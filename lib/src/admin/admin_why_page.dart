import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import '../ui/text_fields_dialog.dart';
import 'admin_api.dart';
import 'admin_errors.dart';
import 'admin_widgets.dart';

/// « Pourquoi ce droit ? » (decision 11 of 23 Oct 2026): for an address,
/// its groups and each right with the path that gives it (« Module ADRASEC
/// ← FNRASEC ← ADRASEC 78 ← paul@adrasec78.fr »). An address without
/// account is accepted: rights of Public and invitations.
class AdminWhyPage extends StatefulWidget {
  final AdminApi api; final String? email;
  const AdminWhyPage({super.key,required this.api,this.email});
  @override State<AdminWhyPage> createState()=>_AdminWhyPageState();
}

class _AdminWhyPageState extends State<AdminWhyPage> {
  Map<String,dynamic>? _r; String? _error, _email; bool _busy=false;

  @override void initState(){
    super.initState();
    _email=widget.email;
    if(_email!=null)unawaited(_load(_email!));
  }

  Future<void> _ask() async {
    final email=await showTextFieldsDialog<String>(context,initial:[_email??''],builder:(c,f,_)=>AlertDialog(
      title:Text(S.t('admin.why')),
      content:TextField(key:const ValueKey('admin-why-email'),controller:f[0],autofocus:true,keyboardType:TextInputType.emailAddress,autocorrect:false,
        decoration:InputDecoration(labelText:S.t('auth.email'))),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(key:const ValueKey('admin-why-go'),onPressed:()=>Navigator.pop(c,f[0].text.trim()),child:Text(S.t('admin.whyShow'))),
      ]));
    if(email!=null&&email.isNotEmpty&&mounted)await _load(email);
  }

  Future<void> _load(String email) async {
    setState((){_busy=true;_error=null;_email=email;});
    try{
      final r=await widget.api.rightsOfEmail(email);
      if(mounted)setState(()=>_r=r);
    }catch(e){
      if(mounted)setState((){_r=null;_error=adminErrorText(e);});
    }finally{
      if(mounted)setState(()=>_busy=false);
    }
  }

  @override
  Widget build(BuildContext context){
    final t=Theme.of(context);
    final r=_r;
    final groups=[for(final g in (r?['groups'] as List?)??const [])if(g is Map)Map<String,dynamic>.from(g)];
    final rights=[for(final x in (r?['rights'] as List?)??const [])if(x is Map)Map<String,dynamic>.from(x)];
    return AdminScaffold(title:S.t('admin.why'),
      actions:[IconButton(tooltip:S.t('admin.whyOther'),onPressed:_ask,icon:const Icon(Icons.search))],
      body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:820),child:ListView(padding:const EdgeInsets.fromLTRB(20,12,20,32),children:[
        if(_email==null)...[
          AdminHint(S.t('admin.whyHelp')),
          const SizedBox(height:12),
          Align(alignment:Alignment.centerLeft,child:FilledButton.icon(key:const ValueKey('admin-why-ask'),onPressed:_ask,icon:const Icon(Icons.search),label:Text(S.t('admin.whyOther')))),
        ]else Text(_email!,style:t.textTheme.headlineSmall),
        if(_busy)const Padding(padding:EdgeInsets.only(top:12),child:LinearProgressIndicator()),
        if(_error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(_error!,style:TextStyle(color:t.colorScheme.error))),
        if(r!=null)...[
          Padding(padding:const EdgeInsets.only(top:4),child:AdminHint([
            r['account']==null?S.t('admin.noAccount'):S.t('admin.hasAccount'),
            if(r['server_admin']==true)S.t('admin.serverAdmin'),
            S.t('admin.modulesOf',{'m':[for(final m in (r['modules'] as List?)??const [])'$m'].join(', ').ifEmpty(S.t('admin.none'))}),
          ].join(' · '))),
          AdminHeading(S.t('admin.rights')),
          if(rights.isEmpty)AdminHint(S.t('admin.whyNone')),
          for(final x in rights)ListTile(key:ValueKey('admin-why-${x['habilitation_id']??x['right']}'),contentPadding:EdgeInsets.zero,
            leading:Icon(x['licensed']==false?Icons.block:Icons.verified_user_outlined,color:x['licensed']==false?t.colorScheme.error:null),
            title:Text('${x['path_text']??x['label']??x['right']}'),
            subtitle:Text([
              if('${x['scope_name']??''}'.isNotEmpty)S.t('admin.on',{'name':x['scope_name']}),
              if(x['until']!=null)S.t('admin.until',{'date':adminDate(x['until'])}),
              if(x['licensed']==false)S.t('admin.notLicensed',{'org':x['organization_name']??''}),
            ].join(' · ').ifEmpty(S.t('admin.byGroup',{'name':x['holder_name']??''})))),
          AdminHeading(S.t('admin.groupsOf')),
          for(final g in groups)ListTile(dense:true,contentPadding:EdgeInsets.zero,leading:Icon(g['direct']==true?Icons.person_outline:Icons.account_tree_outlined),
            title:Text([for(final p in (g['path'] as List?)??const [])'$p'].join(' › ').ifEmpty('${g['short_name']}')),
            subtitle:Text(g['direct']==true?S.t('admin.direct'):S.t('admin.nested'))),
          if(((r['invitations'] as List?)??const []).isNotEmpty)AdminHint(S.t('admin.pendingInvitations',{'n':(r['invitations'] as List).length})),
        ],
      ]))));
  }
}

extension on String {
  String ifEmpty(String other)=>isEmpty?other:this;
}
