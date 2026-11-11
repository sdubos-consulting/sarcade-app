import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../account/rights.dart';
import '../l10n/strings.dart';
import '../ui/color_palette.dart';
import '../ui/text_fields_dialog.dart';
import 'admin_api.dart';
import 'admin_tree.dart';
import 'admin_widgets.dart';
import 'admin_why_page.dart';

/// Rights of the catalogue (`GET /admin/directory/catalogue`): label, kind
/// and scope of each.
class RightsCatalogue {
  final List<Map<String,dynamic>> rights;
  const RightsCatalogue(this.rights);
  factory RightsCatalogue.fromJson(Map<String,dynamic> j)=>RightsCatalogue([for(final r in (j['rights'] as List?)??const [])if(r is Map)Map<String,dynamic>.from(r)]);
  Map<String,dynamic>? of(String right)=>rights.where((r)=>r['right']==right).firstOrNull;
  String label(String right)=>'${of(right)?['label']??right}';
  /// `server`, `group`, `either` or `none`.
  String scope(String right)=>'${of(right)?['scope']??'none'}';
}

/// Paramètres › Administration › Groupes: tree of the organisations on the
/// left and the sheet of the chosen group on a computer; the tree, then the
/// sheet on its own page on a phone.
class AdminGroupsPage extends StatefulWidget {
  final AdminApi api; final MyRights? rights;
  const AdminGroupsPage({super.key,required this.api,this.rights});
  @override State<AdminGroupsPage> createState()=>_AdminGroupsPageState();
}

class _AdminGroupsPageState extends State<AdminGroupsPage> {
  List<Map<String,dynamic>>? _groups; RightsCatalogue _catalogue=const RightsCatalogue([]);
  String? _error, _selected;
  int _rev=0;

  @override void initState(){super.initState();unawaited(_load());}

  Future<void> _load() async {
    try{
      final list=await widget.api.groups();
      try{_catalogue=RightsCatalogue.fromJson(await widget.api.catalogue());}catch(_){/* labels from the codes */}
      if(mounted)setState((){_groups=list;_error=null;_rev++;if(_selected!=null&&!list.any((g)=>g['id']==_selected))_selected=null;});
    }catch(e){
      if(mounted)setState(()=>_error='$e');
    }
  }

  Future<void> _newOrganization()=>newGroupDialog(context,api:widget.api,parent:null).then((g){
    if(g!=null&&mounted){setState(()=>_selected='${g['id']}');unawaited(_load());}
  });

  void _open(String id,bool wide){
    if(wide){setState(()=>_selected=id);return;}
    unawaited(Navigator.of(context).push(MaterialPageRoute(builder:(_)=>AdminScaffold(title:S.t('admin.groups'),
      body:GroupPanel(api:widget.api,groupId:id,groups:_groups??const [],catalogue:_catalogue,rights:widget.rights,
        onChanged:_load,onOpen:(other)=>_open(other,false),onDeleted:(){Navigator.of(context).maybePop();unawaited(_load());})))));
  }

  Widget _tree(bool wide){
    final groups=_groups!;
    final lines=groupTree(groups);
    return ListView(key:const ValueKey('admin-tree'),padding:const EdgeInsets.symmetric(vertical:8),children:[
      for(final l in lines)_line(l,wide),
      if(widget.rights?.isServerAdmin==true)Padding(padding:const EdgeInsets.all(12),child:Align(alignment:Alignment.centerLeft,
        child:OutlinedButton.icon(key:const ValueKey('admin-new-org'),onPressed:_newOrganization,icon:const Icon(Icons.add),label:Text(S.t('admin.newOrganization'))))),
    ]);
  }

  Widget _line(GroupLine l,bool wide){
    final g=l.group, id='${g['id']}';
    final c=groupCounts(g);
    final t=Theme.of(context);
    return ListTile(key:ValueKey('admin-group-$id'),dense:true,selected:wide&&_selected==id,
      contentPadding:EdgeInsetsDirectional.only(start:12+20.0*l.depth,end:12),
      leading:CircleAvatar(radius:7,backgroundColor:groupColor(g['color'])),
      title:Text([g['short_name'],if(g['system']==true)S.t('admin.system')].join(' · '),style:const TextStyle(fontWeight:FontWeight.w600)),
      subtitle:Text([
        if('${g['name']??''}'.isNotEmpty&&g['name']!=g['short_name'])'${g['name']}',
        if(g['id']!='public')S.t('admin.membersCount',{'n':c.users}),
        if(c.invitations>0)S.t('admin.invitationsCount',{'n':c.invitations}),
      ].join(' · '),style:t.textTheme.bodySmall),
      onTap:()=>_open(id,wide));
  }

  @override
  Widget build(BuildContext context){
    final groups=_groups;
    return AdminScaffold(title:S.t('admin.groups'),actions:[IconButton(tooltip:S.t('settings.eventsRefresh'),onPressed:_load,icon:const Icon(Icons.refresh))],
      body:_error!=null&&groups==null?Center(child:Padding(padding:const EdgeInsets.all(20),child:Text(_error!)))
        :groups==null?const Center(child:CircularProgressIndicator())
        :LayoutBuilder(builder:(context,box){
          final wide=box.maxWidth>=900;
          if(!wide)return _tree(false);
          return Row(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            SizedBox(width:340,child:_tree(true)),
            const VerticalDivider(width:1),
            Expanded(child:_selected==null?Center(child:AdminHint(S.t('admin.chooseGroup')))
              :GroupPanel(key:ValueKey('panel-$_selected-$_rev'),api:widget.api,groupId:_selected!,groups:groups,catalogue:_catalogue,rights:widget.rights,
                onChanged:_load,onOpen:(id)=>setState(()=>_selected=id),onDeleted:(){setState(()=>_selected=null);unawaited(_load());})),
          ]);
        }));
  }
}

/// « Nouvelle organisation » ([parent] null) or « Nouveau sous-groupe »;
/// the group created, null when cancelled or refused.
Future<Map<String,dynamic>?> newGroupDialog(BuildContext context,{required AdminApi api,required Map<String,dynamic>? parent}) async {
  var memberOfParent=true;
  final r=await showTextFieldsDialog<List<String>>(context,initial:const ['',''],builder:(c,f,set)=>AlertDialog(
    title:Text(parent==null?S.t('admin.newOrganization'):S.t('admin.newSubgroupOf',{'name':parent['short_name']})),
    content:SizedBox(width:420,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      TextField(key:const ValueKey('admin-group-short'),controller:f[0],autofocus:true,maxLength:40,decoration:InputDecoration(labelText:S.t('admin.shortName'),hintText:'ADRASEC 92')),
      TextField(key:const ValueKey('admin-group-name'),controller:f[1],decoration:InputDecoration(labelText:S.t('admin.fullName'))),
      if(parent!=null)SwitchListTile(contentPadding:EdgeInsets.zero,value:memberOfParent,onChanged:(v)=>set(()=>memberOfParent=v),
        title:Text(S.t('admin.memberOfParent',{'name':parent['short_name']})),subtitle:Text(S.t('admin.memberOfParentHelp',{'name':parent['short_name']}))),
    ])),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
      FilledButton(key:const ValueKey('admin-group-create'),onPressed:()=>Navigator.pop(c,[f[0].text.trim(),f[1].text.trim()]),child:Text(S.t('admin.create'))),
    ]));
  if(r==null||r[0].isEmpty||!context.mounted)return null;
  try{
    return await api.createGroup(shortName:r[0],name:r[1].isEmpty?null:r[1],parentId:parent?['id'] as String?,memberOfParent:memberOfParent);
  }catch(e){
    if(context.mounted)await showAdminError(context,e);
    return null;
  }
}

/// Sheet of one group: identity and attachment, members (addresses, CSV,
/// groups), sub-groups, habilitations with their end date, licence of the
/// organisation.
class GroupPanel extends StatefulWidget {
  final AdminApi api; final String groupId; final List<Map<String,dynamic>> groups;
  final RightsCatalogue catalogue; final MyRights? rights;
  final VoidCallback onChanged, onDeleted; final ValueChanged<String> onOpen;
  const GroupPanel({super.key,required this.api,required this.groupId,required this.groups,required this.catalogue,this.rights,
    required this.onChanged,required this.onOpen,required this.onDeleted});
  @override State<GroupPanel> createState()=>_GroupPanelState();
}

class _GroupPanelState extends State<GroupPanel> {
  Map<String,dynamic>? _g, _licence; String? _error;

  @override void initState(){super.initState();unawaited(_load());}

  bool get _admin=>_g?['can_admin']==true;
  bool get _members=>_g?['can_manage_members']==true||_admin;
  bool get _public=>widget.groupId=='public'||_g?['id']=='public';
  bool get _serverAdmin=>widget.rights?.isServerAdmin==true;
  String get _name=>'${_g?['short_name']??''}';

  Future<void> _load() async {
    try{
      final g=await widget.api.group(widget.groupId);
      Map<String,dynamic>? lic;
      if(g['organization']==true){try{lic=await widget.api.licence(widget.groupId);}catch(_){/* not allowed */}}
      if(mounted)setState((){_g=g;_licence=lic;_error=null;});
    }catch(e){
      if(mounted)setState(()=>_error='$e');
    }
  }

  /// Runs a change, then reads the group again (and the tree).
  Future<void> _do(Future<Object?> Function() change,{String? done}) async {
    try{
      await change();
      if(!mounted)return;
      if(done!=null)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(done)));
      widget.onChanged();
      await _load();
    }catch(e){
      if(mounted)await showAdminError(context,e,rightLabel:widget.catalogue.label);
    }
  }

  // --- Identity and attachment -----------------------------------------------------------
  Future<void> _edit() async {
    final g=_g!;
    var color=groupColor(g['color']).toARGB32();
    final r=await showTextFieldsDialog<List<String>>(context,initial:['${g['short_name']??''}','${g['name']??''}','${g['description']??''}'],
      builder:(c,f,set)=>AlertDialog(title:Text(S.t('admin.editGroup')),
        content:SizedBox(width:440,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          TextField(controller:f[0],maxLength:40,decoration:InputDecoration(labelText:S.t('admin.shortName'))),
          TextField(controller:f[1],decoration:InputDecoration(labelText:S.t('admin.fullName'))),
          TextField(controller:f[2],maxLines:3,minLines:1,decoration:InputDecoration(labelText:S.t('admin.description'))),
          const SizedBox(height:12),
          Text(S.t('admin.color'),style:Theme.of(c).textTheme.labelLarge),
          const SizedBox(height:6),
          ColorGrid(colors:paletteWith(color),selected:color,onPick:(v)=>set(()=>color=v)),
        ]))),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
          FilledButton(onPressed:()=>Navigator.pop(c,[f[0].text.trim(),f[1].text.trim(),f[2].text.trim()]),child:Text(S.t('common.save'))),
        ]));
    if(r==null||!mounted)return;
    final patch=<String,dynamic>{
      if(r[0].isNotEmpty&&r[0]!=g['short_name'])'short_name':r[0],
      if(r[1]!='${g['name']??''}')'name':r[1],
      if(r[2]!='${g['description']??''}')'description':r[2],
      if(groupHex(color)!='${g['color']??''}'.toUpperCase())'color':groupHex(color),
    };
    if(patch.isNotEmpty)await _do(()=>widget.api.patchGroup(widget.groupId,patch),done:S.t('admin.saved'));
  }

  /// « Rattacher à… »: another group this administrator administers, or
  /// none (an organisation, administrator of the server).
  Future<void> _move() async {
    final mine=widget.groupId;
    final choices=[for(final g in widget.groups)if(g['id']!=mine&&g['system']!=true&&g['can_admin']==true)g];
    const none='\u0000none';
    var pick='${_g!['parent_id']??none}';
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(
      title:Text(S.t('admin.move',{'name':_name})),
      content:SizedBox(width:420,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        DropdownButtonFormField<String>(key:const ValueKey('admin-move-parent'),initialValue:choices.any((g)=>g['id']==pick)||(pick==none&&_serverAdmin)?pick:null,isExpanded:true,
          decoration:InputDecoration(labelText:S.t('admin.parent')),
          items:[
            if(_serverAdmin)DropdownMenuItem(value:none,child:Text(S.t('admin.noParent'))),
            for(final g in choices)DropdownMenuItem(value:'${g['id']}',child:Text('${g['short_name']}',overflow:TextOverflow.ellipsis)),
          ],
          onChanged:(v)=>set(()=>pick=v??pick)),
        const SizedBox(height:8),
        AdminHint(S.t('admin.moveHelp')),
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('common.save'))),
      ])));
    if(ok!=true||!mounted||pick=='${_g!['parent_id']??none}')return;
    await _do(()=>widget.api.patchGroup(mine,{'parent_id':pick==none?null:pick}),done:S.t('admin.saved'));
  }

  Future<void> _delete() async {
    if(!await confirmAdmin(context,S.t('admin.deleteAsk',{'name':_name}),body:S.t('admin.deleteBody'),action:S.t('common.delete'))||!mounted)return;
    try{
      await widget.api.deleteGroup(widget.groupId);
      widget.onDeleted();
    }catch(e){
      if(mounted)await showAdminError(context,e);
    }
  }

  Future<void> _newSubgroup() async {
    final g=await newGroupDialog(context,api:widget.api,parent:_g);
    if(g!=null){widget.onChanged();widget.onOpen('${g['id']}');}
  }

  // --- Members ---------------------------------------------------------------------------
  Future<void> _addEmail() async {
    final email=await showTextFieldsDialog<String>(context,initial:const [''],builder:(c,f,_)=>AlertDialog(
      title:Text(S.t('admin.addEmail')),
      content:TextField(key:const ValueKey('admin-member-email'),controller:f[0],autofocus:true,keyboardType:TextInputType.emailAddress,autocorrect:false,
        decoration:InputDecoration(labelText:S.t('auth.email'),helperText:S.t('admin.addEmailHelp'),helperMaxLines:3)),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(key:const ValueKey('admin-member-add'),onPressed:()=>Navigator.pop(c,f[0].text.trim()),child:Text(S.t('admin.add'))),
      ]));
    if(email==null||email.isEmpty||!mounted)return;
    Map<String,dynamic>? r;
    await _do(() async=>r=await widget.api.addMemberEmail(widget.groupId,email));
    if(!mounted||r==null)return;
    final kind=r!['kind']=='invitation'?'invitation':'user';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('admin.added.$kind.${r!['status']=='already'?'already':'new'}',{'email':email}))));
  }

  Future<void> _import() async {
    final csv=await showTextFieldsDialog<String>(context,initial:const [''],builder:(c,f,set)=>AlertDialog(
      title:Text(S.t('admin.import')),
      content:SizedBox(width:480,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        AdminHint(S.t('admin.importHelp')),
        const SizedBox(height:8),
        TextField(key:const ValueKey('admin-import-text'),controller:f[0],maxLines:8,minLines:4,keyboardType:TextInputType.multiline,
          decoration:InputDecoration(hintText:'paul@adrasec78.fr\nmarie@adrasec78.fr')),
        const SizedBox(height:8),
        Align(alignment:Alignment.centerLeft,child:OutlinedButton.icon(icon:const Icon(Icons.upload_file),label:Text(S.t('admin.importFile')),
          onPressed:() async {
            final picked=await FilePicker.platform.pickFiles(withData:true,type:FileType.custom,allowedExtensions:const ['csv','txt']);
            final bytes=picked?.files.firstOrNull?.bytes;
            if(bytes!=null)set(()=>f[0].text=decodeCsv(bytes));
          })),
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(key:const ValueKey('admin-import-send'),onPressed:()=>Navigator.pop(c,f[0].text),child:Text(S.t('admin.importSend'))),
      ]));
    if(csv==null||csv.trim().isEmpty||!mounted)return;
    Map<String,dynamic>? r;
    await _do(() async=>r=await widget.api.importMembers(widget.groupId,csv));
    if(r==null||!mounted)return;
    final invalid=[for(final l in (r!['invalid'] as List?)??const [])'$l'];
    await showDialog<void>(context:context,builder:(c)=>AlertDialog(title:Text(S.t('admin.importDone')),
      content:Text([S.t('admin.importResult',{'a':r!['added']??0,'i':r!['invited']??0,'d':r!['already']??0}),
        if(invalid.isNotEmpty)S.t('admin.importInvalid',{'lines':invalid.take(20).join(', ')})].join('\n\n')),
      actions:[FilledButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.ok')))]));
  }

  Future<void> _addGroup() async {
    final present={for(final m in (_g?['groups'] as List?)??const [])if(m is Map)'${m['id']}'};
    final choices=[for(final g in widget.groups)if(g['id']!=widget.groupId&&g['id']!='public'&&!present.contains(g['id']))g];
    final id=await showDialog<String>(context:context,builder:(c)=>SimpleDialog(title:Text(S.t('admin.addGroup',{'name':_name})),children:[
      Padding(padding:const EdgeInsets.symmetric(horizontal:24),child:AdminHint(S.t('admin.addGroupHelp'))),
      for(final g in choices)SimpleDialogOption(onPressed:()=>Navigator.pop(c,'${g['id']}'),child:Row(children:[
        CircleAvatar(radius:6,backgroundColor:groupColor(g['color'])),const SizedBox(width:10),
        Expanded(child:Text('${g['short_name']}',overflow:TextOverflow.ellipsis))])),
    ]));
    if(id==null||!mounted)return;
    await _do(()=>widget.api.addMemberGroup(widget.groupId,id),done:S.t('admin.saved'));
  }

  Future<void> _remove(String what,Future<Object?> Function() call) async {
    if(!await confirmAdmin(context,S.t('admin.removeAsk',{'what':what,'name':_name}),action:S.t('admin.remove'))||!mounted)return;
    await _do(call,done:S.t('admin.removed'));
  }

  // --- Habilitations --------------------------------------------------------------------
  Future<void> _grant() async {
    final rights=widget.catalogue.rights.where((r)=>r['right']!='server_admin'||_serverAdmin).toList();
    if(rights.isEmpty)return;
    var right='${rights.first['right']}';
    String? scope=widget.groupId; DateTime? until;
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set){
      final kind=widget.catalogue.scope(right);
      return AlertDialog(title:Text(S.t('admin.grant',{'name':_name})),
        content:SizedBox(width:440,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          DropdownButtonFormField<String>(key:const ValueKey('admin-grant-right'),initialValue:right,isExpanded:true,
            decoration:InputDecoration(labelText:S.t('admin.right')),
            items:[for(final r in rights)DropdownMenuItem(value:'${r['right']}',child:Text('${r['label']??r['right']}',overflow:TextOverflow.ellipsis))],
            onChanged:(v)=>set((){right=v??right;scope=widget.groupId;})),
          if(kind=='group'||kind=='either')...[
            const SizedBox(height:12),
            DropdownButtonFormField<String>(key:const ValueKey('admin-grant-scope'),initialValue:scope??'',isExpanded:true,
              decoration:InputDecoration(labelText:S.t('admin.scope')),
              items:[
                if(kind=='either')DropdownMenuItem(value:'',child:Text(S.t('admin.scopeServer'))),
                for(final g in widget.groups)if(g['id']!='public')DropdownMenuItem(value:'${g['id']}',child:Text('${g['short_name']}',overflow:TextOverflow.ellipsis)),
              ],
              onChanged:(v)=>set(()=>scope=v==null||v.isEmpty?null:v)),
          ],
          const SizedBox(height:12),
          Row(children:[
            Expanded(child:Text(until==null?S.t('admin.noEnd'):S.t('admin.until',{'date':adminDate(until)}))),
            TextButton(onPressed:() async {final d=await pickEndDate(c,initial:until);if(d!=null)set(()=>until=d);},child:Text(S.t('admin.setEnd'))),
            if(until!=null)IconButton(tooltip:S.t('admin.noEnd'),onPressed:()=>set(()=>until=null),icon:const Icon(Icons.close)),
          ]),
        ])),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
          FilledButton(key:const ValueKey('admin-grant-ok'),onPressed:()=>Navigator.pop(c,true),child:Text(S.t('admin.grantAction'))),
        ]);
    }));
    if(ok!=true||!mounted)return;
    final kind=widget.catalogue.scope(right);
    await _do(()=>widget.api.grant(widget.groupId,right:right,scopeGroupId:kind=='group'||kind=='either'?scope:null,until:until),
      done:S.t('admin.granted'));
  }

  Future<void> _changeUntil(Map<String,dynamic> h) async {
    final current=DateTime.tryParse('${h['until']??''}');
    final choice=await showDialog<String>(context:context,builder:(c)=>SimpleDialog(title:Text(S.t('admin.endOf',{'right':h['label']??h['right']})),children:[
      SimpleDialogOption(onPressed:()=>Navigator.pop(c,'date'),child:Text(S.t('admin.setEnd'))),
      if(current!=null)SimpleDialogOption(onPressed:()=>Navigator.pop(c,'none'),child:Text(S.t('admin.noEnd'))),
    ]));
    if(choice==null||!mounted)return;
    final until=choice=='none'?null:await pickEndDate(context,initial:current);
    if(choice=='date'&&until==null)return;
    await _do(()=>widget.api.setUntil('${h['id']}',until),done:S.t('admin.saved'));
  }

  // --- Licence of the organisation ------------------------------------------------------
  Future<void> _uploadLicence() async {
    final picked=await FilePicker.platform.pickFiles(withData:true,type:FileType.custom,allowedExtensions:const ['json']);
    final bytes=picked?.files.firstOrNull?.bytes;
    if(bytes==null||!mounted)return;
    await _do(()=>widget.api.putLicence(widget.groupId,bytes),done:S.t('admin.licenceLoaded'));
  }

  // --- Page -----------------------------------------------------------------------------
  Widget _memberTile(Widget leading,String title,String? subtitle,{required String what,required Future<Object?> Function() remove,Widget? extra,Key? key})=>
    ListTile(key:key,dense:true,contentPadding:EdgeInsets.zero,leading:leading,title:Text(title,overflow:TextOverflow.ellipsis),
      subtitle:subtitle==null?null:Text(subtitle),
      trailing:Row(mainAxisSize:MainAxisSize.min,children:[
        ?extra,
        if(_members)IconButton(tooltip:S.t('admin.remove'),onPressed:()=>_remove(what,remove),icon:const Icon(Icons.person_remove_outlined)),
      ]));

  @override
  Widget build(BuildContext context){
    final g=_g;
    if(g==null)return Center(child:_error!=null?Padding(padding:const EdgeInsets.all(20),child:Text(_error!)):const CircularProgressIndicator());
    final t=Theme.of(context);
    final users=[for(final u in (g['users'] as List?)??const [])if(u is Map)Map<String,dynamic>.from(u)];
    final invitations=[for(final u in (g['invitations'] as List?)??const [])if(u is Map)Map<String,dynamic>.from(u)];
    final memberGroups=[for(final u in (g['groups'] as List?)??const [])if(u is Map)Map<String,dynamic>.from(u)];
    final habilitations=[for(final h in (g['habilitations'] as List?)??const [])if(h is Map)Map<String,dynamic>.from(h)];
    final children=[for(final c in widget.groups)if(c['parent_id']==widget.groupId)c];
    final ancestors=[for(final a in (g['ancestors'] as List?)??const [])if(a is Map)'${a['short_name']}'];
    final lic=_licence?['licence'] is Map?Map<String,dynamic>.from(_licence!['licence'] as Map):null;
    return ListView(key:ValueKey('admin-panel-${widget.groupId}'),padding:const EdgeInsets.fromLTRB(20,12,20,32),children:[
      Row(children:[
        CircleAvatar(radius:10,backgroundColor:groupColor(g['color'])),
        const SizedBox(width:10),
        Expanded(child:Text('${g['short_name']}',style:t.textTheme.headlineSmall)),
        if(_admin&&g['system']!=true)PopupMenuButton<String>(key:const ValueKey('admin-group-menu'),onSelected:(v){switch(v){
            case 'edit':unawaited(_edit());case 'move':unawaited(_move());case 'delete':unawaited(_delete());}},
          itemBuilder:(_)=>[
            PopupMenuItem(value:'edit',child:Text(S.t('admin.editGroup'))),
            PopupMenuItem(value:'move',child:Text(S.t('admin.move',{'name':_name}))),
            PopupMenuItem(value:'delete',child:Text(S.t('common.delete'))),
          ]),
      ]),
      if('${g['name']??''}'.isNotEmpty&&g['name']!=g['short_name'])Text('${g['name']}',style:t.textTheme.titleSmall),
      if('${g['description']??''}'.isNotEmpty)Padding(padding:const EdgeInsets.only(top:4),child:Text('${g['description']}')),
      Padding(padding:const EdgeInsets.only(top:4),child:AdminHint([
        g['organization']==true?S.t('admin.organization'):ancestors.isEmpty?S.t('admin.noParent'):S.t('admin.attachedTo',{'path':ancestors.join(' › ')}),
        if(g['system']==true)S.t('admin.system'),
      ].join(' · '))),

      // Members
      AdminHeading(S.t('admin.members'),actions:[
        if(_members&&!_public)PopupMenuButton<String>(key:const ValueKey('admin-members-add'),tooltip:S.t('admin.add'),icon:const Icon(Icons.person_add_alt),
          onSelected:(v){switch(v){case 'email':unawaited(_addEmail());case 'csv':unawaited(_import());case 'group':unawaited(_addGroup());}},
          itemBuilder:(_)=>[
            PopupMenuItem(value:'email',child:Text(S.t('admin.addEmail'))),
            PopupMenuItem(value:'csv',child:Text(S.t('admin.import'))),
            if(_admin)PopupMenuItem(value:'group',child:Text(S.t('admin.addGroup',{'name':_name}))),
          ]),
      ]),
      if(_public)AdminHint(S.t('admin.publicMembers'))
      else if(users.isEmpty&&invitations.isEmpty&&memberGroups.isEmpty)AdminHint(S.t('admin.noMembers')),
      for(final u in users)_memberTile(const Icon(Icons.person_outline),'${u['email']}',
        [if('${u['display_name']??''}'.isNotEmpty)'${u['display_name']}',if(u['status']=='disabled')S.t('admin.disabled'),
          if(adminDate(u['added_at']).isNotEmpty)S.t('admin.addedOn',{'date':adminDate(u['added_at'])})].join(' · '),
        key:ValueKey('admin-user-${u['email']}'),what:'${u['email']}',remove:()=>widget.api.removeUser(widget.groupId,'${u['user_id']}'),
        extra:IconButton(tooltip:S.t('admin.why'),icon:const Icon(Icons.help_outline),
          onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>AdminWhyPage(api:widget.api,email:'${u['email']}'))))),
      for(final i in invitations)_memberTile(const Icon(Icons.mail_outline),'${i['email']}',S.t('admin.invitedOn',{'date':adminDate(i['invited_at'])}),
        key:ValueKey('admin-invitation-${i['email']}'),what:'${i['email']}',remove:()=>widget.api.removeInvitation(widget.groupId,'${i['email']}')),
      for(final m in memberGroups)_memberTile(const Icon(Icons.groups_outlined),'${m['short_name']}',S.t('admin.memberGroup'),
        what:'${m['short_name']}',remove:()=>widget.api.removeMemberGroup(widget.groupId,'${m['id']}')),

      // Sub-groups (attached)
      if(!_public)AdminHeading(S.t('admin.subgroups'),actions:[
        if(_admin)IconButton(key:const ValueKey('admin-subgroup-new'),tooltip:S.t('admin.newSubgroup'),onPressed:_newSubgroup,icon:const Icon(Icons.add)),
      ]),
      if(!_public&&children.isEmpty)AdminHint(S.t('admin.noSubgroups')),
      for(final c in children)ListTile(dense:true,contentPadding:EdgeInsets.zero,leading:CircleAvatar(radius:7,backgroundColor:groupColor(c['color'])),
        title:Text('${c['short_name']}'),trailing:const Icon(Icons.chevron_right),onTap:()=>widget.onOpen('${c['id']}')),

      // Habilitations
      AdminHeading(S.t('admin.habilitations'),actions:[
        if(_admin&&!_public)IconButton(key:const ValueKey('admin-grant'),tooltip:S.t('admin.grantAction'),onPressed:_grant,icon:const Icon(Icons.add_moderator_outlined)),
      ]),
      if(_public)AdminHint(S.t('admin.publicRights'))
      else if(habilitations.isEmpty)AdminHint(S.t('admin.noHabilitations')),
      for(final h in habilitations)ListTile(key:ValueKey('admin-hab-${h['id']}'),dense:true,contentPadding:EdgeInsets.zero,
        leading:Icon(h['expired']==true?Icons.timer_off_outlined:Icons.verified_user_outlined,color:h['expired']==true?t.colorScheme.error:null),
        title:Text('${h['label']??widget.catalogue.label('${h['right']}')}'),
        subtitle:Text([
          if('${h['scope_name']??''}'.isNotEmpty)S.t('admin.on',{'name':h['scope_name']}),
          if(h['expired']==true)S.t('admin.expired',{'date':adminDate(h['until'])})
          else if(h['until']!=null)S.t('admin.until',{'date':adminDate(h['until'])}),
          if('${h['granted_by']??''}'.isNotEmpty)S.t('admin.grantedBy',{'who':h['granted_by'],'date':adminDate(h['granted_at'])}),
        ].join(' · ')),
        trailing:_admin?Row(mainAxisSize:MainAxisSize.min,children:[
          IconButton(tooltip:S.t('admin.setEnd'),onPressed:()=>_changeUntil(h),icon:const Icon(Icons.event_outlined)),
          IconButton(tooltip:S.t('admin.revoke'),onPressed:()=>_remove('${h['label']??h['right']}',()=>widget.api.revokeHabilitation('${h['id']}')),
            icon:const Icon(Icons.remove_moderator_outlined)),
        ]):null),

      // Licence of the organisation
      if(g['organization']==true)...[
        AdminHeading(S.t('admin.licence'),actions:[
          if(_serverAdmin)IconButton(tooltip:S.t('admin.licenceLoad'),onPressed:_uploadLicence,icon:const Icon(Icons.upload_file)),
          if(_serverAdmin&&lic!=null)IconButton(tooltip:S.t('admin.licenceRemove'),
            onPressed:()=>_remove(S.t('admin.licence'),()=>widget.api.deleteLicence(widget.groupId)),icon:const Icon(Icons.delete_outline)),
        ]),
        if(lic==null)AdminHint(S.t('admin.noLicence'))
        else AdminHint([
          S.t('admin.licenceStatus',{'s':S.t('admin.licence.${lic['status']}')}),
          if('${lic['kind']??''}'.isNotEmpty)'${lic['kind']}',
          S.t('admin.licenceModules',{'m':[for(final m in (_licence?['modules'] as List?)??const [])'$m'].join(', ')}),
          if(lic['expires_at']!=null)S.t('admin.until',{'date':adminDate(lic['expires_at'])}),
        ].join(' · '),color:const {'valid','expiring','grace'}.contains(lic['status'])?null:t.colorScheme.error),
      ],
    ]);
  }
}

/// Text of a CSV file: UTF-8, else Latin-1 (Excel on Windows).
String decodeCsv(List<int> bytes){
  try{return const Utf8Decoder().convert(bytes);}catch(_){return String.fromCharCodes(bytes);}
}
