/// Private conversations with MeshCore nodes (lot 17, card « MeshCore :
/// nœuds sur la carte et discussion directe avec un nœud », validated on
/// 1 Nov 2026, 11 h 58). One thread « MeshCore · nom du nœud » per node,
/// kept on this device only (sharing through the server: later). Each sent
/// message goes « envoyé », then « reçu par le nœud » (MeshCore
/// acknowledgement) or « échec »; the answers of the node arrive in the
/// thread and as a notification. Pure code: the frames go through [send].
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'meshcore_protocol.dart';

/// State of a message: written, given to the module ([sending]), sent on
/// LoRa ([sent]), acknowledged by the node ([delivered]), lost ([failed]);
/// [received] for a message of the node.
enum MeshCoreMsgState { sending, sent, delivered, failed, received }

class MeshCoreChatMessage {
  final String id, text;
  final bool mine;
  final DateTime at;
  MeshCoreMsgState state;
  /// Acknowledgement awaited (RESP_CODE_SENT), until it comes or the
  /// [deadline] passes.
  int? ack;
  DateTime? deadline;
  int attempt;
  MeshCoreChatMessage({required this.id,required this.text,required this.mine,required this.at,required this.state,this.attempt=0});

  Map<String,dynamic> toJson()=>{'id':id,'t':text,'m':mine,'at':at.toUtc().toIso8601String(),'s':state.name};
  static MeshCoreChatMessage? fromJson(Object? j){
    if(j is! Map)return null;
    final at=DateTime.tryParse('${j['at']}');
    if(at==null)return null;
    var s=MeshCoreMsgState.values.where((x)=>x.name==j['s']).firstOrNull??MeshCoreMsgState.failed;
    // Still with the module when SARCADE stopped: no acknowledgement can
    // come any more.
    if(s==MeshCoreMsgState.sending)s=MeshCoreMsgState.failed;
    return MeshCoreChatMessage(id:'${j['id']}',text:'${j['t']}',mine:j['m']==true,at:at,state:s);
  }
}

/// One thread: a node (prefix of its key) and its messages.
class MeshCoreThread {
  final String prefix;
  String name;
  final List<MeshCoreChatMessage> messages=[];
  int unread=0;
  MeshCoreThread(this.prefix,this.name);
  MeshCoreChatMessage? get last=>messages.isEmpty?null:messages.last;
}

/// Preference where the threads are kept on this device.
const meshCoreChatsKey='meshcore_chats';

/// Messages kept per thread.
const meshCoreChatKeep=200;

/// Time given to the module to answer RESP_CODE_SENT, and the least time
/// waited for the acknowledgement of the node.
const meshCoreSendAnswer=Duration(seconds:10), meshCoreAckLeast=Duration(seconds:20);

class MeshCoreChats extends ChangeNotifier {
  MeshCoreChats();
  static final MeshCoreChats instance=MeshCoreChats();

  final Map<String,MeshCoreThread> _threads={};
  /// Last signal to noise ratio heard from a node (its messages).
  final Map<String,double> snr={};
  /// Sends a frame to the module; null when no module is connected.
  Future<void> Function(Uint8List frame,String what)? send;
  /// Shows a notification for a message of a node (title, text).
  void Function(String title,String body)? notify;
  /// Thread on screen: its messages are read at once, no notification.
  String? openThread;
  /// Expiry of the acknowledgements checked by a timer (off in the tests).
  bool autoExpire=true;
  /// Every message of a node, also given here (lot 19: answers of a box of
  /// relays, see meshcore_remote.dart).
  void Function(String prefix,String text,DateTime at)? onIncoming;

  Future<void> Function(String key,String? value)? _save;
  Timer? _tick;
  int _seq=0;

  /// Threads, the most recent first.
  List<MeshCoreThread> get threads=>_threads.values.toList()
    ..sort((a,b)=>(b.last?.at??DateTime(2000)).compareTo(a.last?.at??DateTime(2000)));
  MeshCoreThread? thread(String prefix)=>_threads[meshCorePrefix(prefix)];
  int get unread=>_threads.values.fold(0,(n,t)=>n+t.unread);

  /// Where the threads are kept (the preferences of the device).
  void attach({required String? Function(String key) load,required Future<void> Function(String key,String? value) save}){
    _save=save;
    final raw=load(meshCoreChatsKey);
    if(raw==null||raw.isEmpty)return;
    try{
      final j=jsonDecode(raw);
      if(j is! Map)return;
      _threads.clear();
      j.forEach((k,v){
        if(v is! Map)return;
        final t=MeshCoreThread('$k','${v['name']??k}')..unread=(v['unread'] as num?)?.toInt()??0;
        for(final m in (v['msgs'] as List?)??const []){final x=MeshCoreChatMessage.fromJson(m);if(x!=null)t.messages.add(x);}
        _threads['$k']=t;
      });
      notifyListeners();
    }catch(_){/* unreadable: start again */}
  }

  Future<void> _persist() async {
    final save=_save; if(save==null)return;
    await save(meshCoreChatsKey,jsonEncode({for(final t in _threads.values)t.prefix:{
      'name':t.name,'unread':t.unread,'msgs':[for(final m in t.messages)m.toJson()]}}));
  }

  /// The thread of a node, opened (« Écrire »): created when new, its name
  /// kept up to date.
  MeshCoreThread open(String key,String name){
    final p=meshCorePrefix(key);
    final t=_threads.putIfAbsent(p,()=>MeshCoreThread(p,name));
    if(name.isNotEmpty)t.name=name;
    return t;
  }

  /// Thread shown on screen: everything in it is read.
  void markRead(String prefix){
    final t=thread(prefix); if(t==null||t.unread==0)return;
    t.unread=0; notifyListeners(); unawaited(_persist());
  }

  void _add(MeshCoreThread t,MeshCoreChatMessage m){
    t.messages.add(m);
    if(t.messages.length>meshCoreChatKeep)t.messages.removeRange(0,t.messages.length-meshCoreChatKeep);
  }

  /// Sends [text] to the node; the message shows at once (« envoi… ») and
  /// fails when no module is connected or the text is too long.
  Future<MeshCoreChatMessage> write(String key,String name,String text,{DateTime? now}) async {
    final t=open(key,name), at=now??DateTime.now();
    final m=MeshCoreChatMessage(id:'${at.microsecondsSinceEpoch}-${_seq++}',text:text.trim(),mine:true,at:at,state:MeshCoreMsgState.sending);
    _add(t,m);
    await _transmit(t,m,at);
    return m;
  }

  /// « Renvoyer » on a failed message: next attempt (3 at most).
  Future<void> retry(String prefix,MeshCoreChatMessage m,{DateTime? now}) async {
    final t=thread(prefix); if(t==null||!m.mine||m.state!=MeshCoreMsgState.failed)return;
    m.attempt=(m.attempt+1).clamp(0,3);
    m.state=MeshCoreMsgState.sending;
    await _transmit(t,m,now??DateTime.now());
  }

  Future<void> _transmit(MeshCoreThread t,MeshCoreChatMessage m,DateTime at) async {
    final out=send;
    if(out==null||!meshCoreTextFits(m.text)){m.state=MeshCoreMsgState.failed;notifyListeners();unawaited(_persist());return;}
    m.deadline=at.add(meshCoreSendAnswer);
    notifyListeners();
    try{
      await out(sendTextMessage(t.prefix,m.text,at:at,attempt:m.attempt),'SEND_TXT_MSG');
      _watch();
    }catch(_){
      m.state=MeshCoreMsgState.failed; m.deadline=null;
    }
    notifyListeners(); unawaited(_persist());
  }

  /// The oldest message still with the module, waiting for RESP_CODE_SENT.
  MeshCoreChatMessage? get _waitingAnswer{
    MeshCoreChatMessage? best;
    for(final t in _threads.values){for(final m in t.messages){
      if(m.mine&&m.state==MeshCoreMsgState.sending&&m.ack==null&&(best==null||m.at.isBefore(best.at)))best=m;
    }}
    return best;
  }

  /// RESP_CODE_SENT: the module sent it on LoRa; the acknowledgement [ack]
  /// is awaited during the round trip it suggests (20 s at least).
  void onSent(int ack,Duration timeout,{DateTime? now}){
    final m=_waitingAnswer; if(m==null)return;
    final wait=timeout<meshCoreAckLeast?meshCoreAckLeast:timeout*2;
    m..state=MeshCoreMsgState.sent..ack=ack..deadline=(now??DateTime.now()).add(wait);
    notifyListeners(); unawaited(_persist());
  }

  /// An error answer of the module while a message waits for it: failed.
  void onError(){
    final m=_waitingAnswer; if(m==null)return;
    m..state=MeshCoreMsgState.failed..deadline=null;
    notifyListeners(); unawaited(_persist());
  }

  /// PUSH_CODE_SEND_CONFIRMED: the node acknowledged the message.
  void onConfirmed(int ack){
    for(final t in _threads.values){for(final m in t.messages){
      if(m.mine&&m.ack==ack&&m.state!=MeshCoreMsgState.delivered){
        m..state=MeshCoreMsgState.delivered..deadline=null;
        notifyListeners(); unawaited(_persist());
        return;
      }
    }}
  }

  /// A message of a node: in its thread, and a notification unless the
  /// thread is on screen. [nameOf] finds the node among the contacts.
  void onReceived(MeshCoreIncoming i,{String? Function(String prefix)? nameOf,DateTime? now}){
    if(i.text.isEmpty)return;
    final name=nameOf?.call(i.prefix)??thread(i.prefix)?.name??i.prefix;
    final t=open(i.prefix,name), at=now??DateTime.now();
    if(i.snr!=null)snr[t.prefix]=i.snr!;
    _add(t,MeshCoreChatMessage(id:'${at.microsecondsSinceEpoch}-${_seq++}',text:i.text,mine:false,at:at,state:MeshCoreMsgState.received));
    if(openThread!=t.prefix){
      t.unread++;
      notify?.call('MeshCore · ${t.name}',i.text);
    }
    onIncoming?.call(t.prefix,i.text,at);
    notifyListeners(); unawaited(_persist());
  }

  /// Messages whose answer or acknowledgement did not come in time: failed.
  void expire(DateTime now){
    var changed=false;
    for(final t in _threads.values){for(final m in t.messages){
      final d=m.deadline;
      if(m.mine&&d!=null&&(m.state==MeshCoreMsgState.sending||m.state==MeshCoreMsgState.sent)&&now.isAfter(d)){
        m..state=MeshCoreMsgState.failed..deadline=null; changed=true;
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
  void reset(){_threads.clear();snr.clear();openThread=null;_tick?.cancel();_tick=null;send=null;notify=null;onIncoming=null;_save=null;}
}
