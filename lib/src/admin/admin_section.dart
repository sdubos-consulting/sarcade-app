import 'dart:async';
import 'package:flutter/material.dart';
import '../account/rights.dart';
import '../l10n/strings.dart';
import '../ui/chevron_row.dart';
import 'admin_accounts_page.dart';
import 'admin_api.dart';
import 'admin_errors.dart';
import 'admin_groups_page.dart';
import 'admin_widgets.dart';
import 'admin_why_page.dart';

/// Paramètres › Administration (lot 26, decision 2 of 3 Nov 2026): shown
/// only when `/me` says `can_administer`. Groups, « Pourquoi ce droit ? »,
/// invitations for every administrator; accounts and devices, transition
/// period and sending of emails for the administrator of the server.
class AdminSection extends StatefulWidget {
  final String server; final MyRights? rights;
  final Widget Function(String label,{String? help,required Widget child}) row;
  final AdminApi? api;
  const AdminSection({super.key,required this.server,required this.rights,required this.row,this.api});
  @override State<AdminSection> createState()=>_AdminSectionState();
}

class _AdminSectionState extends State<AdminSection> {
  late final AdminApi _api=widget.api??AdminApi(widget.server);
  Map<String,dynamic>? _transition, _mail; String? _mailError;

  bool get _serverAdmin=>widget.rights?.isServerAdmin==true;

  @override void initState(){super.initState();if(_serverAdmin)unawaited(_load());}
  @override void dispose(){if(widget.api==null)_api.close();super.dispose();}

  Future<void> _load() async {
    try{final t=await _api.transition();if(mounted)setState(()=>_transition=t);}catch(_){/* older server */}
    try{final m=await _api.mail();if(mounted)setState((){_mail=m;_mailError=null;});}catch(e){if(mounted)setState(()=>_mailError=adminErrorText(e));}
  }

  void _open(Widget Function() page)=>unawaited(Navigator.of(context).push(MaterialPageRoute(builder:(_)=>page())));

  Future<void> _changeTransition() async {
    final current=DateTime.tryParse('${_transition?['until']??''}');
    final choice=await showDialog<String>(context:context,builder:(c)=>AlertDialog(
      title:Text(S.t('admin.transition')),
      content:SizedBox(width:440,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(S.t('admin.transitionHelp')),
        const SizedBox(height:12),
        Text(S.t('admin.transitionWarning'),key:const ValueKey('admin-transition-warning'),
          style:TextStyle(color:Theme.of(c).colorScheme.error,fontWeight:FontWeight.w600)),
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        if(current!=null)TextButton(onPressed:()=>Navigator.pop(c,'none'),child:Text(S.t('admin.transitionNoEnd'))),
        FilledButton(key:const ValueKey('admin-transition-date'),onPressed:()=>Navigator.pop(c,'date'),child:Text(S.t('admin.setEnd'))),
      ]));
    if(choice==null||!mounted)return;
    final until=choice=='none'?null:await pickEndDate(context,initial:current);
    if(choice=='date'&&until==null||!mounted)return;
    try{
      final t=await _api.setTransition(until);
      if(mounted)setState(()=>_transition=t);
    }catch(e){
      if(mounted)await showAdminError(context,e);
    }
  }

  Future<void> _showCodes() async {
    List<Map<String,dynamic>> codes;
    try{codes=await _api.simulatedCodes();}catch(e){if(mounted)await showAdminError(context,e);return;}
    if(!mounted)return;
    await showDialog<void>(context:context,builder:(c)=>AlertDialog(title:Text(S.t('admin.simulatedCodes')),
      content:SizedBox(width:440,child:codes.isEmpty?Text(S.t('admin.noCodes')):ListView(shrinkWrap:true,children:[
        for(final e in codes)ListTile(dense:true,contentPadding:EdgeInsets.zero,
          title:SelectableText('${(e['details'] as Map?)?['code']??''}',style:const TextStyle(fontFamily:'monospace',fontSize:18,letterSpacing:3)),
          subtitle:Text('${(e['details'] as Map?)?['email']??''} · ${adminDate(e['at'])} ${_time(e['at'])}')),
      ])),
      actions:[FilledButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.close')))]));
  }

  static String _time(Object? v){
    final t=DateTime.tryParse('${v??''}')?.toLocal();
    if(t==null)return '';
    String two(int x)=>x.toString().padLeft(2,'0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  String _transitionText(){
    final t=_transition;
    if(t==null)return S.t('admin.loading');
    final until=DateTime.tryParse('${t['until']??''}');
    if(t['active']==false)return S.t('admin.transitionOver',{'date':adminDate(until)});
    return until==null?S.t('admin.transitionOpen'):S.t('admin.transitionUntil',{'date':adminDate(until)});
  }

  String _mailText(){
    final m=_mail;
    if(_mailError!=null)return _mailError!;
    if(m==null)return S.t('admin.loading');
    if(m['delivery']=='smtp')return S.t('admin.mailSmtp',{'host':'${m['host']??''}:${m['port']??''}','from':m['sender']??''});
    final missing=[for(final v in (m['missing'] as List?)??const [])'$v'];
    return S.t('admin.mailSimulated',{'missing':missing.join(', ')});
  }

  @override
  Widget build(BuildContext context){
    final row=widget.row;
    final r=widget.rights;
    // One line per entry, all of it touchable, « › » (lot 29.4).
    Widget open(String key,IconData icon,String title,String help,Widget Function() page)=>
      ChevronRow(key:ValueKey(key),icon:icon,title:title,subtitle:help,onTap:()=>_open(page));
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.only(top:12,bottom:4),child:AdminHint(S.t('admin.intro',{'who':[
        if(r?.isServerAdmin==true)S.t('admin.serverAdmin'),
        for(final a in r?.adminRights??const <Map<String,dynamic>>[])
          if(a['right']!='server_admin')'${S.t('admin.right.${a['right']}')}${a['scope_name']==null?'':' · ${a['scope_name']}'}',
      ].join(', ')}))),
      open('admin-open-groups',Icons.account_tree_outlined,S.t('admin.groups'),S.t('admin.groupsHelp'),()=>AdminGroupsPage(api:_api,rights:r)),
      open('admin-open-why',Icons.help_outline,S.t('admin.why'),S.t('admin.whyHelp'),()=>AdminWhyPage(api:_api)),
      open('admin-open-invitations',Icons.mail_outline,S.t('admin.invitations'),S.t('admin.invitationsHelp'),()=>AdminInvitationsPage(api:_api)),
      if(_serverAdmin)...[
        open('admin-open-accounts',Icons.devices_outlined,S.t('admin.accounts'),S.t('admin.accountsHelp'),()=>AdminAccountsPage(api:_api)),
        // « Période de transition » with its value before « › ».
        ChevronRow(key:const ValueKey('admin-transition'),icon:Icons.event_outlined,title:S.t('admin.transition'),value:_transitionText(),
          onTap:_transition==null?null:_changeTransition),
        if(_transition?['active']!=false)Padding(padding:const EdgeInsets.only(left:42,bottom:6),child:AdminHint(S.t('admin.transitionWarning'),
          color:Theme.of(context).colorScheme.error)),
        row(S.t('admin.mail'),help:_mailText(),child:Align(alignment:Alignment.centerRight,child:Wrap(spacing:8,runSpacing:8,children:[
          if(_mail?['delivery']=='simulated')OutlinedButton(key:const ValueKey('admin-codes'),onPressed:_showCodes,child:Text(S.t('admin.simulatedCodes'))),
          IconButton(tooltip:S.t('settings.eventsRefresh'),onPressed:_load,icon:const Icon(Icons.refresh)),
        ]))),
      ],
    ]);
  }
}
