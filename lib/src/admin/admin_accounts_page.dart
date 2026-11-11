import 'dart:async';
import 'package:flutter/material.dart';
import '../features/map/stations.dart' show platformLabel;
import '../l10n/strings.dart';
import 'admin_api.dart';
import 'admin_errors.dart';
import 'admin_widgets.dart';
import 'admin_why_page.dart';
import '../ui/theme.dart' show searchInputBorder;

/// Comptes et appareils (administrator of the server): accounts by
/// address, their enrolled devices (revocation), disable an account.
class AdminAccountsPage extends StatefulWidget {
  final AdminApi api;
  const AdminAccountsPage({super.key,required this.api});
  @override State<AdminAccountsPage> createState()=>_AdminAccountsPageState();
}

class _AdminAccountsPageState extends State<AdminAccountsPage> {
  final _query=TextEditingController();
  List<Map<String,dynamic>>? _users; String? _error;
  final _devices=<String,List<Map<String,dynamic>>>{};
  Timer? _debounce;

  @override void initState(){super.initState();unawaited(_load());}
  @override void dispose(){_debounce?.cancel();_query.dispose();super.dispose();}

  Future<void> _load() async {
    try{
      final list=await widget.api.users(query:_query.text);
      if(mounted)setState((){_users=list;_error=null;});
    }catch(e){
      if(mounted)setState(()=>_error=adminErrorText(e));
    }
  }

  Future<void> _loadDevices(String userId) async {
    try{
      final list=await widget.api.devices(userId:userId);
      if(mounted)setState(()=>_devices[userId]=list);
    }catch(e){
      if(mounted)await showAdminError(context,e);
    }
  }

  Future<void> _revoke(String userId,Map<String,dynamic> d) async {
    if(!await confirmAdmin(context,S.t('auth.revokeAsk',{'name':d['label']??d['device_id']??''}),body:S.t('auth.revokeBody'),action:S.t('auth.revoke'))||!mounted)return;
    try{
      await widget.api.revokeDevice('${d['id']}');
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('auth.revoked'))));
      await _loadDevices(userId);
    }catch(e){
      if(mounted)await showAdminError(context,e);
    }
  }

  Future<void> _setStatus(Map<String,dynamic> u,bool active) async {
    if(!active&&!await confirmAdmin(context,S.t('admin.disableAsk',{'email':u['email']}),body:S.t('admin.disableBody'),action:S.t('admin.disable')))return;
    try{
      await widget.api.patchUser('${u['id']}',status:active?'active':'disabled');
      await _load();
    }catch(e){
      if(mounted)await showAdminError(context,e);
    }
  }

  @override
  Widget build(BuildContext context){
    final users=_users;
    return AdminScaffold(title:S.t('admin.accounts'),body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:820),child:Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(20,12,20,4),child:TextField(key:const ValueKey('admin-accounts-search'),controller:_query,
        decoration:InputDecoration(isDense:true,prefixIcon:const Icon(Icons.search),hintText:S.t('admin.searchAddress'),border:searchInputBorder),
        onChanged:(_){_debounce?.cancel();_debounce=Timer(const Duration(milliseconds:400),()=>unawaited(_load()));})),
      Expanded(child:_error!=null?Center(child:Text(_error!))
        :users==null?const Center(child:CircularProgressIndicator())
        :users.isEmpty?Center(child:AdminHint(S.t('admin.noAccounts')))
        :ListView(padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),children:[
          for(final u in users)ExpansionTile(key:ValueKey('admin-account-${u['email']}'),
            leading:Icon(u['status']=='disabled'?Icons.person_off_outlined:Icons.person_outline),
            title:Text('${u['email']}'),
            subtitle:AdminHint([
              if(u['status']=='disabled')S.t('admin.disabled'),
              if(adminDate(u['last_login_at']).isNotEmpty)S.t('admin.lastLogin',{'date':adminDate(u['last_login_at'])}),
            ].join(' · ')),
            onExpansionChanged:(open){if(open&&!_devices.containsKey('${u['id']}'))unawaited(_loadDevices('${u['id']}'));},
            childrenPadding:const EdgeInsets.fromLTRB(16,0,16,12),
            children:[
              if(_devices['${u['id']}']==null)const LinearProgressIndicator()
              else if(_devices['${u['id']}']!.isEmpty)Align(alignment:Alignment.centerLeft,child:AdminHint(S.t('auth.devicesNone'))),
              for(final d in _devices['${u['id']}']??const <Map<String,dynamic>>[])ListTile(dense:true,contentPadding:EdgeInsets.zero,
                leading:const Icon(Icons.devices_outlined),
                title:Text('${d['label']??d['device_id']??''}'),
                subtitle:Text([
                  if('${d['platform']??''}'.isNotEmpty)platformLabel('${d['platform']}'),
                  S.t('auth.method.${d['method']=='access'?'access':'email_code'}'),
                  if(adminDate(d['last_seen_at']).isNotEmpty)S.t('auth.lastSeen',{'date':adminDate(d['last_seen_at'])}),
                ].join(' · ')),
                trailing:TextButton(onPressed:()=>_revoke('${u['id']}',d),child:Text(S.t('auth.revoke')))),
              Wrap(spacing:8,runSpacing:8,children:[
                OutlinedButton.icon(icon:const Icon(Icons.help_outline),label:Text(S.t('admin.why')),
                  onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>AdminWhyPage(api:widget.api,email:'${u['email']}')))),
                if(u['status']=='disabled')OutlinedButton(onPressed:()=>_setStatus(u,true),child:Text(S.t('admin.enable')))
                else OutlinedButton(onPressed:()=>_setStatus(u,false),child:Text(S.t('admin.disable'))),
              ]),
            ]),
        ])),
    ]))));
  }
}

/// Invitations waiting for an account, in the groups this administrator sees.
class AdminInvitationsPage extends StatefulWidget {
  final AdminApi api;
  const AdminInvitationsPage({super.key,required this.api});
  @override State<AdminInvitationsPage> createState()=>_AdminInvitationsPageState();
}

class _AdminInvitationsPageState extends State<AdminInvitationsPage> {
  List<Map<String,dynamic>>? _list; String? _error;
  @override void initState(){super.initState();unawaited(_load());}

  Future<void> _load() async {
    try{
      final l=await widget.api.invitations();
      if(mounted)setState((){_list=l;_error=null;});
    }catch(e){
      if(mounted)setState(()=>_error=adminErrorText(e));
    }
  }

  Future<void> _remove(Map<String,dynamic> i) async {
    if(!await confirmAdmin(context,S.t('admin.removeAsk',{'what':i['email'],'name':i['short_name']}),action:S.t('admin.remove'))||!mounted)return;
    try{
      await widget.api.removeInvitation('${i['group_id']}','${i['email']}');
      await _load();
    }catch(e){
      if(mounted)await showAdminError(context,e);
    }
  }

  @override
  Widget build(BuildContext context){
    final list=_list;
    return AdminScaffold(title:S.t('admin.invitations'),body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:820),
      child:_error!=null?Center(child:Text(_error!))
        :list==null?const Center(child:CircularProgressIndicator())
        :list.isEmpty?Center(child:AdminHint(S.t('admin.noInvitations')))
        :ListView(padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),children:[
          AdminHint(S.t('admin.invitationsHelp')),
          for(final i in list)ListTile(leading:const Icon(Icons.mail_outline),title:Text('${i['email']}'),
            subtitle:Text([i['short_name'],S.t('admin.invitedOn',{'date':adminDate(i['invited_at'])}),if('${i['invited_by']??''}'.isNotEmpty)'${i['invited_by']}'].join(' · ')),
            trailing:IconButton(tooltip:S.t('admin.remove'),onPressed:()=>_remove(i),icon:const Icon(Icons.delete_outline))),
        ]))));
  }
}
