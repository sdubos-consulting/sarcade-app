/// Lines of « Liaisons » read live (card « Windows : pastille de liaison
/// grise alors que le Diagnostic dit « Tout fonctionne » », lot 19, points
/// 2, 7 and 9): the event refused by the server, the initial loading of the
/// map, the real time. Each problem is orange, so « Tout fonctionne » only
/// shows when everything really works, with its action: « Choisir un
/// événement » (Paramètres › Général) or « Réessayer ».
library;

import '../../l10n/strings.dart';
import '../../offline/event_access.dart';
import '../map/map_load_status.dart';

/// Same shape as the lines of diagnostics_panel.dart.
typedef LinkDiagLine=({String block,String label,String value,String? state});

/// « Événement : inconnu de ce serveur » / « accès refusé (HTTP 403) »;
/// null while the server serves the event.
LinkDiagLine? eventAccessDiagLine(String block,EventAccess access,{int? status})=>switch(access){
  EventAccess.ok=>null,
  EventAccess.unknown=>(block:block,label:S.t('diagnostics.event'),value:S.t('diag.event.unknown'),state:'orange'),
  EventAccess.refused=>(block:block,label:S.t('diagnostics.event'),
    value:'${S.t('diag.event.refused')}${status==null?'':' (HTTP $status)'}',state:'orange'),
};

/// « Chargement de la carte : OK / en cours / échec : raison ».
LinkDiagLine mapLoadDiagLine(String block,MapLoadStatus map)=>(block:block,label:S.t('diag.mapLoad'),
  value:switch(map.phase){
    MapLoadPhase.ok=>S.t('diag.mapLoad.ok'),
    MapLoadPhase.failed=>map.reason==null?S.t('diag.mapLoad.failed'):'${S.t('diag.mapLoad.failed')} : ${map.reason}',
    _=>S.t('diag.mapLoad.loading'),
  },
  state:map.phase==MapLoadPhase.ok?'green':'orange');

/// « Temps réel : connecté / déconnecté »; disconnected is a problem
/// (orange) once a map is open; [connected] null: nothing to say.
LinkDiagLine realtimeDiagLine(String block,{required bool? connected})=>(block:block,label:S.t('diag.realtime'),
  value:S.t(connected==true?'diag.connected':'diag.disconnected'),state:connected==null?null:connected?'green':'orange');

/// The live lines, in this order: event, map, real time.
List<LinkDiagLine> liveLinkLines(String block,{required EventAccess access,int? refusedStatus,MapLoadStatus? map,bool? realtime}){
  final event=eventAccessDiagLine(block,access,status:refusedStatus);
  return [
    ?event,
    if(map!=null)mapLoadDiagLine(block,map),
    realtimeDiagLine(block,connected:realtime??(map==null?null:false)),
  ];
}

/// Action of a line: 'chooseEvent', 'retry', or null.
String? linkDiagAction(LinkDiagLine l){
  if(l.state!='orange')return null;
  if(l.label==S.t('diagnostics.event'))return 'chooseEvent';
  if(l.label==S.t('diag.mapLoad'))return l.value==S.t('diag.mapLoad.loading')?null:'retry';
  if(l.label==S.t('diag.realtime'))return 'retry';
  return null;
}
