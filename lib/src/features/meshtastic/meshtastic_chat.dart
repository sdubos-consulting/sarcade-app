// SPDX-License-Identifier: MPL-2.0
// © SDUBOS Consulting et contributeurs SARCADE

/// Meshtastic messages (lot 28, card « Module Meshtastic, sur le modèle de
/// MeshCore », point 3): a direct message to a node and messages on the
/// primary channel, one thread « Meshtastic · nom » each, kept on this
/// device only, as for MeshCore (meshcore_chat.dart).
///
/// Each sent message goes « envoi… » (given to the module), « envoyé »
/// (taken in its queue, or relayed by a node for the channel), « reçu par
/// le nœud » (acknowledgement of the node, direct messages only) or
/// « échec » (refused, no acknowledgement after the retries of the module,
/// or nothing heard in time). Pure code: the messages go through [send].
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../meshcore/meshcore_chat.dart' show MeshCoreMsgState;
import 'meshtastic_protocol.dart';

/// Same states as MeshCore (same words, same icons).
typedef MeshtasticMsgState=MeshCoreMsgState;

/// Key of the primary channel thread (node threads: « !a1b2c3d4 »).
const meshtasticChannelKey='^0';

class MeshtasticChatMessage {
  final String id, text;
  final bool mine;
  final DateTime at;
  /// Sender of a channel message (its name), null for mine and for a direct one.
  final String? sender;
  MeshtasticMsgState state;
  /// Packet id of a message of mine, to follow its acknowledgement.
  int packetId;
  DateTime? deadline;
  MeshtasticChatMessage({required this.id,required this.text,required this.mine,required this.at,required this.state,this.sender,this.packetId=0});

  Map<String,dynamic> toJson()=>{'id':id,'t':text,'m':mine,'at':at.toUtc().toIso8601String(),'s':state.name,if(sender!=null)'f':sender};
  static MeshtasticChatMessage? fromJson(Object? j){
    if(j is! Map)return null;
    final at=DateTime.tryParse('${j['at']}');
    if(at==null)return null;
    var s=MeshtasticMsgState.values.where((x)=>x.name==j['s']).firstOrNull??MeshtasticMsgState.failed;
    // Still with the module when SARCADE stopped: no answer can come.
    if(s==MeshtasticMsgState.sending)s=MeshtasticMsgState.failed;
    return MeshtasticChatMessage(id:'${j['id']}',text:'${j['t']}',mine:j['m']==true,at:at,state:s,sender:j['f'] as String?);
  }
}

/// One thread: a node (« !a1b2c3d4 ») or the primary channel.
class MeshtasticThread {
  final String key;
  String name;
  final List<MeshtasticChatMessage> messages=[];
  int unread=0;
  MeshtasticThread(this.key,this.name);
  bool get channel=>key==meshtasticChannelKey;
  /// Node number of a direct thread.
  int? get node=>channel?null:meshtasticNum(key);
  MeshtasticChatMessage? get last=>messages.isEmpty?null:messages.last;
}

/// Preference where the threads are kept on this device.
const meshtasticChatsKey='meshtastic_chats';

/// Messages kept per thread.
const meshtasticChatKeep=200;

/// Time given to the module to take a message in its queue, and to the
/// node to acknowledge a direct message (the module retries meanwhile).
const meshtasticQueueWait=Duration(seconds:15), meshtasticAckWait=Duration(minutes:2);

class MeshtasticChats extends ChangeNotifier {
  MeshtasticChats();
  static final MeshtasticChats instance=MeshtasticChats();

  final Map<String,MeshtasticThread> _threads={};
  /// Writes a ToRadio message; null when no module is linked.
  Future<void> Function(Uint8List toRadio,String what)? send;
  /// A new packet id.
  int Function()? newId;
  /// Number of the node of the module (its own messages are not received).
  int? Function()? myNum;
  /// Name of a node, when known.
  String? Function(int num)? nameOf;
  /// Name of the primary channel (« LongFast »), when known.
  String? Function()? channelName;
  /// Shows a notification for a message received (title, text).
  void Function(String title,String body)? notify;
  /// Thread on screen: its messages are read at once, no notification.
  String? openThread;
  /// Expiry checked by a timer (off in the tests).
  bool autoExpire=true;

  Future<void> Function(String key,String? value)? _save;
  Timer? _tick;
  int _seq=0;

  /// Threads, the most recent first.
  List<MeshtasticThread> get threads=>_threads.values.toList()
    ..sort((a,b)=>(b.last?.at??DateTime(2000)).compareTo(a.last?.at??DateTime(2000)));
  MeshtasticThread? thread(String key)=>_threads[key];
  int get unread=>_threads.values.fold(0,(n,t)=>n+t.unread);

  /// Where the threads are kept (the preferences of the device).
  void attach({required String? Function(String key) load,required Future<void> Function(String key,String? value) save}){
    _save=save;
    final raw=load(meshtasticChatsKey);
    if(raw==null||raw.isEmpty)return;
    try{
      final j=jsonDecode(raw);
      if(j is! Map)return;
      _threads.clear();
      j.forEach((k,v){
        if(v is! Map)return;
        final t=MeshtasticThread('$k','${v['name']??k}')..unread=(v['unread'] as num?)?.toInt()??0;
        for(final m in (v['msgs'] as List?)??const []){final x=MeshtasticChatMessage.fromJson(m);if(x!=null)t.messages.add(x);}
        _threads['$k']=t;
      });
      notifyListeners();
    }catch(_){/* unreadable: start again */}
  }

  Future<void> _persist() async {
    final save=_save; if(save==null)return;
    await save(meshtasticChatsKey,jsonEncode({for(final t in _threads.values)t.key:{
      'name':t.name,'unread':t.unread,'msgs':[for(final m in t.messages)m.toJson()]}}));
  }

  /// The thread of a node or of the channel, opened (« Écrire »): created
  /// when new, its name kept up to date.
  MeshtasticThread open(String key,String name){
    final t=_threads.putIfAbsent(key,()=>MeshtasticThread(key,name));
    if(name.isNotEmpty)t.name=name;
    return t;
  }

  /// Thread shown on screen: everything in it is read.
  void markRead(String key){
    final t=thread(key); if(t==null||t.unread==0)return;
    t.unread=0; notifyListeners(); unawaited(_persist());
  }

  void _add(MeshtasticThread t,MeshtasticChatMessage m){
    t.messages.add(m);
    if(t.messages.length>meshtasticChatKeep)t.messages.removeRange(0,t.messages.length-meshtasticChatKeep);
  }

  /// Sends [text] in the thread [key]; the message shows at once
  /// (« envoi… ») and fails when no module is linked or the text is too long.
  Future<MeshtasticChatMessage> write(String key,String name,String text,{DateTime? now}) async {
    final t=open(key,name), at=now??DateTime.now();
    final m=MeshtasticChatMessage(id:'${at.microsecondsSinceEpoch}-${_seq++}',text:text.trim(),mine:true,at:at,state:MeshtasticMsgState.sending);
    _add(t,m);
    await _transmit(t,m,at);
    return m;
  }

  /// « Renvoyer » on a failed message: a new packet.
  Future<void> retry(String key,MeshtasticChatMessage m,{DateTime? now}) async {
    final t=thread(key); if(t==null||!m.mine||m.state!=MeshtasticMsgState.failed)return;
    m.state=MeshtasticMsgState.sending;
    await _transmit(t,m,now??DateTime.now());
  }

  Future<void> _transmit(MeshtasticThread t,MeshtasticChatMessage m,DateTime at) async {
    final out=send, id=newId;
    final to=t.channel?meshtasticBroadcast:t.node;
    if(out==null||id==null||to==null||!meshtasticTextFits(m.text)){m.state=MeshtasticMsgState.failed;notifyListeners();unawaited(_persist());return;}
    m.packetId=id();
    m.deadline=at.add(t.channel?meshtasticQueueWait:meshtasticAckWait);
    notifyListeners();
    try{
      await out(meshtasticSendText(to:to,text:m.text,id:m.packetId),'text');
      _watch();
    }catch(_){
      m.state=MeshtasticMsgState.failed; m.deadline=null;
    }
    notifyListeners(); unawaited(_persist());
  }

  (MeshtasticThread,MeshtasticChatMessage)? _mineOf(int packetId){
    if(packetId==0)return null;
    for(final t in _threads.values){for(final m in t.messages){
      if(m.mine&&m.packetId==packetId)return (t,m);
    }}
    return null;
  }

  /// QueueStatus of the module: the message is taken (sent on LoRa) or
  /// refused (queue full).
  void onQueue(MeshtasticQueue q){
    final found=_mineOf(q.packetId); if(found==null)return;
    final (t,m)=found;
    if(m.state!=MeshtasticMsgState.sending)return;
    if(q.result!=0){m..state=MeshtasticMsgState.failed..deadline=null;}
    else{m.state=MeshtasticMsgState.sent;if(t.channel)m.deadline=null;}
    notifyListeners(); unawaited(_persist());
  }

  /// A packet of the mesh: an acknowledgement (Routing) of one of my
  /// messages, or a text for this device or the primary channel.
  void onPacket(MeshtasticPacket p,{DateTime? now}){
    if(p.encrypted)return;
    if(p.portnum==meshtasticPortRouting){_onRouting(p);return;}
    final text=p.text;
    if(text==null||text.trim().isEmpty)return;
    final me=myNum?.call();
    if(me!=null&&p.from==me)return;
    final name=nameOf?.call(p.from)??meshtasticId(p.from);
    if(p.broadcast){
      if(p.channel!=0)return;
      _receive(open(meshtasticChannelKey,channelName?.call()??''),text,sender:name,now:now);
    }else if(me==null||p.to==me){
      _receive(open(meshtasticId(p.from),name),text,now:now);
    }
  }

  void _onRouting(MeshtasticPacket p){
    final found=_mineOf(p.requestId); if(found==null)return;
    final (t,m)=found;
    final error=readMeshtasticRoutingError(p.payload);
    if(error!=0){
      if(m.state==MeshtasticMsgState.delivered)return;
      m..state=MeshtasticMsgState.failed..deadline=null;
    }else if(!t.channel&&p.from==t.node){
      m..state=MeshtasticMsgState.delivered..deadline=null;
    }else if(m.state==MeshtasticMsgState.sending){
      // Relayed by a node (implicit acknowledgement): sent.
      m.state=MeshtasticMsgState.sent;
      if(t.channel)m.deadline=null;
    }else{
      return;
    }
    notifyListeners(); unawaited(_persist());
  }

  void _receive(MeshtasticThread t,String text,{String? sender,DateTime? now}){
    final at=now??DateTime.now();
    _add(t,MeshtasticChatMessage(id:'${at.microsecondsSinceEpoch}-${_seq++}',text:text,mine:false,at:at,state:MeshtasticMsgState.received,sender:sender));
    if(openThread!=t.key){
      t.unread++;
      notify?.call('Meshtastic · ${t.name}',sender==null?text:'$sender : $text');
    }
    notifyListeners(); unawaited(_persist());
  }

  /// Messages whose answer did not come in time: failed.
  void expire(DateTime now){
    var changed=false;
    for(final t in _threads.values){for(final m in t.messages){
      final d=m.deadline;
      if(m.mine&&d!=null&&(m.state==MeshtasticMsgState.sending||m.state==MeshtasticMsgState.sent)&&now.isAfter(d)){
        m..state=MeshtasticMsgState.failed..deadline=null; changed=true;
      }
    }}
    if(changed){notifyListeners();unawaited(_persist());}
    if(!_threads.values.any((t)=>t.messages.any((m)=>m.deadline!=null))){_tick?.cancel();_tick=null;}
  }

  void _watch(){
    if(!autoExpire||_tick!=null)return;
    _tick=Timer.periodic(const Duration(seconds:2),(_)=>expire(DateTime.now()));
  }

  /// Everything forgotten (tests).
  @visibleForTesting
  void reset(){_threads.clear();openThread=null;_tick?.cancel();_tick=null;send=null;newId=null;myNum=null;nameOf=null;channelName=null;notify=null;_save=null;}
}
