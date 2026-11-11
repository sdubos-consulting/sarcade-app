/// Reach of the server by the calls of the application (card « Diagnostic :
/// messages contradictoires quand le serveur n'est pas joint », validated on
/// 10 Nov 2026, choices 1, 3, 4 and 9). The real time keeps its channel open
/// while the one-off calls fail: the link dot, the Cloudflare line and the
/// Diagnostic now read the same state, with the exact reason (delay passed,
/// Cloudflare access to renew, refused by the server, no network) and the
/// hour of the return (« rétabli à 09:27 »). Pure parts tested.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../access/access_session.dart';
import '../l10n/strings.dart';
import 'sarcade_api.dart' show SarcadeHttpException;

/// timeout: no answer in time; access: the Cloudflare sign-in answered
/// instead of SARCADE; http: refused by the server (5xx, or the code given);
/// answer: an answer that is not the JSON expected; unreachable: no
/// connection; offline: no network on the device.
enum ServerFailureKind{timeout,access,http,answer,unreachable,offline}

@immutable
class ServerFailure {
  final ServerFailureKind kind;
  /// HTTP code ([ServerFailureKind.http]) or seconds ([ServerFailureKind.timeout]).
  final int? value;
  const ServerFailure(this.kind,[this.value]);
  @override bool operator==(Object other)=>other is ServerFailure&&other.kind==kind&&other.value==value;
  @override int get hashCode=>Object.hash(kind,value);
  @override String toString()=>'${kind.name}${value==null?'':':$value'}';
}

/// « Délai dépassé (6 s) », « Accès Cloudflare à renouveler », « Refusé par
/// le serveur (HTTP 502) », « Pas de réseau »…
String serverFailureText(ServerFailure f)=>switch(f.kind){
  ServerFailureKind.timeout=>S.t('diag.fail.timeout',{'s':f.value??6}),
  ServerFailureKind.http=>f.value==null?S.t('diag.fail.answer'):S.t('diag.fail.http',{'code':f.value}),
  _=>S.t('diag.fail.${f.kind.name}'),
};

/// A body that is the Cloudflare sign-in page (or names it) and not SARCADE.
bool isAccessBody(String body){
  final b=body.toLowerCase();
  return b.contains('cloudflareaccess.com')||b.contains('/cdn-cgi/access/');
}

/// Reason of a failed call. [online] false: the device has no network.
ServerFailure classifyServerError(Object e,{bool online=true,int timeoutS=6}){
  if(!online)return const ServerFailure(ServerFailureKind.offline);
  if(e is TimeoutException)return ServerFailure(ServerFailureKind.timeout,timeoutS);
  if(e is AccessRequiredException)return const ServerFailure(ServerFailureKind.access);
  if(e is SarcadeHttpException)return isAccessBody(e.body)?const ServerFailure(ServerFailureKind.access):ServerFailure(ServerFailureKind.http,e.statusCode);
  if(e is FormatException){
    // An HTML page instead of the JSON: the Cloudflare sign-in when it names it.
    final src='${e.source??''}';
    return isAccessBody(src)?const ServerFailure(ServerFailureKind.access):const ServerFailure(ServerFailureKind.answer);
  }
  // Connection refused, name not found, TLS: no answer of the server.
  return const ServerFailure(ServerFailureKind.unreachable);
}

/// State of one server: last answer, failure under way and since when,
/// hour of the return.
@immutable
class ServerReachState {
  final DateTime? lastOk, failingSince, lastFailAt, recoveredAt;
  final ServerFailure? failure;
  const ServerReachState({this.lastOk,this.failingSince,this.lastFailAt,this.recoveredAt,this.failure});
  bool get failing=>failure!=null;
}

class ServerReach extends ChangeNotifier {
  ServerReach._();
  static final instance=ServerReach._();
  /// Automatic new try while the server is not reached (choice 9).
  static const retryEvery=Duration(seconds:30);

  final _by=<String,ServerReachState>{};

  ServerReachState of(String server)=>_by[accessOrigin(server)]??const ServerReachState();

  /// An answer of SARCADE: the failure under way ends (« rétabli à … »).
  void ok(String server,{DateTime? at}){
    final k=accessOrigin(server), s=_by[k]??const ServerReachState(), now=at??DateTime.now();
    _by[k]=ServerReachState(lastOk:now,recoveredAt:s.failing?now:s.recoveredAt,lastFailAt:s.lastFailAt);
    if(s.failing)notifyListeners();
  }

  void fail(String server,ServerFailure f,{DateTime? at}){
    final k=accessOrigin(server), s=_by[k]??const ServerReachState(), now=at??DateTime.now();
    _by[k]=ServerReachState(lastOk:s.lastOk,failingSince:s.failingSince??now,lastFailAt:now,failure:f);
    if(s.failure!=f)notifyListeners();
  }

  @visibleForTesting void reset(){_by.clear();}
}
