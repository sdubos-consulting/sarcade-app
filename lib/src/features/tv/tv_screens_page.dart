import 'dart:async';

import 'package:flutter/material.dart';
import '../../ui/menu_entry.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import '../../l10n/strings.dart';
import 'tv_screens_button.dart' show tvScreensChanged;
import '../../models/comm_group.dart';
import '../../services/sarcade_api.dart';
import '../../ui/theme.dart' show themeMode;
import 'tv_code.dart';
import 'tv_nearby.dart';
import 'tv_qr_scan_page.dart';
import 'tv_screen_buttons.dart';
import 'tv_theme.dart';
import 'tv_view.dart';
import '../../ui/link_status.dart';
import '../../ui/text_fields_dialog.dart';

/// « Afficher sur une TV » (any operator, decision of the porteur of
/// 29 October 2026): pair the screen opened on tv.sarcade.org by scanning
/// its QR code (Android, iPhone) or typing its code, then list and revoke
/// the screens of the event.
class TvScreensPage extends StatelessWidget {
  final SarcadeApi api; final String eventId;
  /// The camera opens at once.
  final bool scanOnOpen;
  const TvScreensPage({super.key,required this.api,required this.eventId,this.scanOnOpen=false});
  // Card « Afficher sur une TV : écran réorganisé » (lot 29.5): title
  // « Écrans TV », no long sentence; « Mes écrans » first (panel).
  @override Widget build(BuildContext context)=>Scaffold(appBar:LinkedAppBar(title:Text(S.t('tv.screensTitle'))),
    body:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,24),children:[
      TvScreensPanel(api:api,eventId:eventId,scanOnOpen:scanOnOpen),
    ]));
}

/// The content of « Afficher sur une TV » (the only place where the screens
/// are managed since 30 Oct 2026: section removed from Paramètres).
class TvScreensPanel extends StatefulWidget {
  final SarcadeApi api; final String eventId; final bool scanOnOpen;
  const TvScreensPanel({super.key,required this.api,required this.eventId,this.scanOnOpen=false});
  @override State<TvScreensPanel> createState()=>_TvScreensPanelState();
}

class _TvScreensPanelState extends State<TvScreensPanel> {
  List<Map<String,dynamic>>? _list; bool _busy=false; bool _offline=false;

  /// TVs waiting for a code on the same network (card « Écrans TV : page
  /// plus directe », 11 Nov 2026, choice 2), while the discovery is on.
  List<({String code,String name})> _nearby=const [];
  Timer? _nearbyTimer;

  @override void initState(){
    super.initState();_load();
    unawaited(_loadNearby());
    _nearbyTimer=Timer.periodic(const Duration(seconds:10),(_)=>unawaited(_loadNearby()));
    tvDiscovery.addListener(_discoveryChanged);
    if(widget.scanOnOpen&&canScanTvQr)WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_scan();});
  }

  @override void dispose(){
    _nearbyTimer?.cancel();
    tvDiscovery.removeListener(_discoveryChanged);
    super.dispose();
  }

  void _discoveryChanged(){
    if(!mounted)return;
    setState(()=>_nearby=const []);
    unawaited(_loadNearby());
  }

  Future<void> _loadNearby() async {
    if(!tvDiscovery.value||_busy)return;
    try{
      final l=await widget.api.tvNearbyScreens();
      if(mounted)setState(()=>_nearby=l);
    }catch(_){/* offline: nothing offered */}
  }

  /// « Connecter » of a TV nearby: its name proposed, then paired.
  Future<void> _connectNearby(({String code,String name}) n)=>TvNearbyGate.during(() async {
    final name=await _askName(S.t('tv.nameTitle'),n.name);
    if(name!=null&&mounted){await _approve(n.code,name:name);setState(()=>_nearby=[for(final x in _nearby)if(x.code!=n.code)x]);}
  });

  Future<void> _load() async {
    try{
      final l=await widget.api.displays(widget.eventId);
      if(mounted)setState((){_list=l;_offline=false;});
    }catch(_){
      if(mounted)setState(()=>_offline=true);
    }
  }

  void _say(String key){
    if(!mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t(key))));
  }

  Future<void> _approve(String code,{String? name}) async {
    TvNearbyGate.handled(code);
    setState(()=>_busy=true);
    try{
      await widget.api.approveDisplay(code,widget.eventId,name:name);
      _say('tv.done');
      await _load();
      // The « Écrans » button of the map shows it at once (1 Nov 2026).
      tvScreensChanged.value++;
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==401||e.statusCode==403?'tv.signIn':'tv.unknownCode');
    }catch(_){
      _say('event.offline');
    }finally{
      if(mounted)setState(()=>_busy=false);
    }
  }

  // Lot 11: the whole pairing (camera, name) suspends « Écran à proximité »;
  // a scanned code is never offered again by that dialog.
  Future<void> _scan()=>TvNearbyGate.during(() async {
    final code=await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>const TvQrScanPage()));
    if(code==null||!mounted)return;
    TvNearbyGate.handled(code);
    // Name chosen at pairing, the default name of the TV proposed.
    final name=await _askName(S.t('tv.nameTitle'),await widget.api.tvCodeName(code)??'');
    if(name!=null&&mounted)await _approve(code,name:name);
  });

  /// Name of a screen (after the scan, « Renommer »); null when cancelled.
  Future<String?> _askName(String title,String initial) async {
    if(!mounted)return null;
    return showTextFieldsDialog<String>(context,initial:[initial],builder:(c,f,_)=>AlertDialog(title:Text(title),
      content:TextField(key:const ValueKey('tv-name'),controller:f[0],autofocus:true,inputFormatters:[LengthLimitingTextInputFormatter(60)],
        decoration:InputDecoration(labelText:S.t('tv.name'),helperText:S.t('tv.nameHelp'))),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,f[0].text.trim()),child:Text(S.t('common.ok')))]));
  }

  Future<void> _type()=>TvNearbyGate.during(_typeCode);
  Future<void> _typeCode() async {
    var edited=false, closed=false; var asked='';
    final typed=await showTextFieldsDialog<(String,String)>(context,initial:const ['',''],builder:(c,f,set)=>AlertDialog(title:Text(S.t('tv.type')),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:f[0],autofocus:true,textCapitalization:TextCapitalization.characters,
          decoration:InputDecoration(labelText:S.t('tv.code'),helperText:S.t('tv.codeHelp')),
          onChanged:(t) async {
            // Default name of the TV, proposed once the code is complete.
            final code=tvCodeFrom(t);
            if(code==null||code.length!=6||code==asked||edited)return;
            asked=code;
            final n=await widget.api.tvCodeName(code);
            if(n!=null&&!edited&&!closed&&asked==code)set(()=>f[1].text=n);
          }),
        const SizedBox(height:8),
        TextField(key:const ValueKey('tv-name'),controller:f[1],inputFormatters:[LengthLimitingTextInputFormatter(60)],onChanged:(_)=>edited=true,
          decoration:InputDecoration(labelText:S.t('tv.name'),helperText:S.t('tv.nameHelp'))),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,(f[0].text,f[1].text.trim())),child:Text(S.t('tv.show')))]));
    closed=true;
    if(typed==null||!mounted)return;
    final code=tvCodeFrom(typed.$1);
    if(code==null){_say('tv.unknownCode');return;}
    await _approve(code,name:typed.$2);
  }

  /// « Renommer » (menu ⋮ of a screen).
  Future<void> _rename(Map<String,dynamic> d) async {
    final name=await _askName(S.t('tv.rename'),'${d['name']??''}');
    if(name==null||name.isEmpty||!mounted)return;
    try{
      await widget.api.renameDisplay(widget.eventId,'${d['id']}',name);
      _say('tv.renamed');
      await _load();
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==401||e.statusCode==403?'tv.signIn':'event.offline');
    }catch(_){
      _say('event.offline');
    }
  }

  /// « Identifier »: the TV shows its name in very large letters for 5 s.
  Future<void> _identify(Map<String,dynamic> d) async {
    try{
      await widget.api.identifyDisplay(widget.eventId,'${d['id']}');
      _say('tv.identifySent');
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==401||e.statusCode==403?'tv.signIn':'event.offline');
    }catch(_){
      _say('event.offline');
    }
  }

  Future<void> _revoke(Map<String,dynamic> d) async {
    try{
      await widget.api.revokeDisplay(widget.eventId,'${d['id']}');
      await _load();
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==401||e.statusCode==403?'tv.signIn':'event.offline');
    }catch(_){
      _say('event.offline');
    }
  }

  /// « Retirer le bandeau SOS »: the person who paired the screen or an
  /// administrator; the SOS pill of the TV stays until the end of distress.
  Future<void> _clearSos(Map<String,dynamic> d) async {
    try{
      await widget.api.clearDisplayAlert(widget.eventId,'${d['id']}');
      _say('tv.sosCleared');
      await _load();
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==403?'tv.sosForbidden':e.statusCode==401?'tv.signIn':'event.offline');
    }catch(_){
      _say('event.offline');
    }
  }

  /// « Envoyer ma vue »: summary of what leaves (zoom, base map, layers)
  /// with the « Colonne des messages » box; null when cancelled.
  Future<bool?> _confirmView(TvView v,TvOptions? o,bool messages) async {
    var m=messages;
    final layers=o==null?const <String>[]:tvShownLayers(o.layers);
    return showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(title:Text(S.t('tv.sendView')),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(S.t('tv.sumZoom',{'z':v.zoom.toStringAsFixed(1).replaceAll('.',',')})),
        Text(S.t('tv.sumBase',{'b':v.basemapName.isEmpty?v.basemapId:v.basemapName})),
        Text(S.t('tv.sumLayers',{'l':layers.isEmpty?S.t('tv.sumNone'):[for(final k in layers)S.t(tvLayerLabels[k]!)].join(', ')})),
        CheckboxListTile(key:const ValueKey('tv-messages-box'),contentPadding:EdgeInsets.zero,value:m,onChanged:(x)=>set(()=>m=x??true),
          title:Text(S.t('tv.messagesColumn'))),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,m),child:Text(S.t('tv.send')))])));
  }

  /// « Jour / Nuit / Automatique » of this screen.
  Future<void> _theme(Map<String,dynamic> d) async {
    final t=await chooseTvTheme(context,d);
    if(t!=null)await _setTheme(d,t);
  }

  Future<void> _setTheme(Map<String,dynamic> d,String t) async {
    try{
      await widget.api.setDisplayTheme(widget.eventId,'${d['id']}',t);
      _say('tv.themeSet');
      await _load();
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==401||e.statusCode==403?'tv.signIn':'event.offline');
    }catch(_){
      _say('event.offline');
    }
  }

  /// Mode button of the line: one tap goes to the next mode (lot 19).
  Future<void> _nextTheme(Map<String,dynamic> d)=>_setTheme(d,nextTvTheme(tvThemeOf(d)));

  /// Actions of the menu ⋮ and of the buttons of the line: the same calls.
  void _act(Map<String,dynamic> d,String a){
    switch(a){
      case 'view':_view(d,mine:true);
      case 'auto':_view(d,mine:false);
      case 'messages':_messages(d);
      case 'revoke':_revoke(d);
      case 'sos':_clearSos(d);
      case 'rename':_rename(d);
      case 'identify':_identify(d);
      case 'theme':_theme(d);
      case 'nextTheme':_nextTheme(d);
    }
  }

  /// « Messages : afficher / masquer » of this screen, at once, without
  /// sending the view again.
  Future<void> _messages(Map<String,dynamic> d) async {
    final show=d['messages']==false;
    try{
      await widget.api.setDisplayMessages(widget.eventId,'${d['id']}',show);
      _say(show?'tv.messagesShown':'tv.messagesHidden');
      await _load();
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==401||e.statusCode==403?'tv.signIn':'event.offline');
    }catch(_){
      _say('event.offline');
    }
  }

  /// « Envoyer ma vue » (view of the map of this device) or « Revenir à la
  /// vue par défaut » (null); no automatic return (30 Oct 2026).
  Future<void> _view(Map<String,dynamic> d,{required bool mine}) async {
    final v=mine?currentMapView?.call():null;
    if(mine&&v==null){_say('tv.noMap');return;}
    Map<String,dynamic>? json; bool? messages;
    if(v!=null){
      final o=currentMapOptions?.call();
      final m=await _confirmView(v,o,d['messages']!=false);
      if(m==null||!mounted)return;
      json=tvViewJson(v,options:o==null?null:(layers:o.layers,opacity:o.opacity,messages:m),from:myActorId,theme:themeMode.value);
      if(o==null)json['messages']=m;
      messages=m;
    }
    try{
      await widget.api.sendDisplayView(widget.eventId,'${d['id']}',json,messages:messages);
      await _load();
      _say(mine?'tv.viewSent':'tv.autoSent');
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==401||e.statusCode==403?'tv.signIn':'event.offline');
    }catch(_){
      _say('event.offline');
    }
  }

  @override
  Widget build(BuildContext context){
    final t=Theme.of(context); final all=_list; final wide=tvButtonsWide(context);
    // Only the active screens (choices 7 and 9): a revoked or expired one
    // can never connect again; the server erases it after 14 days.
    final list=all==null?null:tvVisibleScreens(all,showOld:false);
    final paired={for(final d in list??const <Map<String,dynamic>>[])'${d['code']}'};
    final nearby=[for(final n in _nearby)if(!paired.contains(n.code))n];
    Widget section(String text)=>Padding(padding:const EdgeInsets.only(top:12,bottom:4),child:Text(text,
      style:t.textTheme.titleSmall?.copyWith(fontWeight:FontWeight.w600,color:t.colorScheme.primary)));
    return AbsorbPointer(absorbing:_busy,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,mainAxisSize:MainAxisSize.min,children:[
        if(_busy)const Padding(padding:EdgeInsets.only(bottom:8),child:LinearProgressIndicator()),
        // Choice 2: the TVs found nearby first, each with « Connecter ».
        if(nearby.isNotEmpty)...[
          section(S.t('tv.nearbySection')),
          for(final n in nearby)ListTile(key:ValueKey('tv-nearby-${n.code}'),contentPadding:EdgeInsets.zero,leading:const Icon(Icons.connected_tv),
            title:Text(n.name.trim().isEmpty?'${S.t('tv.code')} ${n.code}':n.name),
            subtitle:n.name.trim().isEmpty?null:Text('${S.t('tv.code')} ${n.code}'),
            trailing:FilledButton(onPressed:()=>_connectNearby(n),child:Text(S.t('tv.connect')))),
        ],
        // « Mes écrans » (lot 29.5), hidden when empty (choice 1).
        if(_offline||list==null||list.isNotEmpty)section(S.t('tv.mine')),
        if(_offline)ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.cloud_off),title:Text(S.t('event.offline')),
          trailing:OutlinedButton(onPressed:_load,child:Text(S.t('common.retry'))))
        else if(list==null)const Padding(padding:EdgeInsets.all(16),child:Center(child:CircularProgressIndicator()))
        else for(final d in list)Column(key:ValueKey('tv-screen-${d['id']}'),crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          ListTile(contentPadding:EdgeInsets.zero,
          leading:Icon(d['active']==true?(d['alert']==true?Icons.sos:Icons.tv):Icons.tv_off,
            color:d['active']==true?(d['alert']==true?t.colorScheme.error:Colors.green):null),
          // Name as title, then last activity, the code in small, « vue de… ».
          title:Text(tvScreenTitle(d,S.t('tv.code'))),
          subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
            Text([d['active']==true?(d['last_seen'] is num?S.t('tv.lastSeen',{'t':tvWhen(d['last_seen'],lang:S.lang)}):S.t('tv.until',{'t':tvWhen(d['expires'],lang:S.lang)})):S.t(d['revoked']==true?'tv.revoked':'tv.expired'),
              if(d['active']==true&&d['messages']==false)S.t('tv.messagesOff')].join(' · ')),
            Text([if('${d['name']??''}'.trim().isNotEmpty)'${S.t('tv.code')} ${d['code']??''}',
              if(d['active']==true&&'${d['view_from']??''}'.isNotEmpty)S.t('tv.viewOf',{'who':d['view_from']})].join(' · '),
              style:t.textTheme.bodySmall),
          ]),
          // Lot 19: the rare actions stay in ⋮; on a phone, all but
          // « Envoyer ma vue ».
          trailing:d['active']==true?PopupMenuButton<String>(key:ValueKey('tv-menu-${d['id']}'),
            onSelected:(a)=>_act(d,a),
            itemBuilder:(_)=>[
              if(!wide)PopupMenuItem(value:'identify',child:menuEntry(context,icon:Icons.highlight_alt,title:S.t('tv.identify'))),
              PopupMenuItem(value:'rename',child:menuEntry(context,icon:Icons.edit_outlined,title:S.t('tv.rename'))),
              PopupMenuItem(value:'auto',child:menuEntry(context,icon:Icons.fit_screen,title:S.t('tv.auto'))),
              if(!wide)...[
                PopupMenuItem(value:'theme',child:menuEntry(context,icon:Icons.brightness_6_outlined,title:S.t('tv.theme'),
                  detail:S.t('tv.theme.${tvThemeOf(d)}'))),
                PopupMenuItem(value:'messages',child:menuEntry(context,icon:d['messages']==false?Icons.chat_outlined:Icons.speaker_notes_off_outlined,
                  title:S.t(d['messages']==false?'tv.messagesShow':'tv.messagesHide'))),
                PopupMenuItem(value:'sos',enabled:d['can_clear_alert']!=false,
                  child:menuEntry(context,icon:Icons.sos,done:d['can_clear_alert']==false,title:S.t('tv.clearSos'))),
              ],
            ]):null),
          if(d['active']==true)Padding(padding:const EdgeInsets.only(bottom:8),child:TvScreenButtons(screen:d,wide:wide,
            onAction:(a)=>_act(d,a==TvAction.theme?'nextTheme':a))),
          // Choice 9: « Révoquer » in sight on each screen.
          Align(alignment:Alignment.centerRight,child:TextButton.icon(key:ValueKey('tv-revoke-${d['id']}'),onPressed:()=>_act(d,'revoke'),
            style:TextButton.styleFrom(foregroundColor:t.colorScheme.error),icon:const Icon(Icons.tv_off,size:18),label:Text(S.t('tv.revoke')))),
        ]),
        // « Connecter un nouvel écran »: one sentence (choice 6), one main
        // button and « Saisir le code » as a link under it (choice 3); no
        // copy of the address, typed on the TV (choice 4).
        section(S.t('tv.connectNew')),
        Text(S.t(canScanTvQr?'tv.howTo':'tv.howToType'),key:const ValueKey('tv-how-to')),
        const SizedBox(height:8),
        if(canScanTvQr)...[
          FilledButton.icon(key:const ValueKey('tv-scan'),onPressed:_scan,icon:const Icon(Icons.qr_code_scanner),label:Text(S.t('tv.scan'))),
          Align(alignment:Alignment.center,child:TextButton(key:const ValueKey('tv-type'),onPressed:_type,child:Text(S.t('tv.type')))),
        ]else FilledButton.icon(key:const ValueKey('tv-type'),onPressed:_type,icon:const Icon(Icons.keyboard_outlined),label:Text(S.t('tv.type'))),
        const SizedBox(height:8),
        // « Découverte automatique des écrans » (1 Nov 2026, 8 h 01), at the
        // bottom of the page (choice 2).
        ValueListenableBuilder<bool>(valueListenable:tvDiscovery,builder:(_,on,_)=>SwitchListTile(key:const ValueKey('tv-discovery'),
          dense:true,contentPadding:EdgeInsets.zero,value:on,onChanged:(v)=>tvDiscovery.value=v,
          title:Text(S.t('tv.discovery')),subtitle:Text(S.t('tv.discoveryShort')))),
      ]));
  }
}
