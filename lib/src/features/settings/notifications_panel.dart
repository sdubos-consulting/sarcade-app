import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/version.dart';
import '../../l10n/strings.dart';
import '../../offline/local_store.dart';
import '../../operations/event_settings.dart' show StoreRelease;
import '../../operations/version_state.dart';
import '../../platform/platform_services.dart';
import '../../services/notification_service.dart';
import '../../services/notification_actions.dart' show soundChoices, soundDefaults;
import '../../services/sarcade_api.dart';
import '../../services/wakeup_fcm.dart';
import '../../services/wakeup_state.dart';
import '../../models/message.dart' show priorityKey;
import '../../ui/choice_pills.dart';
import '../messages/read_aloud.dart';
import '../../ui/setting_line.dart';
import '../../ui/app_sheet.dart';

/// Sound by priority kept on the device (« notif_sound:routine » …).
Map<String,String> readSoundPrefs(LocalStore? store)=>{
  for(final p in soundChoices.keys)
    if(store?.preference('notif_sound:$p') case final String v)p:v};

bool get _android=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.android;
bool get _ios=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.iOS;
/// Wake-up when SARCADE is closed exists here: Web Push or Firebase.
bool get wakeupSupported=>isWebPlatform||fcmAvailable;

/// Rows of Paramètres › Notifications (decisions of 29 Oct 2026): state of
/// the permissions, « Tester le réveil » with its result, sound by priority.
class NotificationsPanel extends StatefulWidget {
  final SarcadeApi? api; final String eventId, deviceId; final LocalStore? store;
  /// One row of the settings screen (label, help, control).
  final Widget Function(String label,{String? help,required Widget child}) row;
  const NotificationsPanel({super.key,required this.api,required this.eventId,required this.deviceId,required this.store,required this.row});
  @override State<NotificationsPanel> createState()=>_NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> with WidgetsBindingObserver {
  bool? _allowed; bool _testing=false; String? _result;
  late Map<String,String> _sounds=readSoundPrefs(widget.store);
  late String _readMode=readAloudMode(widget.store);
  late bool _readRoutine=readAloudRoutine(widget.store);

  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);_read();}
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);super.dispose();}
  // Back from the system settings: read the permission again.
  @override void didChangeAppLifecycleState(AppLifecycleState s){if(s==AppLifecycleState.resumed)_read();}

  Future<void> _read() async {
    final v=await NotificationService().permissionGranted();
    if(mounted)setState(()=>_allowed=v);
  }

  Future<void> _fixPermission() async {
    await NotificationService().openPermissionSettings();
    await _read();
    if(_allowed==true)wakeupRegistered.value=await registerWakeupHook?.call()??wakeupRegistered.value;
  }

  Future<void> _test() async {
    final api=widget.api;
    if(api==null)return;
    setState((){_testing=true;_result=null;});
    final got=Completer<bool>();
    final sub=(isWebPlatform?webWakeSignals():fcmForeground()).listen((d){if(d['kind']=='test'&&!got.isCompleted)got.complete(true);});
    var ok=false;
    try{
      final hook=registerWakeupHook;
      if(hook!=null)wakeupRegistered.value=await hook();
      final r=await api.testWakeup(widget.eventId,widget.deviceId);
      if(((r['sent'] as num?)??0)>0)ok=await got.future.timeout(const Duration(seconds:20),onTimeout:()=>false);
    }catch(_){ok=false;}
    await sub.cancel();
    await _read();
    final now=DateTime.now(); String two(int v)=>v.toString().padLeft(2,'0');
    if(mounted)setState((){_testing=false;_result=ok?S.t('wakeup.receivedAt',{'time':'${two(now.hour)}:${two(now.minute)}'}):S.t('wakeup.notReceived');});
  }

  Future<void> _setSound(String priority,String v) async {
    setState(()=>_sounds={..._sounds,priority:v});
    NotificationService().sounds=_sounds;
    await widget.store?.setPreference('notif_sound:$priority',v);
  }

  /// Choice of a sound in a sheet: one line per sound, the current one ticked.
  Future<void> _chooseSound(String priority) async {
    final current=_sounds[priority]??soundDefaults[priority]!;
    final picked=await showAppSheet<String>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Padding(padding:const EdgeInsets.fromLTRB(16,0,16,8),child:Text(S.t(priorityKey(priority)),style:Theme.of(c).textTheme.titleMedium)),
      for(final v in soundChoices[priority]!)ListTile(key:ValueKey('sound-$priority-$v'),title:Text(S.t('sound.$v')),
        trailing:v==current?Icon(Icons.check,color:Theme.of(c).colorScheme.primary):null,onTap:()=>Navigator.pop(c,v)),
    ])));
    if(picked!=null&&picked!=current)await _setSound(priority,picked);
  }

  /// State in one band (card « Paramètres › Notifications : onglet compact »,
  /// validated on 5 Nov 2026, choice 1): ready, or what blocks with the
  /// button that fixes it.
  Widget _band(bool? wake){
    final t=Theme.of(context); final s=t.colorScheme;
    final blocked=NotificationService().permissionBlocked;
    final ready=_allowed==true&&(!wakeupSupported||wake==true);
    final unknown=_allowed==null;
    final problems=[
      if(_allowed==false)S.t('settings.notAllowed'),
      if(wakeupSupported&&_allowed!=false&&wake==false)'${S.t('settings.wakeupClosed')} : ${S.t('settings.inactive').toLowerCase()}',
    ];
    final colour=ready?Colors.green.shade700:unknown?s.onSurfaceVariant:s.error;
    return Container(key:const ValueKey('notif-band'),margin:const EdgeInsets.only(top:12,bottom:4),padding:const EdgeInsets.all(12),
      decoration:BoxDecoration(color:colour.withValues(alpha:0.08),borderRadius:BorderRadius.circular(12)),
      child:Row(children:[
        Icon(ready?Icons.check_circle:unknown?Icons.help_outline:Icons.error_outline,color:colour),
        const SizedBox(width:10),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(ready?S.t('notifications.ready'):unknown?S.t('settings.unknown'):problems.join(' · '),style:t.textTheme.bodyMedium?.copyWith(color:colour,fontWeight:FontWeight.w600)),
          if(blocked&&!ready)Text(S.t('notifications.refused'),style:t.textTheme.bodySmall),
        ])),
        if(!ready&&!unknown&&!blocked)TextButton(onPressed:_fixPermission,
          child:Text(isWebPlatform?S.t('notifications.enable'):S.t('settings.openSystem'))),
      ]));
  }

  @override
  Widget build(BuildContext context){
    Widget sound(String p,{String? help})=>SettingLine(key:ValueKey('sound-line-$p'),title:S.t(priorityKey(p)),help:help,
      value:S.t('sound.${_sounds[p]??soundDefaults[p]!}'),onTap:()=>unawaited(_chooseSound(p)));
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      ValueListenableBuilder<bool?>(valueListenable:wakeupRegistered,builder:(_,wake,_)=>_band(wake)),
      if(wakeupSupported&&widget.api!=null)SettingLine(key:const ValueKey('wakeup-test-line'),title:S.t('wakeup.test'),
        help:_result??S.t('wakeup.testSettingsHelp'),
        trailing:_testing?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2))
          :TextButton(onPressed:_test,child:Text(S.t('wakeup.testShort')))),
      SettingsSectionTitle(S.t('sound.title')),
      sound('routine',help:S.t('sound.routineHelp')),
      sound('urgent'),
      sound('immediate',help:S.t('sound.sosHelp')),
      // Card « Messages : lecture à voix haute sur le téléphone » (9 Nov 2026).
      SettingsSectionTitle(S.t('readAloud.title')),
      Padding(padding:const EdgeInsets.symmetric(vertical:6),child:ChoicePills<String>(key:const ValueKey('read-aloud-mode'),equalWidth:true,
        choices:[for(final m in readAloudModes)(value:m,label:S.t('readAloud.$m'),icon:null)],selected:_readMode,
        onSelected:(v){setState(()=>_readMode=v);unawaited(widget.store?.setPreference(readAloudModeKey,v));})),
      Text(S.t('readAloud.help.$_readMode'),style:Theme.of(context).textTheme.bodySmall),
      if(_readMode!='never')SwitchListTile(key:const ValueKey('read-aloud-routine'),contentPadding:EdgeInsets.zero,
        title:Text(S.t('readAloud.routine')),value:_readRoutine,
        onChanged:(v){setState(()=>_readRoutine=v);unawaited(widget.store?.setPreference(readAloudRoutineKey,v?'1':'0'));}),
      // iPhone: Apple has not granted the critical alerts yet: shown, greyed, no control.
      if(_ios)Opacity(opacity:0.6,child:SettingLine(title:S.t('settings.dndBypass'),help:S.t('settings.criticalIos'))),
    ]);
  }
}

/// Phones: « À jour » or « Nouvelle version disponible » with « Mettre à
/// jour » (TestFlight, Google Play); never an obligation (29 Oct 2026).
class VersionStatus extends StatelessWidget {
  const VersionStatus({super.key});
  static bool get shown=>_android||_ios;

  static Future<void> openStore(StoreRelease release) async {
    final urls=[
      if(release.url!=null)release.url!,
      if(_ios)...['itms-beta://','https://testflight.apple.com/'],
      if(_android)...['market://details?id=$androidApplicationId','https://play.google.com/store/apps/details?id=$androidApplicationId'],
    ];
    for(final u in urls){
      try{if(await launchUrl(Uri.parse(u),mode:LaunchMode.externalApplication))return;}catch(_){/* next one */}
    }
  }

  @override
  Widget build(BuildContext context)=>!shown?const SizedBox.shrink():ValueListenableBuilder<StoreRelease?>(valueListenable:latestRelease,builder:(context,r,_){
    if(r==null)return const SizedBox.shrink();
    final t=Theme.of(context);
    if(!r.newerThan(appVersion,appBuildNumber)){
      // « Version à jour », not « À jour »: it speaks of the application, not
      // of the session (card « Diagnostic : messages contradictoires… »,
      // 10 Nov 2026, choice 2).
      return Row(key:const ValueKey('version-up-to-date'),children:[Icon(Icons.check_circle,size:18,color:Colors.green.shade700),const SizedBox(width:6),Text(S.t('version.upToDateLine'))]);
    }
    return Wrap(spacing:12,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
      Text(r.build==null?S.t('version.available',{'version':r.version}):S.t('version.availableBuild',{'version':r.version,'build':r.build}),
        style:TextStyle(color:t.colorScheme.primary,fontWeight:FontWeight.w600)),
      FilledButton.icon(onPressed:()=>unawaited(openStore(r)),icon:const Icon(Icons.system_update),label:Text(S.t('version.update'))),
    ]);
  });
}

/// Application identifier on Google Play (AGENTS.md).
const androidApplicationId='org.sarcade.sarcade_app';
