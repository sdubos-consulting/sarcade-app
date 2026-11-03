import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../access/access_session.dart' show accessOrigin;
import 'api_error.dart' show bodyText;

/// Start of a device token (`sdt_…`, docs/accounts-v0.1.md of the server).
const deviceTokenPrefix='sdt_';

/// Enrolled device (lot 26, « Groupes d'organisation et habilitations »,
/// decision 1 of 3 Nov 2026): the token received after the email code (or
/// Cloudflare Access), shown once by the server, kept in the secure storage.
class DeviceSession {
  final String token, email;
  /// Identifier of the enrolment on the server (`device.id`), and the
  /// terminal declared then (`device.device_id`).
  final String? id, deviceId;
  final String method;
  const DeviceSession({required this.token,required this.email,this.id,this.deviceId,this.method='email_code'});

  static DeviceSession? fromJson(Object? j){
    if(j is! Map)return null;
    final token='${j['token']??''}';
    if(!token.startsWith(deviceTokenPrefix))return null;
    return DeviceSession(token:token,email:'${j['email']??''}',id:j['id'] as String?,deviceId:j['device_id'] as String?,
      method:'${j['method']??'email_code'}');
  }
  Map<String,dynamic> toJson()=>{'token':token,'email':email,'id':id,'device_id':deviceId,'method':method};

  /// Answer of `POST /auth/code/verify` or `/auth/access/enroll`.
  static DeviceSession? fromEnrolment(Map<String,dynamic> j){
    final device=j['device'] is Map?Map<String,dynamic>.from(j['device'] as Map):const <String,dynamic>{};
    final account=j['account'] is Map?Map<String,dynamic>.from(j['account'] as Map):const <String,dynamic>{};
    return fromJson({'token':j['token'],'email':account['email']??'','id':device['id'],'device_id':device['device_id'],
      'method':device['method']??'email_code'});
  }
}

/// Device tokens of the servers, one per server (scheme, host, port), and
/// the servers whose token was just refused (« Se connecter » offered).
class AccountManager extends ChangeNotifier {
  AccountManager();
  static final instance=AccountManager();

  static const _prefix='sarcade.account.';
  final _storage=const FlutterSecureStorage();
  final _sessions=<String,DeviceSession>{};
  final _refused=<String,String>{};

  /// Reads the stored tokens at start; a storage failure only means the
  /// person signs in again.
  Future<void> load() async {
    try{
      final all=await _storage.readAll();
      all.forEach((k,v){
        if(!k.startsWith(_prefix))return;
        try{
          final s=DeviceSession.fromJson(jsonDecode(v));
          if(s!=null)_sessions[k.substring(_prefix.length)]=s;
        }catch(_){/* damaged entry: forgotten */}
      });
    }catch(_){/* signed out */}
  }

  DeviceSession? sessionFor(String server)=>_sessions[accessOrigin(server)];
  /// `device_revoked` or `device_token_invalid` after a refusal, until the
  /// next sign-in.
  String? refusedFor(String server)=>_refused[accessOrigin(server)];

  /// `Authorization: Bearer sdt_…` for the calls of the server the token
  /// belongs to (HTTP and WebSocket); nothing for another server.
  Map<String,String> headersFor(Uri url){
    final s=_sessions[_originOf(url)];
    return s==null?const {}:{'Authorization':'Bearer ${s.token}'};
  }

  Future<void> save(String server,DeviceSession s) async {
    final origin=accessOrigin(server);
    _sessions[origin]=s;
    _refused.remove(origin);
    try{await _storage.write(key:'$_prefix$origin',value:jsonEncode(s.toJson()));}catch(_){/* kept for this run */}
    notifyListeners();
  }

  /// Forgets the token ([reason]: refused by the server, « Se connecter »
  /// offered again).
  Future<void> forget(String server,{String? reason}) async {
    final origin=accessOrigin(server);
    final had=_sessions.remove(origin)!=null;
    if(reason!=null)_refused[origin]=reason;
    try{await _storage.delete(key:'$_prefix$origin');}catch(_){}
    if(had||reason!=null)notifyListeners();
  }

  void clearRefused(String server){
    if(_refused.remove(accessOrigin(server))!=null)notifyListeners();
  }

  /// `device.revoked` of the real-time channel: true when it is the token
  /// of this device, then forgotten.
  Future<bool> onDeviceRevoked(String server,Map<String,dynamic> data) async {
    final s=sessionFor(server);
    if(s==null||!revokedIsMine(s,data))return false;
    await forget(server,reason:'device_revoked');
    return true;
  }
}

/// The enrolment named by a `device.revoked` event is this one: its
/// identifier, else the terminal declared at the enrolment.
bool revokedIsMine(DeviceSession s,Map<String,dynamic> data){
  final id='${data['id']??''}', device='${data['device_id']??''}';
  if((s.id??'').isNotEmpty)return id==s.id;
  return device.isNotEmpty&&device==s.deviceId;
}

String _originOf(Uri url){
  final scheme=switch(url.scheme){'wss'=>'https','ws'=>'http',final s=>s};
  if(scheme!='http'&&scheme!='https')return '';
  return accessOrigin(url.replace(scheme:scheme).toString());
}

/// `device_revoked` or `device_token_invalid` when the server refused the
/// device token (401 with `WWW-Authenticate: Bearer`), null otherwise.
String? refusedTokenReason(int status,Map<String,String> headers,String body){
  if(status!=401)return null;
  final w=(headers['www-authenticate']??headers['WWW-Authenticate']??'').toLowerCase();
  if(!w.contains('bearer'))return null;
  try{
    final d=(jsonDecode(body) as Map)['detail'];
    if(d=='device_revoked'||d=='device_token_invalid')return d as String;
  }catch(_){/* not ours */}
  return null;
}

/// A 401 of a call sent with the device token: when the token is refused it
/// is forgotten and the call is given back to send again without it (rights
/// of the Core); otherwise the answer, read, is given back as it was.
Future<(http.Request?,http.StreamedResponse)> checkRefusedToken(AccountManager account,http.BaseRequest request,http.StreamedResponse response) async {
  final bytes=await response.stream.toBytes();
  final again=http.StreamedResponse(Stream.value(bytes),response.statusCode,contentLength:bytes.length,request:response.request,
    headers:response.headers,isRedirect:response.isRedirect,persistentConnection:response.persistentConnection,reasonPhrase:response.reasonPhrase);
  final reason=refusedTokenReason(response.statusCode,response.headers,bodyText(bytes));
  if(reason==null)return (null,again);
  await account.forget(request.url.toString(),reason:reason);
  if(request is! http.Request)return (null,again);
  final retry=http.Request(request.method,request.url)
    ..headers.addAll(request.headers)..bodyBytes=request.bodyBytes..followRedirects=request.followRedirects..maxRedirects=request.maxRedirects;
  retry.headers.remove('authorization');
  return (retry,again);
}
