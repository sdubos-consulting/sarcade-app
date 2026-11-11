import 'package:flutter/material.dart';
import '../../ui/overlay_page.dart';
import '../../l10n/strings.dart';
import '../../services/sarcade_api.dart';
import '../../modules/adrasec/aprs/aprs_page.dart';
import 'quick_messages_editor.dart';
import 'car_quick_messages_editor.dart';
import '../../services/event_names.dart';
import '../../operations/event_settings.dart' show eventModules, eventModuleIds;
import '../events/event_access.dart' show EventAccessSection;
import '../../ui/setting_line.dart';
import '../../ui/app_sheet.dart';

/// Paramètres › Événement (PCO): settings of the active event kept by the
/// server, applied at once and written in the logbook by the server —
/// « old » stations threshold, predefined messages, APRS followed. The
/// local radio transmission and its callsign moved to the APRS screen
/// (lot 5, decision of 30 Oct 2026, 2 h 47).
class EventSettingsSection extends StatefulWidget {
  final SarcadeApi api; final String eventId, actorId;
  const EventSettingsSection({super.key,required this.api,required this.eventId,required this.actorId});
  @override State<EventSettingsSection> createState()=>_EventSettingsSectionState();
}

class _EventSettingsSectionState extends State<EventSettingsSection> {
  Map<String,dynamic>? _s; String? _error; bool _busy=false;
  /// `vigilance_departments` of the server (departments followed, source).
  Map<String,dynamic>? _followed;
  static const oldChoices=[30,60,120,240,480,1440];

  @override void initState(){super.initState();_load();}

  Future<void> _load() async {
    try{
      final e=await widget.api.event(widget.eventId);
      final s=Map<String,dynamic>.from(e['settings'] as Map? ?? {});
      if(!mounted)return;
      setState((){_s=s;_error=null;});
    }catch(e){
      if(mounted)setState(()=>_error='$e');
    }
    await _loadFollowed();
  }

  /// Departments followed for the vigilance (older server: nothing).
  Future<void> _loadFollowed() async {
    try{
      final w=await widget.api.eventWeather(widget.eventId,compact:true);
      final f=w['vigilance_departments'];
      if(mounted)setState(()=>_followed=f is Map?Map<String,dynamic>.from(f):null);
    }catch(_){/* offline or older server */}
  }

  /// « Département suivi pour la vigilance » (card « Météo : limiter les
  /// appels à Météo-France », choice 10, 10 Nov 2026): set by the PCO, or
  /// « Automatique » (deduced by the server, choices 9 and 11).
  Future<void> _chooseDepartment() async {
    final current='${_s?['department']??''}';
    final picked=await showDialog<String>(context:context,builder:(_)=>_DepartmentDialog(initial:current));
    if(picked==null)return;
    final value=picked.isEmpty?null:picked;
    if(value==(current.isEmpty?null:current))return;
    await _patch({'department':value});
    await _loadFollowed();
  }

  Future<void> _patch(Map<String,dynamic> p) async {
    setState(()=>_busy=true);
    try{
      final e=await widget.api.patchEventSettings(widget.eventId,widget.actorId,p);
      final s=Map<String,dynamic>.from(e['settings'] as Map? ?? {});
      if(mounted)setState(()=>_s=s);
    }on SarcadeHttpException catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t(e.statusCode==403?'event.forbidden':'event.refused',{'error':'${e.statusCode}'}))));
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('event.offline'))));
    }finally{
      if(mounted)setState(()=>_busy=false);
    }
  }

  /// Predefined messages of the event (ATAK 6): an editable list.
  Future<void> _editQuick() async {
    final initial=((_s?['quick_messages'] as List?)??const []).whereType<String>().toList();
    final list=await showOverlayPage<List<String>>(context,(_)=>QuickMessagesEditor(initial:initial));
    if(list!=null)await _patch({'quick_messages':list});
  }

  /// Messages of the car (lot 24): 1 to 4, « Rétablir » = default list.
  Future<void> _editCarQuick() async {
    final r=await showOverlayPage<CarQuickMessagesResult>(context,(_)=>CarQuickMessagesEditor(initial:carQuickMessagesOf(_s)));
    if(r==null)return;
    await _patch({'car_quick_messages':r.reset?null:carQuickMessagesJson(r.messages!)});
  }

  Widget _row(String label,{String? help,required Widget child}){
    final t=Theme.of(context);
    return Column(children:[
      Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Row(children:[
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(label,style:t.textTheme.titleSmall?.copyWith(fontWeight:FontWeight.w600)),
          if(help!=null)Text(help,style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant)),
        ])),
        const SizedBox(width:12),
        // Actions of the same width, right-aligned (card of 30 Oct 2026, 16 h 40).
        SizedBox(width:eventActionWidth,child:Align(alignment:Alignment.centerRight,child:child)),
      ])),
      const Divider(height:1),
    ]);
  }

  /// « Stations anciennes après »: choice in a sheet (card « Paramètres ›
  /// Événement : onglet compact », validated on 5 Nov 2026, choice 2).
  Future<void> _chooseOld(int current) async {
    final picked=await showAppSheet<int>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Padding(padding:const EdgeInsets.fromLTRB(16,0,16,8),child:Text(S.t('event.oldThreshold'),style:Theme.of(c).textTheme.titleMedium)),
      for(final m in oldChoices)ListTile(key:ValueKey('old-$m'),title:Text(_dur(m)),
        trailing:m==current?Icon(Icons.check,color:Theme.of(c).colorScheme.primary):null,onTap:()=>Navigator.pop(c,m)),
    ])));
    if(picked!=null&&picked!=current)await _patch({'position_old_min':picked});
  }

  /// Modules of the event in a sheet (choice 3: one line « Modules · 1 actif »
  /// until the page of the card « Modules : catalogue et instances »).
  Future<void> _chooseModules() async {
    await showAppSheet<void>(context:context,showDragHandle:true,builder:(c)=>StatefulBuilder(builder:(c,set)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Padding(padding:const EdgeInsets.fromLTRB(16,0,16,8),child:Text(S.t('modules.title'),style:Theme.of(c).textTheme.titleMedium)),
      for(final id in eventModuleIds)SwitchListTile(key:ValueKey('module-$id'),
        title:Text(S.t('modules.$id')),subtitle:Text(S.t('modules.${id}Help')),
        value:eventModules(_s!).contains(id),
        onChanged:(on) async {final now=eventModules(_s!).toList();if(on){now.add(id);}else{now.remove(id);}
          await _patch({'modules':[for(final m in eventModuleIds)if(now.contains(m))m]});set((){});}),
    ]))));
  }

  static String _dur(int m)=>m%60==0?'${m~/60} h':'$m min';

  @override
  Widget build(BuildContext context){
    final s=_s;
    if(s==null){
      return Padding(padding:const EdgeInsets.all(16),child:_error==null?const Center(child:CircularProgressIndicator())
        :Column(children:[Text(S.t('event.offline')),OutlinedButton(onPressed:_load,child:Text(S.t('common.retry')))]));
    }
    final t=Theme.of(context);
    final old=(s['position_old_min'] as num?)?.toInt()??120;
    final active=eventModules(s);
    final adrasec=active.contains('adrasec');
    return AbsorbPointer(absorbing:_busy,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      // Header: name of the event, applied at once for all (choice 1).
      Padding(padding:const EdgeInsets.only(top:12,left:4),child:EventNameBuilder(api:widget.api,eventId:widget.eventId,
        builder:(_,name)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(name,style:t.textTheme.titleMedium),
          Text(S.t('event.appliedForAll'),style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant)),
        ]))),
      SettingsSectionTitle(S.t('event.section.display')),
      SettingLine(key:const ValueKey('event-old'),title:S.t('event.oldThreshold'),help:S.t('event.oldThresholdHelp'),
        value:_dur(oldChoices.contains(old)?old:120),onTap:()=>_chooseOld(old)),
      SettingsSectionTitle(S.t('event.section.messages')),
      SettingLine(key:const ValueKey('event-quick'),title:S.t('event.quick'),value:'${(s['quick_messages'] as List?)?.length??0}',onTap:_editQuick),
      SettingLine(key:const ValueKey('car-quick-edit'),title:S.t('eventSettings.quickCar.title'),value:'${carQuickMessagesOf(s).length}',onTap:_editCarQuick),
      // Weather (card « Météo : limiter les appels à Météo-France », choice 10).
      SettingsSectionTitle(S.t('event.section.weather')),
      SettingLine(key:const ValueKey('event-department'),title:S.t('event.department'),help:S.t('event.departmentHelp'),
        value:departmentValue(s,_followed),onTap:_chooseDepartment),
      SettingsSectionTitle(S.t('modules.title')),
      // Modules: one line (choice 3).
      SettingLine(key:const ValueKey('event-modules'),title:S.t('modules.title'),
        value:S.t('event.modulesActive',{'n':active.length}),onTap:_chooseModules),
      // Mission or exercise SATER (lot 24): « Signal entendu ici » in the car; ADRASEC only.
      if(adrasec)SettingLine(key:const ValueKey('event-sater'),title:S.t('eventSettings.quickSater'),help:S.t('eventSettings.quickSaterHelp'),
        trailing:Switch(value:s['sater']==true,onChanged:(on)=>_patch({'sater':on}))),
      if(adrasec)SettingLine(title:S.t('event.aprsFollowed'),help:[S.t('event.aprsFollowedHelp',{'g':(s['aprs_groups'] as List?)?.length??0,'c':(s['aprs_callsigns'] as List?)?.length??0}),
          if(s['aprs_tx_rf']==true)S.t('event.aprsTxOn',{'call':'${s['aprs_tx_callsign']??'—'}'})].join(' · '),
        onTap:()=>showOverlayPage<void>(context,(_)=>AprsPage(api:widget.api,eventId:widget.eventId,actorId:widget.actorId)).then((_)=>_load())),
      // Lot 26: organiser group, invited groups, communication group from a group of organisation.
      SettingsSectionTitle(S.t('event.section.access')),
      EventAccessSection(server:widget.api.baseUrl,eventId:widget.eventId,row:_row),
    ]));
  }
}

/// Dialog of the department: « Automatique » gives '', « Appliquer » a
/// valid department; it owns its text controller (closing animation).
class _DepartmentDialog extends StatefulWidget {
  final String initial;
  const _DepartmentDialog({required this.initial});
  @override State<_DepartmentDialog> createState()=>_DepartmentDialogState();
}

class _DepartmentDialogState extends State<_DepartmentDialog> {
  late final _ctrl=TextEditingController(text:widget.initial);
  String? _error;
  @override void dispose(){_ctrl.dispose();super.dispose();}

  @override Widget build(BuildContext context)=>AlertDialog(
    title:Text(S.t('event.department')),
    content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(S.t('event.departmentHelp'),style:Theme.of(context).textTheme.bodySmall),
      const SizedBox(height:8),
      TextField(key:const ValueKey('event-department-field'),controller:_ctrl,autofocus:true,maxLength:3,
        textCapitalization:TextCapitalization.characters,
        decoration:InputDecoration(labelText:S.t('event.departmentField'),errorText:_error)),
    ]),
    actions:[
      TextButton(key:const ValueKey('event-department-auto'),onPressed:()=>Navigator.pop(context,''),child:Text(S.t('event.departmentAuto'))),
      TextButton(onPressed:()=>Navigator.pop(context),child:Text(S.t('common.cancel'))),
      FilledButton(key:const ValueKey('event-department-apply'),onPressed:(){
        final v=cleanDepartment(_ctrl.text);
        if(v==null){setState(()=>_error=S.t('event.departmentInvalid'));return;}
        Navigator.pop(context,v);
      },child:Text(S.t('event.apply'))),
    ]);
}

/// Department of the event as the server checks it (2 or 3 characters:
/// digits, or 2A / 2B), upper case; null when not valid.
String? cleanDepartment(String raw){
  final v=raw.trim().toUpperCase();
  return RegExp(r'^(?:\d{2,3}|2[AB])$').hasMatch(v)?v:null;
}

/// Value of « Département suivi pour la vigilance »: the department set by
/// the PCO, else « Automatique (78, 92) » with the departments the server
/// follows, « Par défaut du serveur (78) », or « Automatique ».
String departmentValue(Map<String,dynamic> settings,Map<String,dynamic>? followed){
  final forced=settings['department'];
  if(forced is String&&forced.isNotEmpty)return forced;
  final deps=[for(final d in (followed?['departments'] as List?)??const [])'$d'];
  if(deps.isEmpty)return S.t('event.departmentAuto');
  return S.t(followed?['source']=='server'?'event.departmentServer':'event.departmentAutoFound',{'d':deps.join(', ')});
}

/// Width of the actions of Paramètres › Événement (« Modifier », « Ouvrir »,
/// the « Ancien » list): the same for all, right-aligned.
const double eventActionWidth=130;
