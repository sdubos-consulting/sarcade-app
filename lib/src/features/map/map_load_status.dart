/// Initial loading of the map and what the link dot tells (card « Windows :
/// pastille de liaison grise alors que le Diagnostic dit « Tout
/// fonctionne » », lot 19, points 1 to 5, 7 and 9).
///
/// The map is « started » once its initial load is done (latest positions,
/// points of interest, then real time). A failure of this load was
/// swallowed: grey dot for ever, empty map, no real time, and the
/// Diagnostic said « Tout fonctionne ». Now the reason of the last failure
/// is kept, written to the startup log (demarrage.log on Windows, the
/// console elsewhere), shown in the Diagnostic with « Réessayer », and the
/// dot turns orange with a word instead of grey.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../offline/event_access.dart';
import '../../platform/startup_report.dart';
import '../../services/sarcade_api.dart' show SarcadeHttpException;
import 'stations.dart' show ServerLink, serverLink;

/// waiting: not tried yet (first seconds); loading: under way; ok: loaded;
/// failed: the last try failed ([MapLoadStatus.reason]).
enum MapLoadPhase{waiting,loading,ok,failed}

class MapLoadStatus extends ChangeNotifier {
  MapLoadStatus({void Function(String line)? log}):_log=log??StartupReport.note;
  final void Function(String line) _log;

  /// Status of the open map, read by the Diagnostic.
  static MapLoadStatus? active;

  MapLoadPhase phase=MapLoadPhase.waiting;
  /// Reason of the last failure, kept until a load succeeds.
  String? reason;
  DateTime? failedAt;
  /// Failures in a row.
  int failures=0;
  /// « Réessayer »: loads the map again (or reopens the real time).
  VoidCallback? onRetry;

  void begin(){phase=MapLoadPhase.loading;notifyListeners();}

  void succeeded(){
    if(failures>0)_log('carte : chargement initial réussi après $failures échec(s)');
    phase=MapLoadPhase.ok; reason=null; failedAt=null; failures=0;
    notifyListeners();
  }

  /// Written to the log at the first failure and when the reason changes,
  /// not at every retry.
  void failed(Object error){
    final text=loadFailureReason(error);
    failures++; failedAt=DateTime.now();
    if(failures==1||text!=reason)_log('carte : échec du chargement initial ($text)');
    phase=MapLoadPhase.failed; reason=text;
    notifyListeners();
  }

  void retry()=>onRetry?.call();
}

/// Short readable reason: HTTP code and body of a server answer, the
/// message of any other error (cut at 300 characters).
String loadFailureReason(Object error){
  final text=error is SarcadeHttpException
    ?'HTTP ${error.statusCode}${error.body.trim().isEmpty?'':' : ${error.body.trim()}'}'
    :'$error';
  final one=text.replaceAll(RegExp(r'\s+'),' ').trim();
  return one.length>300?'${one.substring(0,300)}…':one;
}

/// Why the dot is not the usual one: the event refused by the server, or
/// the map not loaded while the server answers.
enum LinkIssue{none,eventUnknown,eventRefused,mapNotLoaded}

LinkIssue linkIssue({required EventAccess access,required MapLoadPhase map,required bool serverAnswers}){
  if(access==EventAccess.unknown)return LinkIssue.eventUnknown;
  if(access==EventAccess.refused)return LinkIssue.eventRefused;
  // Offline, the map cannot load either: « Coupée » says it better.
  if(map==MapLoadPhase.failed&&serverAnswers)return LinkIssue.mapNotLoaded;
  return LinkIssue.none;
}

/// Word next to the orange dot (« Carte non chargée », « Événement
/// inconnu », « Accès refusé »); null for [LinkIssue.none].
String? linkIssueWord(LinkIssue issue)=>issue==LinkIssue.none?null:S.t('diag.pill.${issue.name}');

/// Orange of the dot for an issue.
const linkIssueColour=Colors.orange;

/// Dot of the map pill: colour, label of its tooltip, word shown next to
/// it. Orange with a word for an issue; grey « Connexion… » only for the
/// first seconds (a failed load offline is « Coupée »).
({Color colour,String label,String? word}) mapLinkDot({required bool started,required MapLoadPhase map,
    required EventAccess access,required bool syncOk,required bool realtime,required ColorScheme scheme}){
  final word=linkIssueWord(linkIssue(access:access,map:map,serverAnswers:syncOk));
  if(word!=null)return (colour:linkIssueColour,label:word,word:word);
  final state=started||map==MapLoadPhase.failed?serverLink(syncOk:syncOk,realtime:realtime):null;
  final colour=switch(state){ServerLink.direct=>const Color(0xFF2E9D4B),ServerLink.slowed=>Colors.orange,ServerLink.cut=>scheme.error,null=>scheme.outline};
  final label=state==null?S.t('links.starting'):S.t('links.${state.name}');
  return (colour:colour,label:label,word:state==ServerLink.slowed||state==ServerLink.cut?label:null);
}
