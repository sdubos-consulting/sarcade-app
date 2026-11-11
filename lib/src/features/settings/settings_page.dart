import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../access/access_login_page.dart';
import '../../access/access_manager.dart';
import '../../access/access_session.dart';
import '../../account/account_section.dart' show AccountBanner, AccountSection, connectionSummary;
import '../../account/rights.dart' show RightsState;
import '../../admin/admin_section.dart' show AdminSection;
import '../../config/app_config.dart';
import '../../config/saved_servers.dart';
import 'about_page.dart';
import 'general_lists.dart';
import 'windows_update.dart' show WindowsUpdates, windowsUpdateAlert;
import 'settings_list.dart';
import 'notifications_panel.dart';
import '../map/drawing/drawing_controller.dart' show defaultDrawColor;
import '../../ui/color_palette.dart';
import '../../l10n/strings.dart';
import '../../offline/outbox_policy.dart' show normalServer;
import '../events/event_choice.dart' show singleOpenEvent, eventName;
import '../events/event_access.dart' show EventGroupsChoice, EventGroupsSelection, offersEventGroups;
import '../../operations/event_settings.dart';
import '../../services/notification_service.dart';
import '../../models/comm_group.dart' show isPco;
import '../../services/sarcade_api.dart' show SarcadeApi, SarcadeHttpException;
import 'diagnostics_panel.dart';
// Paramètres › Aide (card « Paramètres : menu « Aide » », 10 Nov 2026).
import '../help/help_page.dart' show HelpContent;
import 'event_settings_section.dart';
import '../../offline/local_store.dart';
import '../compass/shared_compass.dart';
import '../../services/power_state.dart';
import '../../ui/save_bar.dart';
import '../../ui/setting_line.dart';
import '../../ui/link_status.dart';
import '../../ui/text_fields_dialog.dart';
import '../measure/external_maps.dart' show openInChoices, navAppMineKey;
import '../map/operator_icons.dart';
import '../profile/profile_photo_row.dart';
import '../../ui/app_sheet.dart';

/// Operator settings: server address, event and terminal identifier,
/// language, radio callsign. Lets one APK serve every field operator
/// instead of one build per terminal.
class SettingsPage extends StatefulWidget {
  final AppConfig initial;
  final Future<void> Function(AppConfig) onSave;
  final bool firstRun;
  /// Events of a server (« Choix de l'événement dans une liste »): fetched
  /// list, and the last list known for offline use.
  final Future<List<Map<String,dynamic>>> Function(String server)? loadEvents;
  final List<Map<String,dynamic>> Function(String server)? cachedEvents;
  /// Items still waiting for a server and event, and « Envoyer d'abord »
  /// returning what is left (« Robustesse de la synchronisation »).
  final int Function(String server,String eventId)? waitingFor;
  final Future<int> Function(String server,String eventId)? sendFirst;
  /// Remembered servers (« Mémorisation des serveurs »), read again after
  /// each successful connection, and saved after a rename or a removal.
  final List<SavedServer> Function()? readServers;
  final Future<void> Function(List<SavedServer>)? saveServers;
  /// Active session, for Paramètres › Événement (PCO only).
  final SarcadeApi? api;
  /// Device store: caches what the administrator saves (default frequencies).
  final LocalStore? store;
  const SettingsPage({super.key,required this.initial,required this.onSave,this.firstRun=false,
    this.loadEvents,this.cachedEvents,this.waitingFor,this.sendFirst,this.readServers,this.saveServers,this.api,this.store});
  @override State<SettingsPage> createState()=>_SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _form=GlobalKey<FormState>();
  late final TextEditingController _server=TextEditingController(text:widget.initial.serverUrl);
  late final TextEditingController _event=TextEditingController(text:widget.initial.eventId);
  late final TextEditingController _device=TextEditingController(text:widget.initial.deviceId);
  late final TextEditingController _callsign=TextEditingController(text:widget.initial.callsign);
  late String _language=widget.initial.language;
  late bool _aprsConsent=widget.initial.aprsTxConsent;
  late bool _bypassDnd=widget.initial.immediateBypassDnd;
  late int _drawColor=defaultDrawColor(widget.initial.drawColor);
  bool _saving=false;
  /// Something changed since the screen opened (or since the last save):
  /// « Enregistrer » is greyed until then. Always on at the first setup.
  bool _dirty=false;
  void _touch(){if(!_dirty)setState(()=>_dirty=true);}
  List<Map<String,dynamic>> _events=[];
  bool _loadingEvents=false, _eventsOffline=false, _accessRequired=false;
  String? _eventsError;
  /// Only open event of the server, chosen by itself (lot 19): said under the field.
  ({String id,String name})? _autoEvent;
  late List<SavedServer> _servers=widget.readServers?.call()??const [];

  @override void initState(){
    super.initState();
    // Red dot on Paramètres: the screen opens on the Diagnostic (card
    // « Diagnostic, point d'arrivée unique des problèmes », 30 Oct 2026).
    // « Choisir un événement » of the Diagnostic opens Général (lot 19).
    final asked=settingsRequestedTab; settingsRequestedTab=null;
    if(asked!=null&&_tabs.contains(asked)){_tab=_tabs.indexOf(asked);_home=false;}
    else if(!widget.firstRun&&unsentAlert()){_tab=_tabs.indexOf('diagnostics');_home=false;}
    _events=widget.cachedEvents?.call(_serverText)??[];
    if(widget.loadEvents!=null)WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_loadEvents();});
    settingsBackToList.addListener(_backToList);
  }

  /// Paramètres touched again in the bottom bar: back to the list, as ←
  /// does (changes kept); nothing on a wide screen, where the list is
  /// always on the left.
  void _backToList(){
    if(!mounted||_home||widget.firstRun||MediaQuery.sizeOf(context).width>=settingsWideWidth)return;
    setState(()=>_home=true);
  }

  @override void dispose(){
    settingsBackToList.removeListener(_backToList);
    _server.dispose();_event.dispose();_device.dispose();_callsign.dispose();
    if(!widget.firstRun)WidgetsBinding.instance.addPostFrameCallback((_)=>settingsUnsaved.value=false);
    super.dispose();
  }

  String get _serverText{var s=_server.text.trim();while(s.endsWith('/')){s=s.substring(0,s.length-1);}return s;}

  Future<void> _loadEvents() async {
    final load=widget.loadEvents;
    if(load==null||_url(_server.text)!=null)return;
    final server=_serverText;
    setState((){_loadingEvents=true;_eventsError=null;});
    try{
      final list=await load(server);
      if(!mounted||server!=_serverText)return;
      setState((){_events=list;_eventsOffline=false;_accessRequired=false;_servers=widget.readServers?.call()??_servers;});
      // First run, server added or changed: its only open event (lot 19).
      final only=widget.firstRun||_event.text.trim().isEmpty||normalServer(server)!=normalServer(widget.initial.serverUrl)?singleOpenEvent(list,_event.text.trim()):null;
      if(only!=null)setState((){_event.text='${only['id']}';_autoEvent=(id:'${only['id']}',name:eventName(only));});
    }on AccessRequiredException{
      // Protected by Cloudflare Access: sign in first, then the list comes.
      if(mounted)setState((){_events=widget.cachedEvents?.call(server)??[];_accessRequired=true;});
    }on SarcadeHttpException catch(e){
      // The list could not be read: the last known one is shown.
      if(mounted)setState((){_events=widget.cachedEvents?.call(server)??[];_eventsError='HTTP ${e.statusCode}';});
    }catch(_){
      if(mounted)setState((){_events=widget.cachedEvents?.call(server)??[];_eventsOffline=true;});
    }finally{
      if(mounted)setState(()=>_loadingEvents=false);
    }
  }

  Future<List<SavedServer>?> _renameServer(SavedServer server) async {
    final label=await showTextFieldsDialog<String>(context,initial:[server.label],builder:(c,f,_)=>AlertDialog(
      title:Text(S.t('servers.rename')),
      content:TextField(controller:f[0],autofocus:true,decoration:InputDecoration(labelText:S.t('servers.label'),helperText:server.url)),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,f[0].text.trim()),child:Text(S.t('common.save'))),
      ]));
    if(label==null||!mounted)return null;
    final list=[for(final s in _servers)serverKey(s.url)==serverKey(server.url)?s.copyWith(label:label.isEmpty?defaultLabel(s.url):label):s];
    setState(()=>_servers=list);
    await widget.saveServers?.call(list);
    return list;
  }

  Future<List<SavedServer>?> _removeServer(SavedServer server) async {
    final waiting=server.lastEvent==null?0:(widget.waitingFor?.call(server.url,server.lastEvent!)??0);
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:Text(S.t('servers.remove')),
      content:Text([S.t('servers.removeBody',{'label':server.label,'url':server.url}),
        if(waiting>0)S.t('servers.removeWaiting',{'n':waiting})].join('\n\n')),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('servers.removeConfirm'))),
      ]));
    if(ok!=true||!mounted)return null;
    final list=_servers.where((s)=>serverKey(s.url)!=serverKey(server.url)).toList();
    setState(()=>_servers=list);
    await widget.saveServers?.call(list);
    // The Cloudflare Access session of that server goes with it.
    await AccessManager.instance.signOut(server.url);
    return list;
  }

  /// A new address typed in a small window (« Ajouter un serveur »).
  Future<String?> _askServerUrl() async {
    final url=await showTextFieldsDialog<String>(context,initial:const ['https://'],builder:(c,f,_)=>AlertDialog(
      title:Text(S.t('servers.add')),
      content:TextField(controller:f[0],autofocus:true,keyboardType:TextInputType.url,autocorrect:false,
        decoration:InputDecoration(labelText:S.t('settings.server'),hintText:defaultServerUrl,helperText:S.t('settings.serverHelp'),helperMaxLines:3)),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,f[0].text.trim()),child:Text(S.t('common.ok'))),
      ]));
    if(url==null||!mounted)return null;
    if(_url(url)!=null){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('settings.urlExpected'))));return null;}
    return url;
  }

  Future<void> _signIn() async {
    if(_url(_server.text)!=null)return;
    if(await signInToServer(context,_serverText)&&mounted){setState(()=>_accessRequired=false);_loadEvents();}
  }

  /// Sign-in state of the server (Cloudflare Access), with its buttons:
  /// first setup only (the list of events needs it).
  Widget _accessRow(){
    if(_url(_server.text)!=null)return const SizedBox.shrink();
    final server=_serverText;
    final session=AccessManager.instance.sessionFor(server);
    if(session==null&&!_accessRequired)return const SizedBox.shrink();
    final now=DateTime.now().toUtc();
    String fmt(DateTime t){final l=t.toLocal();String two(int v)=>v.toString().padLeft(2,'0');return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';}
    final expired=session==null||session.expired(now);
    final text=session==null?S.t('access.required')
      :expired?S.t('access.sessionExpired',{'email':session.email??''})
      :S.t('access.session',{'email':session.email??'',
          'date':session.expiresAt==null?'-':fmt(session.expiresAt!)});
    final color=session==null||expired||session.renewSoon(now)?Colors.deepOrange:null;
    return Padding(padding:const EdgeInsets.only(top:8),child:Wrap(crossAxisAlignment:WrapCrossAlignment.center,spacing:8,children:[
      Icon(expired?Icons.lock_outline:Icons.lock_open,size:18,color:color),
      Text(text,style:TextStyle(color:color)),
      OutlinedButton(onPressed:_signIn,child:Text(S.t(session==null?'access.signIn':'access.signInAgain'))),
      if(session!=null)OutlinedButton(onPressed:() async {await AccessManager.instance.signOut(server);if(mounted)setState((){});},child:Text(S.t('access.signOut'))),
    ]));
  }

  static String _date(Object? v){
    final t=DateTime.tryParse('${v??''}')?.toLocal();
    if(t==null)return '';
    String two(int x)=>x.toString().padLeft(2,'0');
    return '${two(t.day)}/${two(t.month)}';
  }

  String _eventLabel(Map<String,dynamic> e){
    final state=S.t('eventState.${e['status']}');
    return [e['name'],state,_date(e['created_at'])].where((x)=>'${x??''}'.isNotEmpty).join(' · ');
  }

  Widget _eventPicker(){
    final current=_event.text.trim();
    final ids=_events.map((e)=>'${e['id']}').toSet();
    final items=[
      for(final e in _events)DropdownMenuItem(value:'${e['id']}',child:Text(_eventLabel(e),overflow:TextOverflow.ellipsis)),
      if(current.isNotEmpty&&!ids.contains(current))DropdownMenuItem(value:current,child:Text(S.t('settings.eventUnlisted',{'id':current}),overflow:TextOverflow.ellipsis)),
    ];
    final help=_eventsError!=null?S.t('settings.eventsError',{'error':_eventsError})
      :_eventsOffline?S.t('settings.eventsOffline')
      :(_events.isEmpty&&!_loadingEvents)?S.t('settings.eventsEmpty')
      :_autoEvent!=null&&_autoEvent!.id==current?S.t('events.followed',{'name':_autoEvent!.name}):null;
    return _withActions(DropdownButtonFormField<String>(
        key:ValueKey('$current|${_events.length}'),
        initialValue:current.isEmpty?null:current,
        isExpanded:true,
        decoration:_field(label:widget.firstRun?S.t('settings.event'):null,help:help),
        items:items,
        onChanged:(v)=>setState((){_event.text=v??'';_dirty=true;}),
        validator:(_)=>_required(_event.text),
      ),[
      _loadingEvents
        ? const SizedBox(width:48,height:48,child:Padding(padding:EdgeInsets.all(12),child:CircularProgressIndicator(strokeWidth:2)))
        : IconButton(tooltip:S.t('settings.eventsRefresh'),onPressed:_loadEvents,icon:Icon(_eventsOffline?Icons.cloud_off:Icons.refresh)),
      if(_canCreateEvent)IconButton(key:const ValueKey('event-new'),tooltip:S.t('events.new'),onPressed:_createEvent,icon:const Icon(Icons.add)),
    ]);
  }

  /// The PCO creates an event from the app, on the server it is linked to.
  bool get _canCreateEvent=>widget.api!=null&&!widget.firstRun&&isPco(widget.initial.deviceId)
    &&normalServer(_serverText)==normalServer(widget.initial.serverUrl);

  /// The id of the new event (chosen afterwards in the list of Général).
  Future<String?> _createEvent() async {
    var kind='exercise'; final groups=EventGroupsSelection();
    final name=await showTextFieldsDialog<String>(context,initial:const [''],builder:(c,f,set)=>AlertDialog(scrollable:true,title:Text(S.t('events.new')),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        TextField(key:const ValueKey('event-new-name'),controller:f[0],autofocus:true,decoration:InputDecoration(labelText:S.t('events.name'))),
        const SizedBox(height:12),
        DropdownButtonFormField<String>(key:const ValueKey('event-new-kind'),initialValue:kind,isExpanded:true,decoration:InputDecoration(labelText:S.t('events.model')),
          items:[for(final k in eventKinds)DropdownMenuItem(value:k,child:Text(S.t('events.kind.$k')))],onChanged:(v)=>set(()=>kind=v??kind)),
        const SizedBox(height:6),
        Text(S.t('events.modulesOf',{'m':eventKindModules(kind)}),style:Theme.of(c).textTheme.bodySmall),
        // Lot 26: organiser group and invited groups.
        if(offersEventGroups(widget.api!.baseUrl))EventGroupsChoice(server:widget.api!.baseUrl,selection:groups),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(key:const ValueKey('event-new-create'),onPressed:()=>Navigator.pop(c,f[0].text),child:Text(S.t('events.create')))]));
    final n=name?.trim()??'';
    if(n.isEmpty||!mounted)return null;
    final m=ScaffoldMessenger.of(context);
    try{
      final e=await widget.api!.createEvent(n,kind,organizerGroupId:groups.offered?groups.organizer:null,invitedGroupIds:groups.invited);
      if(!mounted)return null;
      await _loadEvents();
      m.showSnackBar(SnackBar(content:Text(S.t('events.created',{'n':n}))));
      return '${e['id']}';
    }on SarcadeHttpException catch(e){
      m.showSnackBar(SnackBar(content:Text(S.t(e.statusCode==403?'events.pcoOnly':'events.createFailed',{'e':'HTTP ${e.statusCode}'}))));
    }catch(_){
      m.showSnackBar(SnackBar(content:Text(S.t('events.createFailed',{'e':S.t('settings.eventsOffline')}))));
    }
    return null;
  }

  /// « ADRASEC », « Course » or « aucun (Core seul) », for the dialog.
  String eventKindModules(String kind){
    final m=modulesOfKind(kind);
    return m.isEmpty?S.t('modules.none'):m.map((id)=>S.t('modules.$id')).join(', ');
  }

  /// ADRASEC on for the event this device follows (Core and modules).
  bool get _adrasec=>eventModules(widget.store?.eventSettings(widget.initial.eventId)).contains('adrasec')&&RightsState.instance.allows('adrasec');

  String? _required(String? v)=>(v==null||v.trim().isEmpty)?S.t('settings.required'):null;

  String? _url(String? v){
    final r=_required(v);
    if(r!=null)return r;
    final u=Uri.tryParse(v!.trim());
    if(u==null||!(u.scheme=='http'||u.scheme=='https')||u.host.isEmpty)return S.t('settings.urlExpected');
    return null;
  }

  String? _callsignCheck(String? v)=>(v==null||v.trim().isEmpty||validCallsign(v))?null:S.t('settings.callsignInvalid');

  /// True once saved (false: a field refused, or the change cancelled).
  Future<bool> _save() async {
    if(!_form.currentState!.validate())return false;
    final server=_serverText, event=_event.text.trim();
    final from=widget.initial;
    final changes=normalServer(server)!=normalServer(from.serverUrl)||event!=from.eventId;
    final waiting=(!widget.firstRun&&changes)?(widget.waitingFor?.call(from.serverUrl,from.eventId)??0):0;
    if(waiting>0){
      // Decision 5: Envoyer d'abord · Garder pour plus tard · Annuler.
      final choice=await showDialog<String>(context:context,builder:(c)=>AlertDialog(
        title:Text(S.t('change.title')),
        content:Text(S.t('change.body',{'n':waiting,'event':from.eventId,'server':from.serverUrl})),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
          TextButton(onPressed:()=>Navigator.pop(c,'keep'),child:Text(S.t('change.keep'))),
          FilledButton(onPressed:()=>Navigator.pop(c,'send'),child:Text(S.t('change.sendFirst'))),
        ]));
      if(choice==null||!mounted)return false;
      setState(()=>_saving=true);
      final left=choice=='send'&&widget.sendFirst!=null?await widget.sendFirst!(from.serverUrl,from.eventId):waiting;
      if(left>0&&mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('change.kept',{'n':left}))));
    }
    if(!mounted)return false;
    setState(()=>_saving=true);
    await widget.onSave(widget.initial.copyWith(serverUrl:server,eventId:event,deviceId:_device.text.trim(),
      language:_language,callsign:_callsign.text.trim().toUpperCase(),aprsTxConsent:_aprsConsent,
      immediateBypassDnd:_bypassDnd,drawColor:_drawColor));
    if(mounted)setState((){_saving=false;_dirty=false;});
    return true;
  }

  /// Tabs of the screen (« Charte graphique épurée »); the first setup only
  /// shows what is needed to start. No « Affichage » any more (card
  /// « Paramètres : supprimer l'onglet Affichage », 1 Nov 2026, 22 h 17):
  /// the theme is in « Fond et affichage » of the map, the power saving in
  /// Général, the language in Profil.
  List<String> get _tabs=>settingsTabs(firstRun:widget.firstRun,event:_eventTab,admin:_adminTab);
  /// Paramètres › Administration (lot 26): administrators only (`/me`).
  bool get _adminTab=>widget.api!=null&&RightsState.instance.of(widget.initial.serverUrl)?.canAdminister==true;
  bool get _eventTab=>widget.api!=null&&isPco(widget.initial.deviceId);
  int _tab=0;
  /// Phone: the list of Paramètres is shown (no page open).
  bool _home=true;
  /// Opens a page of Paramètres (list on a phone, right side on a computer).
  void _openTab(String id)=>setState((){_tab=_tabs.indexOf(id).clamp(0,_tabs.length-1);_home=false;});

  /// One setting per line: see [settingsRowLayout].
  Widget _row(String label,{String? help,String? tip,required Widget child})=>settingsRowLayout(context,label,help:help,tip:tip,child:child);

  /// Compact field; its label stays inside (read by screen readers and the
  /// end-to-end tests). Shape and background from the theme (card « Saisie…
  /// sans contour », 10 Nov 2026).
  InputDecoration _field({String? label,String? hint,String? help})=>InputDecoration(isDense:true,labelText:label,hintText:hint,helperText:help,helperMaxLines:3);


  /// Compact field on the right of a row (label inside, read by screen
  /// readers and the end-to-end tests).
  Widget _compact(Widget field)=>Align(alignment:Alignment.centerLeft,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),child:field));

  /// First setup: the plain form of before (fields one under the other),
  /// kept as it is for the end-to-end tests of the first run.
  Widget _firstRunTab()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Padding(padding:const EdgeInsets.only(top:12),child:Text(S.t('settings.intro'))),
    Padding(padding:const EdgeInsets.only(top:14),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Focus(
        // Leaving the server field reloads the events of that server.
        onFocusChange:(f){if(!f)_loadEvents();},
        child:TextFormField(
          controller:_server,
          decoration:_field(label:S.t('settings.server'),hint:defaultServerUrl,help:S.t('settings.serverHelp')),
          keyboardType:TextInputType.url,autocorrect:false,validator:_url,
          onFieldSubmitted:(_)=>_loadEvents(),
          onChanged:(_)=>setState((){}),
        ),
      ),
      _accessRow(),
    ])),
    Padding(padding:const EdgeInsets.only(top:14),child:widget.loadEvents!=null?_eventPicker():TextFormField(
      controller:_event,decoration:_field(label:S.t('settings.event')),autocorrect:false,validator:_required)),
    Padding(padding:const EdgeInsets.only(top:14),child:TextFormField(
      controller:_device,decoration:_field(label:S.t('settings.device'),hint:'TERRAIN-01',help:S.t('settings.deviceHelp')),autocorrect:false,validator:_required)),
    const SizedBox(height:8),
  ]);

  /// Paramètres › Général (card « Paramètres › Général : onglet compact »,
  /// 5 Nov 2026, choices 1 to 7): sections Connexion, Cet appareil,
  /// Batterie; one line per setting, its value on the right and « › »; a
  /// help line in small under each title (no more ⓘ); each setting applied
  /// at once, no « Annuler » / « Enregistrer » (a new server or event is
  /// confirmed first). The first setup keeps its plain form.
  Widget _generalTab()=>widget.firstRun?_firstRunTab():Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    SettingsSectionTitle(S.t('general.section.connection')),
    // « Serveur · app.sarcade.org › », « Connecté : … › Profil » under it.
    ListenableBuilder(listenable:Listenable.merge([AccountManager.instance,AccessManager.instance]),builder:(context,_){
      final server=_serverText;
      final connected=_url(_server.text)!=null?null:connectionSummary(account:AccountManager.instance.sessionFor(server),
        access:AccessManager.instance.sessionFor(server),accessRequired:_accessRequired||AccessManager.instance.requiredFor(server));
      return SettingLine(key:const ValueKey('general-server'),title:S.t('settings.server'),value:_serverValue,
        help:connected,helpKey:const ValueKey('general-connection'),onHelpTap:()=>_openTab('profile'),
        onTap:_openServers);
    }),
    // « Événement suivi · Test NAS 1 [Brouillon] › ».
    SettingLine(key:const ValueKey('general-event'),title:S.t('settings.eventRow'),help:S.t('general.eventHelp'),
      valueWidget:_eventValue(),onTap:_openEvents),
    SettingsSectionTitle(S.t('general.section.device')),
    // « Terminal » renamed « Nom de l'appareil » (choice 4).
    SettingLine(key:const ValueKey('general-device'),title:S.t('general.deviceName'),help:S.t('general.deviceNameHelp'),
      value:_device.text.trim(),onTap:_editDeviceName),
    // Settings of this device (22 h 18, point 5): « Toujours ouvrir avec … »
    // of « Ouvrir dans… » (31 Oct 2026), applied at once.
    if(widget.store!=null)SettingLine(key:const ValueKey('settings-nav-app'),title:S.t('settings.navApp'),help:S.t('general.navAppHelp'),
      value:_navAppLabel(widget.store!.preference(navAppMineKey)),onTap:_chooseNavApp),
    SettingsSectionTitle(S.t('general.section.battery')),
    // Battery card (30 Oct 2026, point E): applied at once, kept on the
    // device; the switch on the line (choice 6).
    ListenableBuilder(listenable:PowerState.instance,builder:(context,_)=>SettingLine(title:S.t('power.saver'),help:S.t('power.saverHelp'),
      onTap:()=>PowerState.instance.setSaver(!PowerState.instance.saver),
      trailing:Switch(key:const ValueKey('power-saver'),value:PowerState.instance.saver,onChanged:(v){PowerState.instance.setSaver(v);}))),
  ]);

  /// « app.sarcade.org », or « Club · 192.168.0.110:8000 » when the name
  /// does not say the address.
  String get _serverValue{
    final saved=findServer(_servers,_serverText);
    if(saved==null)return defaultLabel(_serverText);
    return saved.label.toLowerCase().contains(saved.shortAddress.toLowerCase())?saved.shortAddress:'${saved.label} · ${saved.shortAddress}';
  }

  /// Name of the followed event and its state in a pill, never cut.
  Widget _eventValue(){
    final id=_event.text.trim();
    final e=_events.where((x)=>'${x['id']}'==id).firstOrNull;
    final t=Theme.of(context);
    final style=t.textTheme.bodyMedium?.copyWith(color:t.colorScheme.onSurfaceVariant);
    if(e==null)return Text(id,textAlign:TextAlign.end,style:style);
    return Wrap(alignment:WrapAlignment.end,crossAxisAlignment:WrapCrossAlignment.center,spacing:6,runSpacing:4,children:[
      Text(eventName(e),textAlign:TextAlign.end,style:style),eventStatePill(e['status'])]);
  }

  String _navAppLabel(String? id)=>id==null||id.isEmpty?S.t('settings.navAppAsk'):S.t('ext.app.$id');

  /// Why the list of events may be old or empty.
  String? get _eventsNote=>_accessRequired?S.t('access.required')
    :_eventsError!=null?S.t('settings.eventsError',{'error':_eventsError})
    :_eventsOffline?S.t('settings.eventsOffline'):null;

  Future<String?> _pickEvent(){
    final current=_event.text.trim();
    return Navigator.of(context).push<String>(MaterialPageRoute(builder:(_)=>EventListPage(
      events:_events,current:current,note:_eventsNote,
      reload:() async {await _loadEvents();return (_events,_eventsNote);},
      create:_canCreateEvent?_createEvent:null)));
  }

  /// Choice 3: the list of events; another one is confirmed, then applied.
  Future<void> _openEvents() async {
    if(widget.loadEvents==null){await _typeEvent();return;}
    final id=await _pickEvent();
    if(id==null||!mounted||id==widget.initial.eventId)return;
    final e=_events.where((x)=>'${x['id']}'==id).firstOrNull;
    if(!await _confirmSwitch(S.t('general.switchEvent.title'),S.t('general.switchEvent.body',{'name':e==null?id:eventName(e)})))return;
    setState(()=>_event.text=id);
    await _applyOrRevert();
  }

  /// No list of events (tests, builds without a server): the id is typed.
  Future<void> _typeEvent() async {
    final id=await showTextFieldsDialog<String>(context,initial:[_event.text],builder:(c,f,_)=>AlertDialog(
      title:Text(S.t('settings.eventRow')),
      content:TextField(key:const ValueKey('general-event-field'),controller:f[0],autofocus:true,autocorrect:false,decoration:InputDecoration(labelText:S.t('settings.event'))),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,f[0].text.trim()),child:Text(S.t('common.ok')))]));
    if(id==null||id.isEmpty||id==widget.initial.eventId||!mounted)return;
    if(!await _confirmSwitch(S.t('general.switchEvent.title'),S.t('general.switchEvent.body',{'name':id})))return;
    setState(()=>_event.text=id);
    await _applyOrRevert();
  }

  /// Choice 2: the remembered servers (choose, add, rename, forget).
  Future<void> _openServers() async {
    final current=_serverText;
    final v=await Navigator.of(context).push<String>(MaterialPageRoute(builder:(_)=>ServerListPage(
      servers:_servers,current:current,rename:_renameServer,remove:_removeServer,canRemove:canRemoveServer,label:serverChoiceLabel)));
    if(v==null||!mounted)return;
    final url=v==addServerChoice?await _askServerUrl():v;
    if(url==null||!mounted||normalServer(url)==normalServer(widget.initial.serverUrl))return;
    if(!await _confirmSwitch(S.t('general.switchServer.title'),S.t('general.switchServer.body',{'server':defaultLabel(url)})))return;
    final saved=findServer(_servers,url);
    setState((){
      _server.text=url;_event.text=saved?.lastEvent??'';
      if(saved?.lastDevice!=null&&saved!.lastDevice!.isNotEmpty)_device.text=saved.lastDevice!;
      _events=widget.cachedEvents?.call(_serverText)??[];
    });
    await _loadEvents();
    if(!mounted)return;
    // No event known on that server: chosen in its list first.
    if(_event.text.trim().isEmpty){
      final id=await _pickEvent();
      if(id==null||!mounted){_revert();return;}
      setState(()=>_event.text=id);
    }
    await _applyOrRevert();
  }

  /// Choice 4: « Nom de l'appareil », typed in a small window.
  Future<void> _editDeviceName() async {
    final name=await showTextFieldsDialog<String>(context,initial:[_device.text],builder:(c,f,_)=>AlertDialog(
      title:Text(S.t('general.deviceName')),
      content:TextField(key:const ValueKey('general-device-field'),controller:f[0],autofocus:true,autocorrect:false,
        decoration:InputDecoration(labelText:S.t('general.deviceName'),hintText:'TERRAIN-01',helperText:S.t('settings.deviceHelp'),helperMaxLines:2)),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(key:const ValueKey('general-device-ok'),onPressed:()=>Navigator.pop(c,f[0].text.trim()),child:Text(S.t('common.ok')))]));
    if(name==null||name.isEmpty||name==widget.initial.deviceId||!mounted)return;
    setState(()=>_device.text=name);
    await _applyOrRevert();
  }

  /// « Application de navigation »: chosen in a small list, applied at once.
  Future<void> _chooseNavApp() async {
    final store=widget.store!;
    final current=store.preference(navAppMineKey)??'';
    final choices=['',for(final a in openInChoices(android:!kIsWeb&&defaultTargetPlatform==TargetPlatform.android,ios:!kIsWeb&&defaultTargetPlatform==TargetPlatform.iOS))if(a!='other')a];
    final v=await showDialog<String>(context:context,builder:(c)=>SimpleDialog(title:Text(S.t('settings.navApp')),children:[
      for(final a in choices)SimpleDialogOption(key:ValueKey('nav-app-${a.isEmpty?'ask':a}'),onPressed:()=>Navigator.pop(c,a),child:Row(children:[
        SizedBox(width:32,child:a==current?Icon(Icons.check,size:20,color:Theme.of(c).colorScheme.primary):null),
        Expanded(child:Text(_navAppLabel(a))),
      ])),
    ]));
    if(v==null||v==current)return;
    await store.setPreference(navAppMineKey,v.isEmpty?null:v);
    if(mounted)setState((){});
  }

  /// A new server or event is confirmed (choice 7). With items still
  /// waiting, the window « Envoyer d'abord » of the save asks instead.
  Future<bool> _confirmSwitch(String title,String body) async {
    final waiting=widget.waitingFor?.call(widget.initial.serverUrl,widget.initial.eventId)??0;
    if(waiting>0)return true;
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(title),content:Text(body),actions:[
      TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
      FilledButton(key:const ValueKey('general-switch-ok'),onPressed:()=>Navigator.pop(c,true),child:Text(S.t('general.switch'))),
    ]));
    return ok==true&&mounted;
  }

  /// Applied at once; refused or cancelled: back to the settings in use.
  Future<void> _applyOrRevert() async {
    if(_url(_server.text)!=null||_required(_event.text)!=null||_required(_device.text)!=null){_revert();return;}
    if(!await _save()&&mounted)_revert();
  }

  void _revert(){
    final i=widget.initial;
    setState((){
      _server.text=i.serverUrl;_event.text=i.eventId;_device.text=i.deviceId;
      _events=widget.cachedEvents?.call(_serverText)??_events;
    });
  }

  /// Serveur, Événement suivi and Terminal of the same width, their buttons
  /// (pencil, bin, refresh) in one column on the right (16 h 38).
  static const double _actionsWidth=96;
  Widget _withActions(Widget field,[List<Widget> actions=const []])=>Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Expanded(child:field),
    SizedBox(width:_actionsWidth,child:Row(mainAxisAlignment:MainAxisAlignment.end,children:actions)),
  ]);

  /// Card « Paramètres › Profil : onglet compact » (validated on 5 Nov 2026):
  /// sections, one line per setting, choices in a sheet, applied at once
  /// (the call sign when ✓ of the keyboard is touched).
  Future<void> _applyNow() async {if(!widget.firstRun)await _trySave();}

  Future<T?> _sheet<T>(String title,Widget Function(BuildContext c) body)=>showAppSheet<T>(context:context,showDragHandle:true,isScrollControlled:true,
    builder:(c)=>SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(16,0,16,16),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text(title,style:Theme.of(c).textTheme.titleMedium),const SizedBox(height:12),body(c)]))));

  Future<void> _chooseColor() async {
    final picked=await _sheet<Object>(S.t('settings.drawColor'),(c)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      ColorGrid(colors:paletteWith(_drawColor),selected:_drawColor,onPick:(v)=>Navigator.pop(c,v)),
      const SizedBox(height:8),
      ActionChip(avatar:const Icon(Icons.palette_outlined,size:18),label:Text(S.t('settings.otherColor')),onPressed:()=>Navigator.pop(c,'other')),
    ]));
    if(picked=='other'){await _pickOtherColor();return;}
    if(picked is int&&mounted&&picked!=_drawColor){setState((){_drawColor=picked;_dirty=true;});await _applyNow();}
  }

  Future<void> _chooseIcon() async {
    final current=widget.store!.preference(operatorIconKey)??'';
    final picked=await _sheet<String>(S.t('settings.operatorIcon'),(c)=>Wrap(spacing:6,runSpacing:6,children:[
      ChoiceChip(key:const ValueKey('icon-none'),label:Text(S.t('settings.operatorIconNone')),selected:current.isEmpty,onSelected:(_)=>Navigator.pop(c,'')),
      for(final id in operatorIconIds)ChoiceChip(key:ValueKey('icon-$id'),tooltip:S.t('icon.$id'),showCheckmark:false,
        label:Icon(operatorIcon(id),size:20),selected:current==id,onSelected:(_)=>Navigator.pop(c,id)),
    ]));
    if(picked!=null&&picked!=current)await _setOperatorIcon(picked.isEmpty?null:picked);
  }

  String _languageLabel(String v)=>v=='fr'?'Français':v=='en'?'English':S.t('settings.languageSystem');

  Future<void> _chooseLanguage() async {
    final picked=await _sheet<String>(S.t('settings.languageRow'),(c)=>Column(mainAxisSize:MainAxisSize.min,children:[
      for(final v in const ['system','fr','en'])ListTile(key:ValueKey('language-$v'),title:Text(_languageLabel(v)),
        trailing:v==_language?Icon(Icons.check,color:Theme.of(c).colorScheme.primary):null,onTap:()=>Navigator.pop(c,v)),
    ]));
    if(picked!=null&&picked!=_language&&mounted){setState((){_language=picked;_dirty=true;});await _applyNow();}
  }

  Widget _profileTab(){
    final icon=widget.store?.preference(operatorIconKey)??'';
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      // Account of the person (lot 26): « Se connecter », Mes appareils.
      // AccountSection has its own « Connexion » title.
      if(!widget.firstRun)AccountSection(server:widget.initial.serverUrl,deviceId:widget.initial.deviceId,row:_row),
      SettingsSectionTitle(S.t('profile.section.map')),
      // Call sign: saved with ✓ of the keyboard, checked before (choice 7).
      _row(S.t('settings.callsignRow'),help:S.t('settings.callsignHelp'),child:_compact(TextFormField(
        controller:_callsign,decoration:_field(hint:'F4ABC-7'),textInputAction:TextInputAction.done,
        onFieldSubmitted:(_)=>unawaited(_applyNow()),
        autocorrect:false,textCapitalization:TextCapitalization.characters,validator:_callsignCheck))),
      // Colour of every new drawing (existing objects keep theirs).
      SettingLine(key:const ValueKey('profile-color'),title:S.t('settings.drawColor'),help:S.t('settings.drawColorHelp'),
        valueWidget:Container(width:22,height:22,decoration:BoxDecoration(color:Color(_drawColor),shape:BoxShape.circle)),
        onTap:()=>unawaited(_chooseColor())),
      // Icon on the map, as the APRS symbols (1 Nov 2026); applied at once,
      // sent with the next heartbeat, kept in the personal settings.
      if(widget.store!=null)SettingLine(key:const ValueKey('profile-icon'),title:S.t('settings.operatorIcon'),help:S.t('settings.operatorIconHelp'),
        valueWidget:icon.isEmpty?Text(S.t('settings.operatorIconNone')):Icon(operatorIcon(icon),size:22),
        onTap:()=>unawaited(_chooseIcon())),
      // Photo in place of the initials (lot 29, group 7), applied at once.
      if(widget.store!=null&&widget.api!=null&&!widget.firstRun)_row(S.t('profile.photo'),help:S.t('profile.photoHelp'),
        child:ProfilePhotoRow(api:widget.api!,store:widget.store!,eventId:widget.initial.eventId,deviceId:widget.initial.deviceId)),
      SettingsSectionTitle(S.t('profile.section.app')),
      // Language of the person (22 h 17, choice 1), « Langue de l'appareil »
      // by default. Kept on this device: the server has no personal language.
      SettingLine(key:const ValueKey('settings-language'),title:S.t('settings.languageRow'),value:_languageLabel(_language),
        onTap:()=>unawaited(_chooseLanguage())),
      // ADRASEC module only: the switch on its line (choice 5).
      if(_adrasec)SettingLine(title:S.t('settings.aprsConsent'),help:S.t('settings.aprsConsentHelp'),
        trailing:Switch(value:_aprsConsent,onChanged:(v){setState((){_aprsConsent=v;_dirty=true;});unawaited(_applyNow());})),
    ]);
  }

  /// « Autre couleur »: free choice of the hue, light enough to read on
  /// the map.
  Future<void> _pickOtherColor() async {
    var hue=HSVColor.fromColor(Color(_drawColor)).hue;
    final picked=await showDialog<int>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set){
      final color=HSVColor.fromAHSV(1,hue,0.8,0.85).toColor();
      return AlertDialog(title:Text(S.t('settings.otherColor')),content:Column(mainAxisSize:MainAxisSize.min,children:[
        Container(width:56,height:56,decoration:BoxDecoration(color:color,shape:BoxShape.circle)),
        Slider(value:hue,min:0,max:359,onChanged:(v)=>set(()=>hue=v)),
      ]),actions:[
        TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,color.toARGB32()),child:Text(S.t('common.ok'))),
      ]);
    }));
    if(picked!=null&&mounted){setState((){_drawColor=picked;_dirty=true;});await _applyNow();}
  }

  Widget _notificationsTab()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    NotificationsPanel(api:widget.api,eventId:widget.initial.eventId,deviceId:widget.initial.deviceId,store:widget.store,row:_row),
    // Android: « Immédiat en mode Ne pas déranger » on its line (5 Nov 2026).
    if(NotificationService.supportsDndBypass)SettingLine(title:S.t('settings.dndBypass'),help:S.t('settings.dndBypassHelp'),
      trailing:Switch(value:_bypassDnd,onChanged:(v) async {
        setState((){_bypassDnd=v;_dirty=true;});
        if(!v)return;
        final granted=await NotificationService().enableDndBypass();
        if(!granted&&mounted){
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('settings.dndPending'))));
        }
      })),
  ]);

  /// Active session only: what is shown does not depend on unsaved edits.
  Widget _diagnosticsTab()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Padding(padding:const EdgeInsets.only(top:12),child:Text(S.t('diagnostics.description'))),
    // Événement, Serveur and Terminal are in Général, not repeated here; they
    // stay in the copied report. Main courante moved to Outils › Au PC
    // (22 h 18, points 6 and 8).
    // The version is only in « Cet appareil » of the panel (lot 29.4).
    // On its own line, apart from the description (card « Diagnostic :
    // messages contradictoires… », 10 Nov 2026, choice 2).
    if(VersionStatus.shown)const Padding(padding:EdgeInsets.only(top:12,bottom:12),child:VersionStatus()),
    // Battery card (30 Oct 2026, point F).
    _row(S.t('power.consumption'),child:Builder(builder:(_){final p=PowerState.instance;
      return Text(consumptionLine(trackingS:p.trackingS,moving:p.trackingMoving,reduced:p.gpsReduced,
        compass:SharedCompass.instance.running,saver:p.saver,t:S.t));})),
    // Cet appareil, Liaisons, Serveur (PCO / admin), « Copier le rapport » (lot 5).
    if(widget.api!=null)DiagnosticsPanel(api:widget.api!,server:widget.initial.serverUrl,eventId:widget.initial.eventId,actorId:widget.initial.deviceId,
      onChooseEvent:()=>_openTab('general')),
  ]);

  Widget _tabBody(String id)=>switch(id){
    'general'=>_generalTab(),'profile'=>_profileTab(),
    'notifications'=>_notificationsTab(),'diagnostics'=>_diagnosticsTab(),
    // Default frequencies of the bearing tool: Outils › Fréquences du
    // relevé (22 h 18, point 7).
    'event'=>EventSettingsSection(api:widget.api!,eventId:widget.initial.eventId,actorId:widget.initial.deviceId),
    'admin'=>AdminSection(server:widget.initial.serverUrl,rights:RightsState.instance.of(widget.initial.serverUrl),row:_row),
    'help'=>HelpContent(eventSettings:widget.store?.eventSettings(widget.initial.eventId)),
    _=>Padding(padding:const EdgeInsets.only(top:16),child:SarcadeAboutContent(serverUrl:widget.initial.serverUrl)),
  };

  Future<void> _setOperatorIcon(String? id) async {
    await widget.store!.setPreference(operatorIconKey,id);
    if(mounted)setState((){});
    try{await widget.api?.patchMyPreferences({'operator_icon':id});}catch(_){/* kept on this device */}
  }

  void _cancel(){
    final i=widget.initial;
    setState((){
      _server.text=i.serverUrl;_event.text=i.eventId;_device.text=i.deviceId;_callsign.text=i.callsign;
      _language=i.language;_aprsConsent=i.aprsTxConsent;_bypassDnd=i.immediateBypassDnd;_drawColor=defaultDrawColor(i.drawColor);
      _dirty=false;
    });
    _form.currentState?.reset();
    final nav=Navigator.of(context);
    if(nav.canPop())nav.pop();
  }

  Future<void> _trySave() async {
    // A refused field may sit in a hidden tab: show the first one.
    final general=_url(_server.text)!=null||_required(_event.text)!=null||_required(_device.text)!=null;
    if(general&&_tab!=0){
      _openTab(_tabs.first);
    }else if(!general&&_callsignCheck(_callsign.text)!=null){
      _openTab('profile');
    }
    await WidgetsBinding.instance.endOfFrame;
    if(mounted)await _save();
  }

  /// Paramètres as a list (card « Paramètres : moins d'onglets », option B,
  /// 9 Nov 2026). Every page stays built (Offstage, IndexedStack): the form
  /// keeps and validates all its fields, as with the tabs before.
  Widget _listLayout(BuildContext context){
    final wide=MediaQuery.sizeOf(context).width>=settingsWideWidth;
    final id=_tabs[_tab.clamp(0,_tabs.length-1)];
    final pages=IndexedStack(index:_tab.clamp(0,_tabs.length-1),children:[for(final p in _tabs)ListView(key:ValueKey('settings-page-$p'),
      padding:const EdgeInsets.fromLTRB(20,0,20,24),children:[_tabBody(p)])]);
    final list=ListenableBuilder(listenable:Listenable.merge([AccountManager.instance,AccessManager.instance,WindowsUpdates.instance]),builder:(context,_){
      final server=_serverText;
      final connection=connectionSummary(account:AccountManager.instance.sessionFor(server),access:AccessManager.instance.sessionFor(server),
        accessRequired:_accessRequired||AccessManager.instance.requiredFor(server));
      return ListView(key:const ValueKey('settings-list'),padding:const EdgeInsets.only(bottom:24),children:[
        SettingsAccountHeader(device:_device.text,callsign:_callsign.text,connection:connection,selected:wide&&id=='profile',onTap:()=>_openTab('profile')),
        const Divider(height:1),
        for(final r in _tabs)if(r!='profile')SettingsListRow(id:r,selected:wide&&id==r,onTap:()=>_openTab(r),
          value:r=='diagnostics'&&diagnosticsAlert()?S.t('settings.rowAlert'):r=='about'&&windowsUpdateAlert()?S.t('settings.rowUpdate'):null,
          warn:r=='diagnostics'||r=='about'),
      ]);
    });
    if(wide){
      return Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        SizedBox(width:340,child:list),const VerticalDivider(width:1),Expanded(child:pages)]);
    }
    return PopScope(canPop:_home,onPopInvokedWithResult:(did,_){if(!did)setState(()=>_home=true);},child:Stack(children:[
      Offstage(offstage:!_home,child:list),
      Offstage(offstage:_home,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Padding(padding:const EdgeInsets.fromLTRB(4,0,16,4),child:Row(children:[
          IconButton(key:const ValueKey('settings-back'),tooltip:S.t('settings.backToList'),onPressed:()=>setState(()=>_home=true),icon:const Icon(Icons.arrow_back)),
          const SizedBox(width:4),
          Expanded(child:Text(settingsRowTitle(id),key:const ValueKey('settings-page-title'),style:Theme.of(context).textTheme.headlineSmall)),
        ])),
        const Divider(height:1),
        Expanded(child:pages),
      ])),
    ]));
  }

  @override
  Widget build(BuildContext context){
    final t=Theme.of(context);
    // Phone: orange dot on « Paramètres » of the bottom bar while a change
    // waits to be saved (card « Menu du bas toujours visible », 8 Nov 2026).
    if(!widget.firstRun&&settingsUnsaved.value!=_dirty){
      WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)settingsUnsaved.value=_dirty;});
    }
    return Scaffold(
      // Same surface as the content in both themes (revue n° 68).
      appBar:LinkedAppBar(linkStatus:!widget.firstRun,automaticallyImplyLeading:!widget.firstRun,backgroundColor:t.colorScheme.surface),
      // Fixed save bar at the bottom (charte « style Play Console »); none on
      // Diagnostic and À propos, nothing to save there (revue n° 64).
      bottomNavigationBar:settingsShowsSaveBar(tab:!widget.firstRun&&_home&&MediaQuery.sizeOf(context).width<settingsWideWidth?'list':_tabs[_tab.clamp(0,_tabs.length-1)],firstRun:widget.firstRun,dirty:_dirty)?SaveBar(changed:widget.firstRun||_dirty,saving:_saving,onSave:_trySave,
        onCancel:widget.firstRun?null:_cancel):null,
      body:SafeArea(child:Center(child:ConstrainedBox(
        constraints:const BoxConstraints(maxWidth:900),
        child:Form(key:_form,onChanged:widget.firstRun?null:_touch,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          // Phone, a page open: its own title with ← instead.
          if(widget.firstRun||_home||MediaQuery.sizeOf(context).width>=settingsWideWidth)
          Padding(padding:const EdgeInsets.fromLTRB(20,0,20,4),child:Text(widget.firstRun?S.t('settings.firstRun'):S.t('settings.title'),
            style:t.textTheme.headlineMedium)),
          // « En-tête allégé » (30 Oct 2026, 2 h 56): no lines under the
          // title; server, event and terminal are in Général (lot 19).
          if(widget.firstRun)Padding(padding:const EdgeInsets.symmetric(horizontal:20),child:Text(S.t('settings.subtitleFirst'),
            style:t.textTheme.bodyMedium?.copyWith(color:t.colorScheme.onSurfaceVariant))),
          const SizedBox(height:8),
          // Discreet invitation to sign in (lot 26, device without account).
          if(!widget.firstRun&&(_home||MediaQuery.sizeOf(context).width>=settingsWideWidth))AccountBanner(server:widget.initial.serverUrl,deviceId:widget.initial.deviceId,store:widget.store,invite:true),
          if(!widget.firstRun)Expanded(child:_listLayout(context))
          else...[
          // Underlined tabs; every tab stays built so that the form keeps
          // and validates all its fields.
          DefaultTabController(key:ValueKey(_tabs.length),length:_tabs.length,initialIndex:_tab,child:Builder(builder:(context){
            final c=DefaultTabController.of(context);
            if(c.index!=_tab)c.animateTo(_tab);
            // Dot on À propos when a Windows version is available (lot 25).
            return ListenableBuilder(listenable:WindowsUpdates.instance,builder:(context,_)=>TabBar(isScrollable:true,tabAlignment:TabAlignment.start,
              onTap:(i)=>setState(()=>_tab=i),
              tabs:[for(final id in _tabs)id=='diagnostics'&&diagnosticsAlert()
                ?Tab(child:Badge(key:const ValueKey('diag-tab-alert'),smallSize:8,offset:const Offset(8,-2),child:Text(settingsTabLabel(id))))
                :id=='about'&&windowsUpdateAlert()
                ?Tab(child:Badge(key:const ValueKey('about-tab-update'),smallSize:8,offset:const Offset(8,-2),child:Text(settingsTabLabel(id))))
                :Tab(text:settingsTabLabel(id))]));
          })),
          const Divider(height:1),
          Expanded(child:IndexedStack(index:_tab,children:[for(final id in _tabs)ListView(
            padding:const EdgeInsets.fromLTRB(20,0,20,24),children:[_tabBody(id)])])),
          ],
        ])),
      ))),
    );
  }
}

/// The save bar on the list itself only for a change waiting to be saved.
/// One setting per line of Paramètres: bold label and grey help on the left
/// (under it on a phone), the control on the right. Public for the tests at
/// 320 px of Paramètres › Administration (lot 28).
Widget settingsRowLayout(BuildContext context,String label,{String? help,String? tip,required Widget child}){
  final t=Theme.of(context);
  final head=Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[
      Flexible(child:Text(label,style:t.textTheme.titleSmall?.copyWith(fontWeight:FontWeight.w600))),
      // Fewer words (card « Paramètres › Général, mise en page », 16 h 38):
      // the explanation in an ⓘ rather than grey text.
      if(tip!=null)Tooltip(message:tip,triggerMode:TooltipTriggerMode.tap,child:Padding(padding:const EdgeInsets.only(left:6),
        child:Icon(Icons.info_outline,size:16,color:t.colorScheme.onSurfaceVariant))),
    ]),
    if(help!=null)Padding(padding:const EdgeInsets.only(top:2),child:Text(help,style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant))),
  ]);
  return Column(children:[
    // Width of the screen, not a LayoutBuilder: a field keeps its focus
    // while the keyboard opens.
    Padding(padding:const EdgeInsets.symmetric(vertical:14),child:MediaQuery.sizeOf(context).width>=640
      ? Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(flex:2,child:head),const SizedBox(width:24),Expanded(flex:3,child:child)])
      : Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[head,const SizedBox(height:8),child])),
    const Divider(height:1),
  ]);
}

/// Tabs of Paramètres: Général, Événement (PCO), Profil, Notifications,
/// Diagnostic, Aide, À propos; at the first setup Général, Profil, À propos.
/// « Aide » just above « À propos » (card « Paramètres : menu « Aide » »,
/// validated on 10 Nov 2026, choice 1).
List<String> settingsTabs({required bool firstRun,required bool event,bool admin=false})=>firstRun
  ?const ['general','profile','about']
  :['general',if(event)'event','profile','notifications',if(admin)'admin','diagnostics','help','about'];
/// Name of a tab; « Administration » is a text of lot 26.
String settingsTabLabel(String id)=>id=='admin'?S.t('admin.title'):S.t('settings.tab.$id');

/// Phone: a change of Paramètres not saved yet; the bottom bar shows an
/// orange dot on « Paramètres » (Paramètres is a tab since 8 Nov 2026).
final settingsUnsaved=ValueNotifier<bool>(false);

/// Paramètres touched again in the bottom bar while shown (card
/// « Paramètres : retoucher le bouton Paramètres revient à la liste »,
/// validated on 9 Nov 2026): the open page goes back to the list.
final settingsBackToList=ChangeNotifier();

/// Tab the next opening of Paramètres shows (« Choisir un événement » of
/// the Diagnostic over the map, lot 19); read once.
String? settingsRequestedTab;

/// The save bar, except on Diagnostic and À propos with nothing changed.
/// Nor on Général, applied at once (card « Paramètres › Général : onglet
/// compact », choice 7).
bool settingsShowsSaveBar({required String tab,required bool firstRun,required bool dirty})=>firstRun||dirty||!(tab=='list'||tab=='general'||tab=='diagnostics'||tab=='about'||tab=='help'||tab=='admin'||tab=='notifications'||tab=='profile'||tab=='event');
/// Name of a remembered server in the list: « SARCADE · app.sarcade.org »
/// as it is, « Club · 192.168.0.110:8000 » when the name does not say the
/// address (lot 28: no address twice).
String serverChoiceLabel(SavedServer s)=>s.label.toLowerCase().contains(s.shortAddress.toLowerCase())?s.label:'${s.label} · ${s.shortAddress}';

