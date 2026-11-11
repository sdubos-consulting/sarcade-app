import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../access/access_manager.dart' show AccessHttpClient;
import '../../account/api_error.dart';
import '../../account/rights.dart' show RightsState;
import '../../l10n/strings.dart';
import '../../ui/text_fields_dialog.dart';

/// Events of a group of organisation (lot 26, docs/directory-v0.1.md of the
/// server, « Événements »): organiser group, invited groups, communication
/// group made from a group of organisation.
class EventAccessApi {
  final String baseUrl; final http.Client _client; final bool _own;
  EventAccessApi(String server,{http.Client? client}):baseUrl=_trim(server),_client=client??AccessHttpClient(),_own=client==null;
  static String _trim(String s){var t=s.trim();while(t.endsWith('/')){t=t.substring(0,t.length-1);}return t;}
  void close(){if(_own)_client.close();}
  Uri _u(String path)=>Uri.parse('$baseUrl/api/v0.1$path');
  static const _json={'content-type':'application/json'};

  Future<Object?> _expect(String op,Future<http.Response> call,Set<int> ok) async {
    final r=await call;
    final text=bodyText(r.bodyBytes);
    if(!ok.contains(r.statusCode))throw ApiError.from(op,r.statusCode,text);
    return text.trim().isEmpty?null:jsonDecode(text);
  }
  static Map<String,dynamic> _map(Object? j)=>j is Map?Map<String,dynamic>.from(j):<String,dynamic>{};

  /// Light list for organisers and administrators: `[{id, short_name, name,
  /// parent_id, system, organization_id, color, can_organize}]`.
  Future<List<Map<String,dynamic>>> directoryGroups() async=>[
    for(final g in (await _expect('directory_groups',_client.get(_u('/directory/groups')),{200}) as List?)??const [])
      if(g is Map)Map<String,dynamic>.from(g)];
  /// `{event_id, organizer_group, invited_groups, organization_id, can_organize}`.
  Future<Map<String,dynamic>> access(String eventId) async=>
    _map(await _expect('event_access',_client.get(_u('/events/${Uri.encodeComponent(eventId)}/access')),{200}));
  Future<Map<String,dynamic>> setAccess(String eventId,{String? organizerGroupId,List<String>? invitedGroupIds}) async=>
    _map(await _expect('event_access_put',_client.put(_u('/events/${Uri.encodeComponent(eventId)}/access'),headers:_json,
      body:jsonEncode({'organizer_group_id':?organizerGroupId,'invited_group_ids':?invitedGroupIds})),{200}));
  /// Communication group with the enrolled devices of the members of the
  /// moment; both groups stay independent afterwards.
  Future<Map<String,dynamic>> commGroupFromDirectory(String eventId,String groupId,{String? name,String mode='discussion'}) async=>
    _map(await _expect('comm_from_directory',_client.post(_u('/events/${Uri.encodeComponent(eventId)}/groups/from-directory'),headers:_json,
      body:jsonEncode({'group_id':groupId,if(name!=null&&name.trim().isNotEmpty)'name':name.trim(),'mode':mode})),{200,201}));
}

/// Sentence of a refusal about the access of an event.
String accessErrorText(Object e){
  if(e is! ApiError)return S.t('access.error.offline');
  const known={'event_organizer_required','invalid_organizer_group','group_not_found','event_closed','invalid_group','invalid_mode',
    'account_required','pco_required','event_not_found'};
  if(known.contains(e.code))return S.t('access.error.${e.code}');
  return S.t('access.error.other',{'e':'HTTP ${e.status}${e.code.isEmpty?'':' · ${e.code}'}'});
}

/// Groups an event may invite: every group but the organiser and the
/// administrators of the server; Public first (« ouvert à tous »).
List<Map<String,dynamic>> invitableGroups(List<Map<String,dynamic>> groups,String? organizer){
  final out=[for(final g in groups)if(g['id']!=organizer&&g['id']!='server-admins')g];
  out.sort((a,b){
    final pa=a['id']=='public'?0:1, pb=b['id']=='public'?0:1;
    return pa!=pb?pa.compareTo(pb):'${a['short_name']}'.toLowerCase().compareTo('${b['short_name']}'.toLowerCase());
  });
  return out;
}

/// Organiser group proposed at the creation: the only one, else ADRASEC 78
/// (default group of the server), else the first.
String? defaultOrganizer(List<Map<String,dynamic>> organizable){
  if(organizable.isEmpty)return null;
  if(organizable.length==1)return '${organizable.single['id']}';
  return organizable.any((g)=>g['id']=='adrasec-78')?'adrasec-78':'${organizable.first['id']}';
}

String groupLabel(Map<String,dynamic> g)=>g['id']=='public'?S.t('access.public'):'${g['short_name']??g['id']}';

/// The window « Nouvel événement » offers the groups to an organiser of
/// events of a server of lot 26 (`/me`); otherwise the server chooses.
bool offersEventGroups(String server)=>RightsState.instance.of(server)?.organizes==true;

/// Choice made in the window « Nouvel événement ».
class EventGroupsSelection {
  String? organizer; List<String> invited=[];
  /// The choice was offered (server of lot 26, organiser of a group).
  bool offered=false;
}

/// « Groupe organisateur » and « Groupes invités » in the window that
/// creates an event; nothing when the server has no directory or the
/// person organises no group (the server chooses then).
class EventGroupsChoice extends StatefulWidget {
  final String server; final EventGroupsSelection selection; final EventAccessApi? api;
  const EventGroupsChoice({super.key,required this.server,required this.selection,this.api});
  @override State<EventGroupsChoice> createState()=>_EventGroupsChoiceState();
}

class _EventGroupsChoiceState extends State<EventGroupsChoice> {
  late final EventAccessApi _api=widget.api??EventAccessApi(widget.server);
  List<Map<String,dynamic>>? _groups;

  @override void initState(){super.initState();unawaited(_load());}
  @override void dispose(){if(widget.api==null)_api.close();super.dispose();}

  Future<void> _load() async {
    try{
      final list=await _api.directoryGroups();
      if(!mounted)return;
      final mine=[for(final g in list)if(g['can_organize']==true)g];
      if(mine.isEmpty)return;
      final s=widget.selection;
      s.offered=true; s.organizer??=defaultOrganizer(mine);
      setState(()=>_groups=list);
    }catch(_){/* older server or no right: the server chooses */}
  }

  @override
  Widget build(BuildContext context){
    final groups=_groups;
    if(groups==null)return const SizedBox.shrink();
    final s=widget.selection;
    final mine=[for(final g in groups)if(g['can_organize']==true)g];
    return Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const SizedBox(height:12),
      DropdownButtonFormField<String>(key:const ValueKey('event-new-organizer'),initialValue:s.organizer,isExpanded:true,
        decoration:InputDecoration(labelText:S.t('access.organizer')),
        items:[for(final g in mine)DropdownMenuItem(value:'${g['id']}',child:Text(groupLabel(g),overflow:TextOverflow.ellipsis))],
        onChanged:(v)=>setState((){s.organizer=v;s.invited.remove(v);})),
      const SizedBox(height:12),
      Text(S.t('access.invited'),style:Theme.of(context).textTheme.labelLarge),
      const SizedBox(height:4),
      Wrap(spacing:6,runSpacing:6,children:[
        for(final g in invitableGroups(groups,s.organizer))FilterChip(key:ValueKey('event-new-invite-${g['id']}'),label:Text(groupLabel(g)),
          selected:s.invited.contains(g['id']),
          onSelected:(on)=>setState((){if(on){s.invited.add('${g['id']}');}else{s.invited.remove(g['id']);}})),
      ]),
      Padding(padding:const EdgeInsets.only(top:4),child:Text(S.t('access.invitedHelp'),style:Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}

/// Paramètres › Événement › Accès: organiser group and invited groups,
/// changed by whoever organises the event; « Créer un groupe de
/// communication depuis un groupe d'organisation ».
class EventAccessSection extends StatefulWidget {
  final String server, eventId;
  final Widget Function(String label,{String? help,required Widget child}) row;
  final EventAccessApi? api;
  const EventAccessSection({super.key,required this.server,required this.eventId,required this.row,this.api});
  @override State<EventAccessSection> createState()=>_EventAccessSectionState();
}

class _EventAccessSectionState extends State<EventAccessSection> {
  late final EventAccessApi _api=widget.api??EventAccessApi(widget.server);
  Map<String,dynamic>? _access; List<Map<String,dynamic>> _groups=const [];
  bool _busy=false;

  @override void initState(){super.initState();unawaited(_load());}
  @override void dispose(){if(widget.api==null)_api.close();super.dispose();}

  bool get _can=>_access?['can_organize']==true;

  Future<void> _load() async {
    try{
      final a=await _api.access(widget.eventId);
      if(mounted)setState(()=>_access=a);
      if(a['can_organize']==true){
        final g=await _api.directoryGroups();
        if(mounted)setState(()=>_groups=g);
      }
    }catch(_){/* older server: no section */}
  }

  Future<void> _save({String? organizer,List<String>? invited}) async {
    setState(()=>_busy=true);
    try{
      final a=await _api.setAccess(widget.eventId,organizerGroupId:organizer,invitedGroupIds:invited);
      if(!mounted)return;
      setState(()=>_access=a);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('access.saved'))));
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(accessErrorText(e))));
    }finally{
      if(mounted)setState(()=>_busy=false);
    }
  }

  String? get _organizerId=>(_access?['organizer_group'] as Map?)?['id'] as String?;
  List<String> get _invitedIds=>[for(final g in (_access?['invited_groups'] as List?)??const [])if(g is Map)'${g['id']}'];

  Future<void> _chooseOrganizer() async {
    final mine=[for(final g in _groups)if(g['can_organize']==true)g];
    final id=await showDialog<String>(context:context,builder:(c)=>SimpleDialog(title:Text(S.t('access.organizer')),children:[
      for(final g in mine)SimpleDialogOption(onPressed:()=>Navigator.pop(c,'${g['id']}'),child:Text(groupLabel(g))),
    ]));
    if(id!=null&&id!=_organizerId&&mounted)await _save(organizer:id);
  }

  Future<void> _chooseInvited() async {
    final chosen=_invitedIds.toSet();
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(
      title:Text(S.t('access.invited')),
      content:SizedBox(width:460,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(S.t('access.invitedHelp'),style:Theme.of(c).textTheme.bodySmall),
        const SizedBox(height:8),
        Wrap(spacing:6,runSpacing:6,children:[
          for(final g in invitableGroups(_groups,_organizerId))FilterChip(key:ValueKey('access-invite-${g['id']}'),label:Text(groupLabel(g)),
            selected:chosen.contains(g['id']),onSelected:(on)=>set((){if(on){chosen.add('${g['id']}');}else{chosen.remove(g['id']);}})),
        ]),
      ]))),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
        FilledButton(key:const ValueKey('access-invite-save'),onPressed:()=>Navigator.pop(c,true),child:Text(S.t('common.save'))),
      ])));
    if(ok==true&&mounted)await _save(invited:chosen.toList());
  }

  /// « Créer un groupe de communication depuis un groupe d'organisation ».
  Future<void> _fromDirectory() async {
    final choices=[for(final g in _groups)if(g['id']!='public')g];
    if(choices.isEmpty)return;
    var group='${(choices.where((g)=>g['id']==_organizerId).firstOrNull??choices.first)['id']}';
    var mode='discussion';
    final r=await showTextFieldsDialog<String>(context,initial:const [''],builder:(c,f,set)=>AlertDialog(
      title:Text(S.t('access.fromDirectory')),
      content:SizedBox(width:440,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(S.t('access.fromDirectoryHelp'),style:Theme.of(c).textTheme.bodySmall),
        const SizedBox(height:12),
        DropdownButtonFormField<String>(key:const ValueKey('access-comm-group'),initialValue:group,isExpanded:true,
          decoration:InputDecoration(labelText:S.t('access.sourceGroup')),
          items:[for(final g in choices)DropdownMenuItem(value:'${g['id']}',child:Text(groupLabel(g),overflow:TextOverflow.ellipsis))],
          onChanged:(v)=>set(()=>group=v??group)),
        const SizedBox(height:12),
        TextField(key:const ValueKey('access-comm-name'),controller:f[0],decoration:InputDecoration(labelText:S.t('access.commName'),
          hintText:groupLabel(choices.firstWhere((g)=>g['id']==group,orElse:()=>choices.first)))),
        const SizedBox(height:12),
        SegmentedButton<String>(segments:[
          ButtonSegment(value:'discussion',label:Text(S.t('access.mode.discussion'))),
          ButtonSegment(value:'listen_only',label:Text(S.t('access.mode.listen_only'))),
        ],selected:{mode},onSelectionChanged:(v)=>set(()=>mode=v.first)),
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(key:const ValueKey('access-comm-create'),onPressed:()=>Navigator.pop(c,f[0].text.trim()),child:Text(S.t('access.create'))),
      ]));
    if(r==null||!mounted)return;
    final m=ScaffoldMessenger.of(context);
    setState(()=>_busy=true);
    try{
      final g=await _api.commGroupFromDirectory(widget.eventId,group,name:r,mode:mode);
      m.showSnackBar(SnackBar(content:Text(S.t('access.commCreated',{'name':g['name']??'','n':(g['devices'] as List?)?.length??(g['members'] as List?)?.length??0}))));
    }catch(e){
      m.showSnackBar(SnackBar(content:Text(accessErrorText(e))));
    }finally{
      if(mounted)setState(()=>_busy=false);
    }
  }

  @override
  Widget build(BuildContext context){
    final a=_access;
    if(a==null)return const SizedBox.shrink();
    final t=Theme.of(context);
    final organizer=a['organizer_group'] is Map?Map<String,dynamic>.from(a['organizer_group'] as Map):null;
    final invited=[for(final g in (a['invited_groups'] as List?)??const [])if(g is Map)Map<String,dynamic>.from(g)];
    final row=widget.row;
    return AbsorbPointer(absorbing:_busy,child:Column(key:const ValueKey('event-access'),crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.only(top:16,bottom:4),child:Text(S.t('access.section'),
        style:t.textTheme.titleSmall?.copyWith(color:t.colorScheme.primary,fontWeight:FontWeight.w600))),
      row(S.t('access.organizer'),help:organizer==null?S.t('access.none'):'${organizer['short_name']}${'${organizer['name']??''}'.isNotEmpty&&organizer['name']!=organizer['short_name']?' · ${organizer['name']}':''}',
        child:_can?Align(alignment:Alignment.centerRight,child:OutlinedButton(key:const ValueKey('access-organizer'),onPressed:_chooseOrganizer,child:Text(S.t('access.change')))):const SizedBox.shrink()),
      row(S.t('access.invited'),help:invited.isEmpty?S.t('access.noneInvited'):invited.map(groupLabel).join(', '),
        child:_can?Align(alignment:Alignment.centerRight,child:OutlinedButton(key:const ValueKey('access-invited'),onPressed:_chooseInvited,child:Text(S.t('access.change')))):const SizedBox.shrink()),
      if(_can&&_groups.isNotEmpty)row(S.t('access.fromDirectory'),help:S.t('access.fromDirectoryHelp'),
        child:Align(alignment:Alignment.centerRight,child:OutlinedButton(key:const ValueKey('access-comm'),onPressed:_fromDirectory,child:Text(S.t('access.create'))))),
    ]));
  }
}
