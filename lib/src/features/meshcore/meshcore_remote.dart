/// Remote control of relays through MeshCore (lot 19, card « MeshCore :
/// télécommande de relais (boîtier d'un membre de l'ADRASEC) », validated on
/// 1 Nov 2026, 22 h 03 to 22 h 07). A box built by a member of the ADRASEC
/// drives up to 4 relays: a MeshCore companion wired to a board switches a
/// relay on or off from the private message it gets, and answers each
/// command by a private message. Relay n: on = digit 2n−1 four times then
/// `#`, off = digit 2n four times then `#` (1111# / 2222#, 3333# / 4444#…),
/// filled in by themselves and editable. Confirmation = a private message of
/// the box's companion within 30 s; else « pas de confirmation »
/// (« Renvoyer »). The state shown is the last confirmed one, « supposé »
/// (the box cannot be asked, and its relays are off after a restart).
/// Every command and its result go to the logbook kept on this device (the
/// server has no entry point for it yet). Declared by the PCO, used by any
/// operator; kept on this device. Pure code: frames go through [send].
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../l10n/strings.dart';
import '../../models/comm_group.dart' show myActorId;
import 'meshcore_chat.dart';
import 'meshcore_protocol.dart';

/// Relays per box, at most.
const meshCoreRemoteMaxRelays=4;

/// Time given to the box to answer a command.
const meshCoreRemoteAnswer=Duration(seconds:30);

/// Preference where the remotes, the last states and the logbook are kept.
const meshCoreRemotesKey='meshcore_remotes';

/// Logbook lines kept on this device.
const meshCoreRemoteLogKeep=300;

/// Codes of relay [n] (from 1): `1111#` / `2222#` for the first one.
({String on,String off}) meshCoreRelayCodes(int n){
  final on='${2*n-1}'*4, off='${2*n}'*4;
  return (on:'$on#',off:'$off#');
}

class MeshCoreRelay {
  String name, onCode, offCode;
  /// « Lire l'état » (point d): ready, hidden until the box has such a
  /// command.
  String? readCode;
  MeshCoreRelay({required this.name,required this.onCode,required this.offCode,this.readCode});
  /// Relay [n] (from 1) with its codes filled in.
  factory MeshCoreRelay.numbered(int n){final c=meshCoreRelayCodes(n);return MeshCoreRelay(name:S.t('remote.relayN',{'n':'$n'}),onCode:c.on,offCode:c.off);}
  Map<String,dynamic> toJson()=>{'name':name,'on':onCode,'off':offCode,if(readCode!=null)'read':readCode};
  static MeshCoreRelay? fromJson(Object? j){
    if(j is! Map||j['on'] is! String||j['off'] is! String)return null;
    return MeshCoreRelay(name:'${j['name']??''}',onCode:j['on'] as String,offCode:j['off'] as String,readCode:j['read'] as String?);
  }
}

/// A box: its name, the companion it listens with, its relays (1 to 4).
class MeshCoreRemote {
  final String id;
  String name, nodeKey, nodeName;
  final List<MeshCoreRelay> relays;
  MeshCoreRemote({required this.id,required this.name,required this.nodeKey,this.nodeName='',required this.relays});
  String get prefix=>meshCorePrefix(nodeKey);
  Map<String,dynamic> toJson()=>{'id':id,'name':name,'node':nodeKey,'nodeName':nodeName,'relays':[for(final r in relays)r.toJson()]};
  static MeshCoreRemote? fromJson(Object? j){
    if(j is! Map||j['id'] is! String||j['node'] is! String)return null;
    final relays=[for(final r in (j['relays'] as List?)??const [])?MeshCoreRelay.fromJson(r)];
    if(relays.isEmpty)return null;
    return MeshCoreRemote(id:j['id'] as String,name:'${j['name']??''}',nodeKey:j['node'] as String,nodeName:'${j['nodeName']??''}',
      relays:relays.take(meshCoreRemoteMaxRelays).toList());
  }
}

/// Where a relay stands: nothing sent ([idle]), command sent and answer
/// awaited ([waiting]), answered ([confirmed]), no answer in 30 s
/// ([noConfirmation]), not sent at all ([failed]).
enum MeshCoreRelayStatus { idle, waiting, confirmed, noConfirmation, failed }

class MeshCoreRelayState {
  /// Last confirmed state (« supposé »); null: unknown.
  bool? on;
  DateTime? confirmedAt;
  /// Text sent back by the box with the last confirmation.
  String? reply;
  MeshCoreRelayStatus status=MeshCoreRelayStatus.idle;
  /// Last command: true = « Allumer », its time and its message.
  bool? command;
  DateTime? sentAt;
  MeshCoreChatMessage? message;
  /// The node acknowledged the message (MeshCore acknowledgement).
  bool get delivered=>message?.state==MeshCoreMsgState.delivered;
  Map<String,dynamic> toJson()=>{if(on!=null)'on':on,if(confirmedAt!=null)'at':confirmedAt!.toUtc().toIso8601String(),if(reply!=null)'reply':reply};
  static MeshCoreRelayState fromJson(Object? j){
    final s=MeshCoreRelayState();
    if(j is Map){
      s.on=j['on'] is bool?j['on'] as bool:null;
      s.confirmedAt=DateTime.tryParse('${j['at']}')?.toLocal();
      s.reply=j['reply'] as String?;
      if(s.on!=null&&s.confirmedAt!=null)s.status=MeshCoreRelayStatus.confirmed;
    }
    return s;
  }
}

/// One line of the logbook kept on this device.
class MeshCoreRemoteLog {
  final DateTime at;
  final String actor, remoteId, remote, text;
  const MeshCoreRemoteLog({required this.at,required this.actor,required this.remoteId,required this.remote,required this.text});
  Map<String,dynamic> toJson()=>{'at':at.toUtc().toIso8601String(),'actor':actor,'rid':remoteId,'remote':remote,'text':text};
  static MeshCoreRemoteLog? fromJson(Object? j){
    if(j is! Map)return null;
    final at=DateTime.tryParse('${j['at']}');
    if(at==null)return null;
    return MeshCoreRemoteLog(at:at.toLocal(),actor:'${j['actor']??''}',remoteId:'${j['rid']??''}',remote:'${j['remote']??''}',text:'${j['text']??''}');
  }
}

/// Text of a logbook line: « Relais 1 allumé · confirmé », « Relais 2
/// éteindre · pas de confirmation », « Relais 1 allumer · échec ».
String meshCoreRemoteLogText(String relay,bool on,MeshCoreRelayStatus result)=>switch(result){
  MeshCoreRelayStatus.confirmed=>S.t(on?'remote.log.onConfirmed':'remote.log.offConfirmed',{'relay':relay}),
  MeshCoreRelayStatus.noConfirmation=>S.t(on?'remote.log.onNoConfirmation':'remote.log.offNoConfirmation',{'relay':relay}),
  _=>S.t(on?'remote.log.onFailed':'remote.log.offFailed',{'relay':relay}),
};

class MeshCoreRemotes extends ChangeNotifier {
  MeshCoreRemotes();
  static final MeshCoreRemotes instance=MeshCoreRemotes();

  final List<MeshCoreRemote> remotes=[];
  final Map<String,List<MeshCoreRelayState>> _states={};
  final List<MeshCoreRemoteLog> log=[];
  /// Sends a private message to the box's companion; by default through
  /// MeshCore (private messages of lot 17, #188).
  Future<MeshCoreChatMessage> Function(String key,String name,String text) send=
    (key,name,text)=>MeshCoreChats.instance.write(key,name,text);
  /// Who sends (the operator of this device).
  String Function() actor=()=>myActorId??'';
  /// Expiry of the 30 s checked by a timer (off in the tests).
  bool autoExpire=true;

  Future<void> Function(String key,String? value)? _save;
  Timer? _tick;
  int _seq=0;

  void attach({required String? Function(String key) load,required Future<void> Function(String key,String? value) save}){
    _save=save;
    final raw=load(meshCoreRemotesKey);
    if(raw==null||raw.isEmpty)return;
    try{
      final j=jsonDecode(raw);
      if(j is! Map)return;
      remotes..clear()..addAll([for(final r in (j['remotes'] as List?)??const [])?MeshCoreRemote.fromJson(r)]);
      _states.clear();
      final st=j['states'];
      for(final r in remotes){
        final l=st is Map?st[r.id]:null;
        _states[r.id]=[for(var i=0;i<r.relays.length;i++)MeshCoreRelayState.fromJson(l is List&&i<l.length?l[i]:null)];
      }
      log..clear()..addAll([for(final e in (j['log'] as List?)??const [])?MeshCoreRemoteLog.fromJson(e)]);
      notifyListeners();
    }catch(_){/* unreadable: start again */}
  }

  Future<void> _persist() async {
    final save=_save; if(save==null)return;
    await save(meshCoreRemotesKey,jsonEncode({
      'remotes':[for(final r in remotes)r.toJson()],
      'states':{for(final r in remotes)r.id:[for(final s in states(r))s.toJson()]},
      'log':[for(final e in log)e.toJson()],
    }));
  }

  MeshCoreRemote? byId(String id)=>remotes.where((r)=>r.id==id).firstOrNull;
  /// The remotes of the box listening with this node.
  List<MeshCoreRemote> ofNode(String key)=>remotes.where((r)=>r.prefix==meshCorePrefix(key)).toList();

  List<MeshCoreRelayState> states(MeshCoreRemote r){
    final l=_states.putIfAbsent(r.id,()=>[]);
    while(l.length<r.relays.length){l.add(MeshCoreRelayState());}
    if(l.length>r.relays.length)l.removeRange(r.relays.length,l.length);
    return l;
  }

  /// Declared or changed (PCO): kept on this device.
  Future<void> put(MeshCoreRemote r) async {
    final i=remotes.indexWhere((x)=>x.id==r.id);
    if(i<0){remotes.add(r);}else{remotes[i]=r;}
    states(r);
    notifyListeners(); await _persist();
  }

  Future<void> remove(String id) async {
    remotes.removeWhere((r)=>r.id==id); _states.remove(id);
    notifyListeners(); await _persist();
  }

  String newId(DateTime now)=>'rc-${now.microsecondsSinceEpoch}-${_seq++}';

  /// Lines of the logbook about [remoteId], the most recent first.
  List<MeshCoreRemoteLog> logOf(String remoteId)=>log.where((e)=>e.remoteId==remoteId).toList().reversed.toList();

  void _write(MeshCoreRemote r,String text,DateTime at){
    log.add(MeshCoreRemoteLog(at:at,actor:actor(),remoteId:r.id,remote:r.name,text:text));
    if(log.length>meshCoreRemoteLogKeep)log.removeRange(0,log.length-meshCoreRemoteLogKeep);
  }

  /// « Allumer » ([on] true) or « Éteindre » relay [index] of [r]: the code
  /// goes as a private message to the box's companion, then its answer is
  /// awaited for 30 s.
  Future<void> command(MeshCoreRemote r,int index,bool on,{DateTime? now}) async {
    if(index<0||index>=r.relays.length)return;
    final relay=r.relays[index], s=states(r)[index], at=now??DateTime.now();
    s..command=on..sentAt=at..status=MeshCoreRelayStatus.waiting..message=null;
    notifyListeners();
    MeshCoreChatMessage? m;
    try{m=await send(r.nodeKey,r.nodeName,on?relay.onCode:relay.offCode);}catch(_){m=null;}
    s.message=m;
    if(s.sentAt!=at)return; // a newer command replaced this one
    if(m==null||m.state==MeshCoreMsgState.failed){
      s.status=MeshCoreRelayStatus.failed;
      _write(r,meshCoreRemoteLogText(relay.name,on,MeshCoreRelayStatus.failed),at);
    }else{
      _watch();
    }
    notifyListeners(); unawaited(_persist());
  }

  /// A private message of a node (the box's answer): it confirms the oldest
  /// command of that box still awaiting an answer.
  void onIncoming(String prefix,String text,{DateTime? now}){
    final at=now??DateTime.now();
    for(final r in remotes){
      if(r.prefix!=meshCorePrefix(prefix))continue;
      final l=states(r);
      int? best;
      for(var i=0;i<l.length;i++){
        final s=l[i];
        if(s.status==MeshCoreRelayStatus.waiting&&s.sentAt!=null&&(best==null||s.sentAt!.isBefore(l[best].sentAt!)))best=i;
      }
      if(best==null)continue;
      final s=l[best], on=s.command!;
      s..status=MeshCoreRelayStatus.confirmed..on=on..confirmedAt=at..reply=text.trim();
      _write(r,meshCoreRemoteLogText(r.relays[best].name,on,MeshCoreRelayStatus.confirmed),at);
      notifyListeners(); unawaited(_persist());
      return;
    }
  }

  /// Commands not answered within 30 s: « pas de confirmation ».
  void expire(DateTime now){
    var changed=false;
    for(final r in remotes){
      final l=states(r);
      for(var i=0;i<l.length;i++){
        final s=l[i];
        if(s.status==MeshCoreRelayStatus.waiting&&s.sentAt!=null&&now.difference(s.sentAt!)>=meshCoreRemoteAnswer){
          s.status=MeshCoreRelayStatus.noConfirmation; changed=true;
          _write(r,meshCoreRemoteLogText(r.relays[i].name,s.command!,MeshCoreRelayStatus.noConfirmation),s.sentAt!.add(meshCoreRemoteAnswer));
        }
      }
    }
    if(changed){notifyListeners();unawaited(_persist());}
    if(!remotes.any((r)=>states(r).any((s)=>s.status==MeshCoreRelayStatus.waiting))){_tick?.cancel();_tick=null;}
  }

  void _watch(){
    if(!autoExpire||_tick!=null)return;
    _tick=Timer.periodic(const Duration(seconds:1),(_)=>expire(DateTime.now()));
  }

  /// Everything forgotten (tests).
  @visibleForTesting
  void reset(){remotes.clear();_states.clear();log.clear();_tick?.cancel();_tick=null;_save=null;autoExpire=true;
    send=(key,name,text)=>MeshCoreChats.instance.write(key,name,text);actor=()=>myActorId??'';}
}
