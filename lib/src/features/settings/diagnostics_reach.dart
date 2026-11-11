/// Lines of the Diagnostic that depend on the server being reached (card
/// « Diagnostic : messages contradictoires quand le serveur n'est pas
/// joint », validated on 10 Nov 2026, choices 1 to 9). One cause at the top
/// of « À vérifier » with the exact reason, the consequences under it in
/// grey « en attente du serveur » and not counted; « Dernière
/// synchronisation » once, in Liaisons; itinerary on the device in grey
/// while the server is not reached; block « Serveur » « Non joint depuis
/// 09:23 »; public address « inconnue (serveur non joint) »; « rétabli à
/// 09:27 » on the return. Pure functions, tested.
library;

import '../../l10n/strings.dart';
import '../../services/server_reach.dart';

typedef ReachLine=({String block,String label,String value,String? state});

String _two(int v)=>v.toString().padLeft(2,'0');
String _lower(String s)=>s.isEmpty?s:s[0].toLowerCase()+s.substring(1);

/// « 09:23 » today, « 09/11 09:23 » another day.
String diagClock(DateTime t,{DateTime? now}){
  final l=t.toLocal(), n=(now??DateTime.now()).toLocal();
  final hm='${_two(l.hour)}:${_two(l.minute)}';
  return l.year==n.year&&l.month==n.month&&l.day==n.day?hm:'${_two(l.day)}/${_two(l.month)} $hm';
}

/// « Rétabli à 09:27 » stays one hour after the return.
bool showsRecovered(ServerReachState r,{DateTime? now})=>!r.failing&&r.recoveredAt!=null
  &&(now??DateTime.now()).difference(r.recoveredAt!)<const Duration(hours:1);

/// The single cause at the top of « À vérifier »: « Serveur : Délai dépassé
/// (6 s) · depuis 09:23 · nouvel essai toutes les 30 s »; null while the
/// server answers.
ReachLine? serverCauseLine(String block,ServerReachState r,{DateTime? now}){
  final f=r.failure; if(f==null)return null;
  return (block:block,label:S.t('diag.server'),
    value:[serverFailureText(f),if(r.failingSince!=null)S.t('diag.since',{'t':diagClock(r.failingSince!,now:now)}),
      S.t('diag.retryEvery',{'s':ServerReach.retryEvery.inSeconds})].join(' · '),
    state:'red');
}

/// « Temps de réponse du serveur »: « 63 ms », « 63 ms · rétabli à 09:27 »,
/// or « Non joint : Délai dépassé (6 s) ».
ReachLine responseDiagLine(String block,{required ServerReachState reach,int? ms,DateTime? now}){
  final label=S.t('diag.response');
  final f=reach.failure;
  if(f!=null)return (block:block,label:label,value:S.t('diag.notReached',{'why':serverFailureText(f)}),state:'red');
  final back=showsRecovered(reach,now:now)?S.t('diag.recovered',{'t':diagClock(reach.recoveredAt!,now:now)}):null;
  if(ms==null)return (block:block,label:label,value:back??'—',state:back==null?null:'green');
  return (block:block,label:label,value:['$ms ms',?back].join(' · '),state:ms>1500?'orange':'green');
}

/// « Dernière synchronisation » (choice 4): « réussie à 09:23 », or « échec
/// à 09:25 : délai dépassé · dernière réussite à 09:23 ».
ReachLine syncDiagLine(String block,{DateTime? okAt,DateTime? failedAt,ServerFailure? failure,DateTime? now}){
  final label=S.t('diag.lastSync');
  if(failedAt!=null&&(okAt==null||failedAt.isAfter(okAt))){
    return (block:block,label:label,value:[
      S.t('diag.syncFailed',{'t':diagClock(failedAt,now:now),'why':_lower(failure==null?S.t('diag.unknown'):serverFailureText(failure))}),
      if(okAt!=null)S.t('diag.syncLastOk',{'t':diagClock(okAt,now:now)}),
    ].join(' · '),state:'orange');
  }
  if(okAt!=null)return (block:block,label:label,value:S.t('diag.syncOk',{'t':diagClock(okAt,now:now)}),state:'green');
  return (block:block,label:label,value:'—',state:null);
}

/// « Calcul d'itinéraire » (choice 5): grey « sur l'appareil (serveur non
/// joint) » while the server is not reached; orange only when the server
/// answers without an engine.
ReachLine routingDiagLine(String block,{required bool reached,required bool engine,required bool device}){
  final where=engine?'server':device?'device':'none';
  final label=S.t('diag.routing'), value=S.t('diag.routing.$where');
  if(!reached)return (block:block,label:label,value:'$value ${S.t('diag.notReachedShort')}',state:'off');
  return (block:block,label:label,value:value,state:switch(where){'server'=>'green','device'=>'orange',_=>'red'});
}

/// Block « Serveur » while the server is not reached (choice 6).
ReachLine serverWaitingLine(String block,ServerReachState r,{DateTime? now})=>(block:block,label:S.t('diag.state'),
  value:r.failingSince==null?S.t('diag.notReachedNow'):S.t('diag.notReachedSince',{'t':diagClock(r.failingSince!,now:now)}),state:'off');

/// « IP publique » (choice 7): seen by the server, so unknown while it is
/// not reached.
String publicIpValue(Map<String,dynamic>? client,{required bool reached})=>
  !reached?S.t('diag.publicIpUnknown'):'${client?['ip']??'—'}';

/// Lines that only follow from the server: shown under the cause, in grey.
bool dependsOnServer(ReachLine l)=>l.block==S.t('diag.server')||l.block==S.t('diag.eventServices')
  ||{S.t('diag.response'),S.t('diag.lastSync'),S.t('diag.routing'),S.t('diag.access'),S.t('diag.publicIp'),S.t('diag.server')}.contains(l.label);

/// « À vérifier » (choices 1 and 8): without [cause], the lines in red or
/// orange. With it, the cause first, then the problems that do not follow
/// from the server; the consequences go to [waiting] (grey, not counted).
/// [accessCause]: the cause is the Cloudflare access, its line is the cause.
({List<ReachLine> problems,List<ReachLine> waiting}) summaryProblems(List<ReachLine> all,{ReachLine? cause,bool accessCause=false}){
  bool bad(ReachLine l)=>l.state=='red'||l.state=='orange';
  if(cause==null)return (problems:[for(final l in all)if(bad(l))l],waiting:const []);
  final waiting=<ReachLine>[]; final blocks=<String>{};
  final wait=S.t('diag.waitingServer'), response=S.t('diag.response'), access=S.t('diag.access');
  for(final l in all){
    if(!dependsOnServer(l)||l.label==response||(accessCause&&l.label==access))continue;
    final server=l.block==S.t('diag.server')||l.block==S.t('diag.eventServices');
    if(server){if(blocks.add(l.block))waiting.add((block:l.block,label:l.block,value:wait,state:'off'));continue;}
    if(l.label==S.t('diag.publicIp'))continue;
    waiting.add((block:l.block,label:l.label,value:wait,state:'off'));
  }
  return (problems:[cause,for(final l in all)if(bad(l)&&!dependsOnServer(l))l],waiting:waiting);
}
