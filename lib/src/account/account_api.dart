import 'dart:convert';
import 'package:http/http.dart' as http;
import '../access/access_manager.dart' show AccessHttpClient;
import 'api_error.dart';

/// Sign-in by email code and enrolled devices (lot 26,
/// docs/accounts-v0.1.md of the server).
class AccountApi {
  final String baseUrl; final http.Client _client; final bool _own;
  AccountApi(String server,{http.Client? client}):baseUrl=_trim(server),_client=client??AccessHttpClient(),_own=client==null;
  static String _trim(String s){var t=s.trim();while(t.endsWith('/')){t=t.substring(0,t.length-1);}return t;}
  void close(){if(_own)_client.close();}

  Uri _u(String path)=>Uri.parse('$baseUrl/api/v0.1$path');
  static const _json={'content-type':'application/json'};

  static Object? _decode(http.Response r){
    final text=bodyText(r.bodyBytes);
    return text.trim().isEmpty?null:jsonDecode(text);
  }
  Future<Object?> _expect(String op,Future<http.Response> call,Set<int> ok) async {
    final r=await call;
    if(!ok.contains(r.statusCode))throw ApiError.from(op,r.statusCode,bodyText(r.bodyBytes));
    return _decode(r);
  }
  static Map<String,dynamic> _map(Object? j)=>j is Map?Map<String,dynamic>.from(j):<String,dynamic>{};

  /// `{methods, delivery, code_length, code_ttl_s, resend_after_s, max_attempts}`.
  Future<Map<String,dynamic>> state() async=>_map(await _expect('auth_state',_client.get(_u('/auth/state')),{200}));

  /// 202 `{status, delivery, expires_in_s, resend_after_s, code_length}`.
  Future<Map<String,dynamic>> requestCode(String email) async=>_map(await _expect('auth_code',
    _client.post(_u('/auth/code/request'),headers:_json,body:jsonEncode({'email':email.trim()})),{200,202}));

  /// `{token, device, account, created}`.
  Future<Map<String,dynamic>> verifyCode({required String email,required String code,required String deviceId,String? label,String? platform}) async=>
    _map(await _expect('auth_verify',_client.post(_u('/auth/code/verify'),headers:_json,body:jsonEncode({
      'email':email.trim(),'code':code.trim(),'device_id':deviceId,'label':?label,'platform':?platform})),{200}));

  /// Enrolment without code, the email being checked by Cloudflare Access.
  Future<Map<String,dynamic>> accessEnroll({required String deviceId,String? label,String? platform}) async=>
    _map(await _expect('auth_access',_client.post(_u('/auth/access/enroll'),headers:_json,body:jsonEncode({
      'device_id':deviceId,'label':?label,'platform':?platform})),{200,201}));

  /// Revokes the token of this device on the server.
  Future<void> logout() async {await _expect('auth_logout',_client.post(_u('/auth/logout')),{200});}

  /// Who the server sees; null on an older server.
  Future<Map<String,dynamic>?> me() async {
    final r=await _client.get(_u('/me'));
    if(r.statusCode!=200)return null;
    return _map(_decode(r));
  }

  /// My active devices, each with `current`.
  Future<List<Map<String,dynamic>>> myDevices() async {
    final j=await _expect('my_devices',_client.get(_u('/me/devices')),{200});
    return [for(final d in (j as List?)??const [])if(d is Map)Map<String,dynamic>.from(d)];
  }
  Future<void> revokeMyDevice(String id) async {
    await _expect('my_device_revoke',_client.delete(_u('/me/devices/${Uri.encodeComponent(id)}')),{200,204});
  }
}
