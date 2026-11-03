import '../account/api_error.dart';
import '../l10n/strings.dart';

/// Codes of the directory translated into a clear sentence (contract
/// docs/directory-v0.1.md of the server).
const adminErrorCodes={
  'group_not_found','group_not_visible','group_admin_required','member_manager_required','server_admin_required','no_elevation',
  'cycle','too_deep','last_admin','short_name_taken','habilitation_exists','group_has_subgroups','group_has_events','public_not_nested',
  'public_has_no_member_list','public_rights_refused','system_group','unknown_right','scope_not_allowed','invalid_until','until_in_past',
  'invalid_email','invalid_short_name','invalid_name','invalid_color','email_or_group_id','too_many_addresses','member_not_found',
  'invitation_not_found','habilitation_not_found','user_not_found','user_not_visible','admin_required','account_required',
  'licence_refused','not_an_organization','no_licence','licence_too_large','device_not_found','admin_token_required',
};

/// Sentence of a refusal of the console; the path of a cycle and the
/// sentence of the server (in French) when it gives one.
String adminErrorText(Object e,{String Function(String right)? rightLabel}){
  if(e is! ApiError)return S.t('admin.error.offline');
  final code=e.code;
  if(code=='cycle'){
    final path=[for(final p in (e.data['path'] as List?)??const [])'$p'];
    if(S.lang=='fr'&&e.message!=null)return e.message!;
    return S.t('admin.error.cycle',{'path':path.join(' › ')});
  }
  if(code=='too_deep'||code=='last_admin'){
    if(S.lang=='fr'&&e.message!=null)return e.message!;
    return S.t('admin.error.$code',{'max':e.data['max_depth']??8});
  }
  if(code=='no_elevation'){
    final r='${e.data['right']??''}';
    return S.t('admin.error.no_elevation',{'right':r.isEmpty?'':(rightLabel?.call(r)??r)});
  }
  if(code=='licence_refused')return S.t('admin.error.licence_refused',{'reason':e.data['reason']??e.data['status']??''});
  if(adminErrorCodes.contains(code))return S.t('admin.error.$code');
  if(e.status==401)return S.t('admin.error.account_required');
  if(e.status==403)return S.t('admin.error.admin_required');
  return S.t('admin.error.other',{'e':'HTTP ${e.status}${code.isEmpty?'':' · $code'}'});
}
