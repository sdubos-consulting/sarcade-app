/// Télécommandes de relais, a tool of their own (lot 21, card
/// « Télécommandes de relais : fonction à part entière, indépendante de
/// MeshCore », validated on 2 Nov 2026, 5 h 05): the relay is the object,
/// the way the command travels is a setting of each remote
/// ([RemoteTransport]). MeshCore is the only real one today (private
/// message to the box's companion, answer awaited 30 s); Meshtastic and
/// VHF are named in the model for later cards, not offered yet.
///
/// Born in lot 19 inside Outils › MeshCore (card « MeshCore : télécommande
/// de relais (boîtier d'un membre de l'ADRASEC) », 1 Nov 2026, 22 h 03 to
/// 22 h 07). A box built by a member of the ADRASEC drives up to 4 relays:
/// relay n: on = digit 2n−1 four times then `#`, off = digit 2n four times
/// then `#` (1111# / 2222#, 3333# / 4444#…), filled in by themselves and
/// editable. Confirmation = a message of the box within 30 s; else « pas de
/// confirmation » (« Renvoyer »). The state shown is the last confirmed
/// one, « supposé ». Every command and its result go to the logbook kept on
/// this device. Declared by the PCO, used by any operator; kept on this
/// device. Pure code: messages go through the [RemoteLink] of each
/// transport.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../l10n/strings.dart';
import '../../models/comm_group.dart' show myActorId;
import '../meshcore/meshcore_protocol.dart' show meshCorePrefix;

/// Relays per box, at most.
const remoteMaxRelays=4;

/// Time given to the box to answer a command.
const remoteAnswer=Duration(seconds:30);

/// Preference where the remotes, the last states and the logbook are kept.
const remotesKey='relay_remotes';

/// Preference of lot 19 (Outils › MeshCore), read once then emptied.
const remotesOldKey='meshcore_remotes';

/// Logbook lines kept on this device.
const remoteLogKeep=300;

/// How the commands of a remote travel. Only [meshcore] is offered today;
/// [meshtastic] (node, direct message) and [vhf] (frequency and tones)
/// come later, on cards of their own.
enum RemoteTransport { meshcore, meshtastic, vhf }

/// « MeshCore », « Meshtastic », « VHF ».
String remoteTransportName(RemoteTransport t)=>S.t('remote.transport.${t.name}');

/// Same box: MeshCore matches the prefix of the public key.
bool remoteSameTarget(RemoteTransport t,String a,String b)=>switch(t){
  RemoteTransport.meshcore=>meshCorePrefix(a)==meshCorePrefix(b),
  _=>a==b,
};

/// Codes of relay [n] (from 1): `1111#` / `2222#` for the first one.
({String on,String off}) remoteRelayCodes(int n){
  final on='${2*n-1}'*4, off='${2*n}'*4;
  return (on:'$on#',off:'$off#');
}

class RemoteRelay {
  String name, onCode, offCode;
  /// « Lire l'état »: ready, hidden until the box has such a command.
  String? readCode;
  RemoteRelay({required this.name,required this.onCode,required this.offCode,this.readCode});
  /// Relay [n] (from 1) with its codes filled in.
  factory RemoteRelay.numbered(int n){final c=remoteRelayCodes(n);return RemoteRelay(name:S.t('remote.relayN',{'n':'$n'}),onCode:c.on,offCode:c.off);}
  Map<String,dynamic> toJson()=>{'name':name,'on':onCode,'off':offCode,if(readCode!=null)'read':readCode};
  static RemoteRelay? fromJson(Object? j){
    if(j is! Map||j['on'] is! String||j['off'] is! String)return null;
    return RemoteRelay(name:'${j['name']??''}',onCode:j['on'] as String,offCode:j['off'] as String,readCode:j['read'] as String?);
  }
}

/// A box: its name, its transport and who receives the commands
/// ([target]: the public key of the MeshCore companion), its relays (1 to
/// 4).
class Remote {
  final String id;
  String name;
  RemoteTransport transport;
  String target, targetName;
  final List<RemoteRelay> relays;
  Remote({required this.id,required this.name,this.transport=RemoteTransport.meshcore,required this.target,this.targetName='',required this.relays});
  Map<String,dynamic> toJson()=>{'id':id,'name':name,'transport':transport.name,'target':target,'targetName':targetName,
    'relays':[for(final r in relays)r.toJson()]};
  /// Also reads the remotes of lot 19 (`node`, `nodeName`, MeshCore).
  static Remote? fromJson(Object? j){
    if(j is! Map||j['id'] is! String)return null;
    final target=j['target']??j['node'];
    if(target is! String)return null;
    final t=j['transport']==null?RemoteTransport.meshcore:RemoteTransport.values.where((x)=>x.name==j['transport']).firstOrNull;
    if(t==null)return null;
    final relays=[for(final r in (j['relays'] as List?)??const [])?RemoteRelay.fromJson(r)];
    if(relays.isEmpty)return null;
    return Remote(id:j['id'] as String,name:'${j['name']??''}',transport:t,target:target,
      targetName:'${j['targetName']??j['nodeName']??''}',relays:relays.take(remoteMaxRelays).toList());
  }
}

/// A command handed to a transport: refused at once ([failed]), and
/// whether the receiver acknowledged it ([delivered], MeshCore
/// acknowledgement). Read again while the answer is awaited.
abstract class RemoteDelivery {
  bool get failed;
  bool get delivered;
}

/// A transport usable on this device: [ready] (module connected…) and
/// [send] of a command text to the box.
class RemoteLink {
  final bool Function() ready;
  final Future<RemoteDelivery> Function(Remote r,String text) send;
  const RemoteLink({required this.ready,required this.send});
}

/// Where a relay stands: nothing sent ([idle]), command sent and answer
/// awaited ([waiting]), answered ([confirmed]), no answer in 30 s
/// ([noConfirmation]), not sent at all ([failed]).
enum RemoteRelayStatus { idle, waiting, confirmed, noConfirmation, failed }

class RemoteRelayState {
  /// Last confirmed state (« supposé »); null: unknown.
  bool? on;
  DateTime? confirmedAt;
  /// Text sent back by the box with the last confirmation.
  String? reply;
  RemoteRelayStatus status=RemoteRelayStatus.idle;
  /// Last command: true = « Allumer », its time and how it went.
  bool? command;
  DateTime? sentAt;
  RemoteDelivery? delivery;
  /// The receiver acknowledged the command.
  bool get delivered=>delivery?.delivered==true;
  Map<String,dynamic> toJson()=>{if(on!=null)'on':on,if(confirmedAt!=null)'at':confirmedAt!.toUtc().toIso8601String(),if(reply!=null)'reply':reply};
  static RemoteRelayState fromJson(Object? j){
    final s=RemoteRelayState();
    if(j is Map){
      s.on=j['on'] is bool?j['on'] as bool:null;
      s.confirmedAt=DateTime.tryParse('${j['at']}')?.toLocal();
      s.reply=j['reply'] as String?;
      if(s.on!=null&&s.confirmedAt!=null)s.status=RemoteRelayStatus.confirmed;
    }
    return s;
  }
}

/// One line of the logbook kept on this device.
class RemoteLog {
  final DateTime at;
  final String actor, remoteId, remote, text;
  const RemoteLog({required this.at,required this.actor,required this.remoteId,required this.remote,required this.text});
  Map<String,dynamic> toJson()=>{'at':at.toUtc().toIso8601String(),'actor':actor,'rid':remoteId,'remote':remote,'text':text};
  static RemoteLog? fromJson(Object? j){
    if(j is! Map)return null;
    final at=DateTime.tryParse('${j['at']}');
    if(at==null)return null;
    return RemoteLog(at:at.toLocal(),actor:'${j['actor']??''}',remoteId:'${j['rid']??''}',remote:'${j['remote']??''}',text:'${j['text']??''}');
  }
}

/// Text of a logbook line: « Relais 1 allumé · confirmé », « Relais 2
/// éteindre · pas de confirmation », « Relais 1 allumer · échec ».
String remoteLogText(String relay,bool on,RemoteRelayStatus result)=>switch(result){
  RemoteRelayStatus.confirmed=>S.t(on?'remote.log.onConfirmed':'remote.log.offConfirmed',{'relay':relay}),
  RemoteRelayStatus.noConfirmation=>S.t(on?'remote.log.onNoConfirmation':'remote.log.offNoConfirmation',{'relay':relay}),
  _=>S.t(on?'remote.log.onFailed':'remote.log.offFailed',{'relay':relay}),
};

class Remotes extends ChangeNotifier {
  Remotes();
  static final Remotes instance=Remotes();

  final List<Remote> remotes=[];
  final Map<String,List<RemoteRelayState>> _states={};
  final List<RemoteLog> log=[];
  /// Transports usable on this device (MeshCore: `remote_meshcore.dart`).
  final Map<RemoteTransport,RemoteLink> links={};
  /// Who sends (the operator of this device).
  String Function() actor=()=>myActorId??'';
  /// Expiry of the 30 s checked by a timer (off in the tests).
  bool autoExpire=true;

  Future<void> Function(String key,String? value)? _save;
  bool _attached=false;
  Timer? _tick;
  int _seq=0;

  /// Reads the remotes kept on this device, once. Those of lot 19 (kept by
  /// Outils › MeshCore) are taken over as they are, then their old place
  /// is emptied.
  void attach({required String? Function(String key) load,required Future<void> Function(String key,String? value) save}){
    if(_attached)return;
    _attached=true;
    _save=save;
    var raw=load(remotesKey);
    final old=raw==null?load(remotesOldKey):null;
    raw??=old;
    if(raw==null||raw.isEmpty)return;
    try{
      final j=jsonDecode(raw);
      if(j is! Map)return;
      remotes..clear()..addAll([for(final r in (j['remotes'] as List?)??const [])?Remote.fromJson(r)]);
      _states.clear();
      final st=j['states'];
      for(final r in remotes){
        final l=st is Map?st[r.id]:null;
        _states[r.id]=[for(var i=0;i<r.relays.length;i++)RemoteRelayState.fromJson(l is List&&i<l.length?l[i]:null)];
      }
      log..clear()..addAll([for(final e in (j['log'] as List?)??const [])?RemoteLog.fromJson(e)]);
      notifyListeners();
    }catch(_){return;/* unreadable: start again, the old place untouched */}
    if(old!=null)unawaited(_migrate());
  }

  Future<void> _migrate() async {
    try{
      await _persist();
      await _save?.call(remotesOldKey,null);
    }catch(_){/* kept at the old place, taken over at the next start */}
  }

  Future<void> _persist() async {
    final save=_save; if(save==null)return;
    await save(remotesKey,jsonEncode({
      'remotes':[for(final r in remotes)r.toJson()],
      'states':{for(final r in remotes)r.id:[for(final s in states(r))s.toJson()]},
      'log':[for(final e in log)e.toJson()],
    }));
  }

  Remote? byId(String id)=>remotes.where((r)=>r.id==id).firstOrNull;
  /// The remotes of the box listening with [target] (a MeshCore node…).
  List<Remote> ofTarget(RemoteTransport t,String target)=>
    remotes.where((r)=>r.transport==t&&remoteSameTarget(t,r.target,target)).toList();

  /// The transport of [r] can send now (module connected…).
  bool ready(Remote r){
    final l=links[r.transport];
    if(l==null)return false;
    try{return l.ready();}catch(_){return false;}
  }

  List<RemoteRelayState> states(Remote r){
    final l=_states.putIfAbsent(r.id,()=>[]);
    while(l.length<r.relays.length){l.add(RemoteRelayState());}
    if(l.length>r.relays.length)l.removeRange(r.relays.length,l.length);
    return l;
  }

  /// Declared or changed (PCO): kept on this device.
  Future<void> put(Remote r) async {
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
  List<RemoteLog> logOf(String remoteId)=>log.where((e)=>e.remoteId==remoteId).toList().reversed.toList();

  void _write(Remote r,String text,DateTime at){
    log.add(RemoteLog(at:at,actor:actor(),remoteId:r.id,remote:r.name,text:text));
    if(log.length>remoteLogKeep)log.removeRange(0,log.length-remoteLogKeep);
  }

  /// « Allumer » ([on] true) or « Éteindre » relay [index] of [r]: the code
  /// goes through the transport of [r], then the box's answer is awaited
  /// for 30 s.
  Future<void> command(Remote r,int index,bool on,{DateTime? now}) async {
    if(index<0||index>=r.relays.length)return;
    final relay=r.relays[index], s=states(r)[index], at=now??DateTime.now();
    s..command=on..sentAt=at..status=RemoteRelayStatus.waiting..delivery=null;
    notifyListeners();
    final link=links[r.transport];
    RemoteDelivery? d;
    if(link!=null){try{d=await link.send(r,on?relay.onCode:relay.offCode);}catch(_){d=null;}}
    s.delivery=d;
    if(s.sentAt!=at)return; // a newer command replaced this one
    if(d==null||d.failed){
      s.status=RemoteRelayStatus.failed;
      _write(r,remoteLogText(relay.name,on,RemoteRelayStatus.failed),at);
    }else{
      _watch();
    }
    notifyListeners(); unawaited(_persist());
  }

  /// A message of [from] through [t] (the box's answer): it confirms the
  /// oldest command of that box still awaiting an answer.
  void onIncoming(RemoteTransport t,String from,String text,{DateTime? now}){
    final at=now??DateTime.now();
    for(final r in remotes){
      if(r.transport!=t||!remoteSameTarget(t,r.target,from))continue;
      final l=states(r);
      int? best;
      for(var i=0;i<l.length;i++){
        final s=l[i];
        if(s.status==RemoteRelayStatus.waiting&&s.sentAt!=null&&(best==null||s.sentAt!.isBefore(l[best].sentAt!)))best=i;
      }
      if(best==null)continue;
      final s=l[best], on=s.command!;
      s..status=RemoteRelayStatus.confirmed..on=on..confirmedAt=at..reply=text.trim();
      _write(r,remoteLogText(r.relays[best].name,on,RemoteRelayStatus.confirmed),at);
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
        if(s.status==RemoteRelayStatus.waiting&&s.sentAt!=null&&now.difference(s.sentAt!)>=remoteAnswer){
          s.status=RemoteRelayStatus.noConfirmation; changed=true;
          _write(r,remoteLogText(r.relays[i].name,s.command!,RemoteRelayStatus.noConfirmation),s.sentAt!.add(remoteAnswer));
        }
      }
    }
    if(changed){notifyListeners();unawaited(_persist());}
    if(!remotes.any((r)=>states(r).any((s)=>s.status==RemoteRelayStatus.waiting))){_tick?.cancel();_tick=null;}
  }

  void _watch(){
    if(!autoExpire||_tick!=null)return;
    _tick=Timer.periodic(const Duration(seconds:1),(_)=>expire(DateTime.now()));
  }

  /// Everything forgotten (tests).
  @visibleForTesting
  void reset(){remotes.clear();_states.clear();log.clear();links.clear();_tick?.cancel();_tick=null;_save=null;_attached=false;autoExpire=true;
    actor=()=>myActorId??'';}
}
