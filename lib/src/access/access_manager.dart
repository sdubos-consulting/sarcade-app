import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'access_session.dart';

/// Cloudflare Access sessions of the servers (« Accès protégé par Cloudflare
/// Access »): kept in the secure storage of the device (Keystore, Keychain,
/// Windows credentials), one per server, never shown nor logged.
///
/// In a browser nothing is needed: the browser holds the session cookie.
class AccessManager extends ChangeNotifier {
  AccessManager._();
  static final instance=AccessManager._();

  static const _prefix='sarcade.access.';
  final _storage=const FlutterSecureStorage();
  final _sessions=<String,AccessSession>{};
  /// Servers whose last answer was the Cloudflare sign-in.
  final _required=<String>{};

  /// Reads the stored sessions at start; a storage failure only means the
  /// operator signs in again.
  Future<void> load() async {
    if(kIsWeb)return;
    try{
      final all=await _storage.readAll();
      all.forEach((k,v){
        if(!k.startsWith(_prefix))return;
        final s=AccessSession.fromToken(v);
        if(s!=null)_sessions[k.substring(_prefix.length)]=s;
      });
    }catch(_){/* signed out */}
  }

  AccessSession? sessionFor(String server)=>_sessions[accessOrigin(server)];
  bool requiredFor(String server)=>_required.contains(accessOrigin(server));

  /// Headers for a call: the token only goes to the server it belongs to
  /// (a local address never receives it), and never once expired.
  Map<String,String> headersFor(Uri url){
    if(kIsWeb||!(url.scheme=='http'||url.scheme=='https'||url.scheme=='ws'||url.scheme=='wss'))return const {};
    final origin=accessOrigin(url.replace(scheme:url.scheme=='wss'?'https':url.scheme=='ws'?'http':url.scheme).toString());
    final s=_sessions[origin];
    if(s==null||s.expired(DateTime.now().toUtc()))return const {};
    return s.headers;
  }

  /// « Connexion requise » seen on this device, newest last (card « Jeton
  /// Cloudflare redemandé régulièrement », 1 Nov 2026): when, which call,
  /// which answer, and until when the stored token was valid. Shown in the
  /// Diagnostic, never the token itself.
  final challenges=<AccessChallenge>[];
  void noteChallenge(Uri url,int status,{required bool retried,required bool recovered}){
    final s=_sessions[accessOrigin(url.toString())];
    challenges.add(AccessChallenge(at:DateTime.now(),path:url.path,status:status,tokenUntil:s?.expiresAt,retried:retried,recovered:recovered));
    if(challenges.length>20)challenges.removeAt(0);
  }

  /// A stored token still valid for [url]: worth one more try before asking.
  bool hasValidSession(Uri url){
    final s=_sessions[accessOrigin(url.toString())];
    return s!=null&&!s.expired(DateTime.now().toUtc());
  }

  void markRequired(Uri url){
    if(_required.add(accessOrigin(url.toString())))notifyListeners();
  }

  void markOk(Uri url){
    if(_required.remove(accessOrigin(url.toString())))notifyListeners();
  }

  /// Stores the token handed over by the server page. False if it is not a
  /// valid, unexpired token.
  Future<bool> save(String server,String token) async {
    final s=AccessSession.fromToken(token);
    if(s==null||s.expired(DateTime.now().toUtc()))return false;
    final origin=accessOrigin(server);
    _sessions[origin]=s;
    _required.remove(origin);
    try{await _storage.write(key:'$_prefix$origin',value:s.token);}catch(_){/* kept for this run */}
    notifyListeners();
    return true;
  }

  Future<void> signOut(String server) async {
    final origin=accessOrigin(server);
    _sessions.remove(origin);
    try{await _storage.delete(key:'$_prefix$origin');}catch(_){}
    notifyListeners();
  }
}

/// HTTP client of the application: adds the Access session to the calls of
/// its server and recognises when the Cloudflare sign-in answered instead,
/// so that « Connexion requise » is not mistaken for « Hors connexion ».
class AccessHttpClient extends http.BaseClient {
  final http.Client _inner; final AccessManager access;
  AccessHttpClient({http.Client? inner,AccessManager? access}):_inner=inner??http.Client(),access=access??AccessManager.instance;

  bool _challenged(http.StreamedResponse r){
    // Redirections are followed: a call that ends on the Cloudflare sign-in
    // page (or is refused by Access) did not reach SARCADE.
    final Uri? landed=switch(r){http.BaseResponseWithUrl x=>x.url,_=>null};
    return isAccessChallenge(r.statusCode,r.headers)||(landed!=null&&isAccessPage(landed));
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.addAll(access.headersFor(request.url));
    var response=await _inner.send(request);
    if(_challenged(response)){
      // A token still valid: one more try a second later before asking for
      // a new one (a passing refusal is not the end of the session).
      final again=request is http.Request&&access.hasValidSession(request.url)?_copy(request):null;
      if(again!=null){
        await response.stream.drain<void>();
        await Future<void>.delayed(const Duration(seconds:1));
        final first=response.statusCode;
        response=await _inner.send(again);
        if(!_challenged(response)){
          access.noteChallenge(request.url,first,retried:true,recovered:true);
          if(response.statusCode<500)access.markOk(request.url);
          return response;
        }
      }
      access.noteChallenge(request.url,response.statusCode,retried:again!=null,recovered:false);
      access.markRequired(request.url);
      await response.stream.drain<void>();
      throw AccessRequiredException(accessOrigin(request.url.toString()));
    }
    if(response.statusCode<500)access.markOk(request.url);
    return response;
  }

  http.Request _copy(http.Request r)=>http.Request(r.method,r.url)
    ..headers.addAll(r.headers)..bodyBytes=r.bodyBytes..followRedirects=r.followRedirects..maxRedirects=r.maxRedirects;

  @override void close()=>_inner.close();
}

/// One « Connexion requise » of the Diagnostic.
class AccessChallenge {
  final DateTime at; final String path; final int status; final DateTime? tokenUntil;
  /// A second try was made; it succeeded (no sign-in asked).
  final bool retried, recovered;
  const AccessChallenge({required this.at,required this.path,required this.status,this.tokenUntil,this.retried=false,this.recovered=false});
}
