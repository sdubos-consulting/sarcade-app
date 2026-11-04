import 'dart:convert';
import 'package:http/http.dart' as http;
import '../access/access_manager.dart' show AccessHttpClient;
import '../account/api_error.dart';

/// Console d'administration (lot 26): groups of organisation, members,
/// habilitations, accounts and devices, transition, sending of emails
/// (docs/directory-v0.1.md and docs/accounts-v0.1.md of the server). Every
/// refusal is an [ApiError] with the code of the contract.
class AdminApi {
  final String baseUrl; final http.Client _client; final bool _own;
  AdminApi(String server,{http.Client? client}):baseUrl=_trim(server),_client=client??AccessHttpClient(),_own=client==null;
  static String _trim(String s){var t=s.trim();while(t.endsWith('/')){t=t.substring(0,t.length-1);}return t;}
  void close(){if(_own)_client.close();}

  Uri _u(String path,[Map<String,String>? query])=>Uri.parse('$baseUrl/api/v0.1$path').replace(queryParameters:query==null||query.isEmpty?null:query);
  static String _id(String v)=>Uri.encodeComponent(v);
  static const _json={'content-type':'application/json'};

  Future<Object?> _expect(String op,Future<http.Response> call,[Set<int> ok=const {200}]) async {
    final r=await call;
    final text=bodyText(r.bodyBytes);
    if(!ok.contains(r.statusCode))throw ApiError.from(op,r.statusCode,text);
    return text.trim().isEmpty?null:jsonDecode(text);
  }
  static Map<String,dynamic> _map(Object? j)=>j is Map?Map<String,dynamic>.from(j):<String,dynamic>{};
  static List<Map<String,dynamic>> _list(Object? j)=>[for(final x in (j as List?)??const [])if(x is Map)Map<String,dynamic>.from(x)];

  Future<Map<String,dynamic>> _get(String op,String path,[Map<String,String>? q]) async=>_map(await _expect(op,_client.get(_u(path,q))));
  Future<List<Map<String,dynamic>>> _getList(String op,String path,[Map<String,String>? q]) async=>_list(await _expect(op,_client.get(_u(path,q))));
  Future<Map<String,dynamic>> _send(String op,String method,String path,[Object? body,Set<int> ok=const {200,201}]) async {
    final u=_u(path), b=body==null?null:jsonEncode(body);
    final call=switch(method){
      'POST'=>_client.post(u,headers:b==null?null:_json,body:b),
      'PUT'=>_client.put(u,headers:_json,body:b),
      'PATCH'=>_client.patch(u,headers:_json,body:b),
      _=>_client.delete(u),
    };
    return _map(await _expect(op,call,ok));
  }

  // Groups
  Future<Map<String,dynamic>> catalogue()=>_get('catalogue','/admin/directory/catalogue');
  Future<List<Map<String,dynamic>>> groups()=>_getList('groups','/admin/groups');
  Future<Map<String,dynamic>> group(String id)=>_get('group','/admin/groups/${_id(id)}');
  Future<Map<String,dynamic>> createGroup({required String shortName,String? name,String? description,String? color,String? parentId,bool memberOfParent=true})=>
    _send('group_create','POST','/admin/groups',{'short_name':shortName,'name':?name,'description':?description,'color':?color,
      'parent_id':?parentId,'member_of_parent':memberOfParent});
  /// [fields]: short_name, name, description, color, parent_id (null: organisation).
  Future<Map<String,dynamic>> patchGroup(String id,Map<String,dynamic> fields)=>_send('group_update','PATCH','/admin/groups/${_id(id)}',fields);
  Future<void> deleteGroup(String id)=>_send('group_delete','DELETE','/admin/groups/${_id(id)}');

  // Members
  Future<Map<String,dynamic>> members(String id)=>_get('members','/admin/groups/${_id(id)}/members');
  Future<Map<String,dynamic>> addMemberEmail(String id,String email)=>_send('member_add','POST','/admin/groups/${_id(id)}/members',{'email':email.trim()});
  Future<Map<String,dynamic>> addMemberGroup(String id,String groupId)=>_send('member_add','POST','/admin/groups/${_id(id)}/members',{'group_id':groupId});
  /// `{added, invited, already, invalid: [lines]}`.
  Future<Map<String,dynamic>> importMembers(String id,String csv)=>_send('members_import','POST','/admin/groups/${_id(id)}/members/import',{'csv':csv});
  Future<void> removeUser(String id,String userId)=>_send('member_remove','DELETE','/admin/groups/${_id(id)}/members/users/${_id(userId)}');
  Future<void> removeMemberGroup(String id,String memberId)=>_send('member_remove','DELETE','/admin/groups/${_id(id)}/members/groups/${_id(memberId)}');
  Future<void> removeInvitation(String id,String email)=>_send('invitation_remove','DELETE','/admin/groups/${_id(id)}/invitations/${_id(email)}');
  Future<List<Map<String,dynamic>>> invitations()=>_getList('invitations','/admin/invitations');

  // Habilitations
  Future<Map<String,dynamic>> grant(String groupId,{required String right,String? scopeGroupId,DateTime? until})=>
    _send('habilitation_grant','POST','/admin/groups/${_id(groupId)}/habilitations',
      {'right':right,'scope_group_id':?scopeGroupId,'until':?until?.toUtc().toIso8601String()});
  Future<Map<String,dynamic>> setUntil(String habilitationId,DateTime? until)=>
    _send('habilitation_until','PATCH','/admin/habilitations/${_id(habilitationId)}',{'until':until?.toUtc().toIso8601String()});
  Future<void> revokeHabilitation(String habilitationId)=>_send('habilitation_revoke','DELETE','/admin/habilitations/${_id(habilitationId)}');

  // « Pourquoi ce droit ? »
  Future<Map<String,dynamic>> rightsOfEmail(String email)=>_get('rights','/admin/rights',{'email':email.trim()});
  Future<Map<String,dynamic>> rightsOfUser(String userId)=>_get('rights','/admin/users/${_id(userId)}/rights');

  // Licence of an organisation
  Future<Map<String,dynamic>> licence(String id)=>_get('licence','/admin/groups/${_id(id)}/licence');
  Future<Map<String,dynamic>> putLicence(String id,List<int> bytes) async=>
    _map(await _expect('licence_put',_client.put(_u('/admin/groups/${_id(id)}/licence'),headers:_json,body:bytes)));
  Future<void> deleteLicence(String id)=>_send('licence_delete','DELETE','/admin/groups/${_id(id)}/licence');

  // Accounts and enrolled devices (administrator of the server)
  Future<List<Map<String,dynamic>>> users({String? query})=>_getList('users','/admin/users',{if(query!=null&&query.trim().isNotEmpty)'q':query.trim()});
  Future<Map<String,dynamic>> patchUser(String userId,{String? status,String? displayName})=>
    _send('user_update','PATCH','/admin/users/${_id(userId)}',{'status':?status,'display_name':?displayName});
  Future<List<Map<String,dynamic>>> devices({String? userId,bool includeRevoked=false})=>_getList('devices','/admin/devices',
    {'user_id':?userId,if(includeRevoked)'include_revoked':'true'});
  Future<Map<String,dynamic>> revokeDevice(String id)=>_send('device_revoke','POST','/admin/devices/${_id(id)}/revoke');

  // Transition and emails
  Future<Map<String,dynamic>> transition()=>_get('transition','/transition');
  Future<Map<String,dynamic>> setTransition(DateTime? until)=>_send('transition','PUT','/admin/transition',{'until':until?.toUtc().toIso8601String()});
  Future<Map<String,dynamic>> mail()=>_get('mail','/admin/mail');
  /// « Envoyer un e-mail d'essai » (lot 28): `{status: sent|simulated, to}`.
  Future<Map<String,dynamic>> mailTest()=>_send('mail_test','POST','/admin/mail/test');

  // Échéances (lot 28): `{items, summary, tls, manual}`.
  Future<Map<String,dynamic>> deadlines()=>_get('deadlines','/admin/deadlines');
  Future<Map<String,dynamic>> saveDeadlines(List<Map<String,dynamic>> manual)=>
    _send('deadlines','PUT','/admin/deadlines',{'items':manual});

  /// Codes written in the security journal while the sending is simulated.
  Future<List<Map<String,dynamic>>> simulatedCodes() async=>[
    for(final e in await _getList('journal','/admin/security-journal',{'category':'auth','limit':'50'}))
      if(e['action']=='login_code_simulated')e];
}
