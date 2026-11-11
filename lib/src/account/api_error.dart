/// Refusal of the server with its code (lot 26, docs/accounts-v0.1.md and
/// docs/directory-v0.1.md of the server): `{"detail": "code"}` or
/// `{"detail": {"error": "code", …}}`. Pure code.
library;

import 'dart:convert';

class ApiError implements Exception {
  final String operation; final int status;
  /// `invalid_code`, `cycle`, `last_admin`…; empty when the body says nothing.
  final String code;
  /// The other fields of the refusal (`attempts_left`, `path`, `message`…).
  final Map<String,dynamic> data;
  const ApiError(this.operation,this.status,this.code,[this.data=const {}]);

  factory ApiError.from(String operation,int status,String body){
    Object? detail;
    try{
      final j=jsonDecode(body);
      detail=j is Map?j['detail']:null;
    }catch(_){/* not JSON (proxy page) */}
    if(detail is String)return ApiError(operation,status,detail);
    if(detail is Map){
      final d=Map<String,dynamic>.from(detail);
      return ApiError(operation,status,'${d['error']??''}',d);
    }
    // FastAPI validation (422, list of fields): an invalid request.
    return ApiError(operation,status,detail is List?'invalid_request':'');
  }

  /// Seconds before asking again (429).
  int? get retryAfterS=>(data['retry_after_s'] as num?)?.toInt();
  /// Sentence written by the server (`cycle`, `too_deep`, `last_admin`).
  String? get message{final m=data['message'];return m is String&&m.trim().isNotEmpty?m.trim():null;}

  @override String toString()=>'${operation}_http_$status${code.isEmpty?'':':$code'}';
}

/// Body of an answer as text (UTF-8 whatever the headers say).
String bodyText(List<int> bytes)=>utf8.decode(bytes,allowMalformed:true);
