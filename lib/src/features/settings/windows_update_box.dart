/// « Mise à jour » box at the top of Paramètres › À propos, Windows only
/// (card « Windows : menu Mise à jour », lot 25): installed version, last
/// published, state, « Mettre à jour » and « Télécharger ».
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/version.dart';
import '../../l10n/strings.dart';
import 'windows_update.dart';

class WindowsUpdateBox extends StatelessWidget {
  final WindowsUpdates? updates;
  const WindowsUpdateBox({super.key,this.updates});

  static bool get shown=>WindowsUpdates.instance.supported;

  WindowsUpdates get _u=>updates??WindowsUpdates.instance;

  Future<void> _install(BuildContext context) async {
    final u=_u;
    final g=u.currentGuard;
    if(g.blocks){
      final ok=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
        title:Text(S.t('update.win.confirmTitle')),
        content:Text(S.t(g.sos?'update.win.confirmSos':'update.win.confirmMission')),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(context,false),child:Text(S.t('common.cancel'))),
          FilledButton(key:const ValueKey('update-confirm'),onPressed:()=>Navigator.pop(context,true),child:Text(S.t('update.win.install'))),
        ],
      ));
      if(ok!=true)return;
    }
    await u.install();
  }

  Future<void> _download(BuildContext context) async {
    final messenger=ScaffoldMessenger.of(context);
    bool opened;
    try{
      opened=await launchUrl(Uri.parse(_u.downloadUrl),mode:LaunchMode.externalApplication);
    }catch(_){
      opened=false;
    }
    if(!opened)messenger.showSnackBar(SnackBar(content:Text(S.t('about.linkFailed'))));
  }

  static String _stateKey(WindowsUpdateState s)=>switch(s){
    WindowsUpdateState.idle||WindowsUpdateState.checking=>'update.win.checking',
    WindowsUpdateState.upToDate=>'update.win.upToDate',
    WindowsUpdateState.available=>'update.win.available',
    WindowsUpdateState.unknown=>'update.win.unknown',
    WindowsUpdateState.downloading=>'update.win.downloading',
    WindowsUpdateState.verifying=>'update.win.verifying',
    WindowsUpdateState.installing=>'update.win.installing',
    WindowsUpdateState.failed=>'update.win.failed',
  };

  @override
  Widget build(BuildContext context)=>ListenableBuilder(listenable:_u,builder:(context,_){
    final u=_u, t=Theme.of(context), r=u.latest;
    final available=u.available;
    final state=u.state==WindowsUpdateState.failed&&u.failure!=null?u.failure!:_stateKey(u.state);
    final color=switch(u.state){
      WindowsUpdateState.upToDate=>Colors.green.shade700,
      WindowsUpdateState.available=>t.colorScheme.primary,
      WindowsUpdateState.failed=>t.colorScheme.error,
      _=>t.colorScheme.onSurfaceVariant,
    };
    final icon=switch(u.state){
      WindowsUpdateState.upToDate=>Icons.check_circle,
      WindowsUpdateState.available=>Icons.new_releases_outlined,
      WindowsUpdateState.failed=>Icons.error_outline,
      WindowsUpdateState.unknown=>Icons.cloud_off_outlined,
      _=>Icons.hourglass_empty,
    };
    final installed=appBuild.isEmpty?appVersionFull:'$appVersionFull · $appBuild';
    return Card(key:const ValueKey('windows-update-box'),margin:EdgeInsets.zero,
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12),side:BorderSide(color:available?t.colorScheme.primary:t.colorScheme.outlineVariant)),
      child:Padding(padding:const EdgeInsets.fromLTRB(16,8,8,16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          Icon(Icons.system_update_alt,color:t.colorScheme.primary),
          const SizedBox(width:8),
          Expanded(child:Text(S.t('update.win.title'),style:t.textTheme.titleMedium)),
          IconButton(key:const ValueKey('update-check'),tooltip:S.t('update.win.check'),icon:const Icon(Icons.refresh),
            onPressed:u.busy?null:()=>unawaited(u.check())),
        ]),
        SelectableText(S.t('update.win.installed',{'version':installed})),
        if(r!=null)SelectableText(S.t('update.win.latest',{
          'version':r.build==null?r.version:'${r.version} · ${r.build}',
          'source':S.t(r.source==WindowsUpdateSource.server?'update.win.source.server':'update.win.source.github')})),
        const SizedBox(height:8),
        Row(children:[
          Icon(icon,size:18,color:color),
          const SizedBox(width:6),
          Expanded(child:Text(S.t(state),style:TextStyle(color:color,fontWeight:available?FontWeight.w600:null))),
        ]),
        if(u.busy)const Padding(padding:EdgeInsets.only(top:8,right:8),child:LinearProgressIndicator()),
        if(!u.installed)Padding(padding:const EdgeInsets.only(top:6),child:Text(S.t('update.win.portable'),style:t.textTheme.bodySmall)),
        if(available||!u.installed)Padding(padding:const EdgeInsets.only(top:12),child:Wrap(spacing:8,runSpacing:8,children:[
          if(available&&u.installed)FilledButton.icon(key:const ValueKey('update-install'),onPressed:u.busy?null:()=>unawaited(_install(context)),
            icon:const Icon(Icons.system_update),label:Text(S.t('update.win.install'))),
          OutlinedButton.icon(key:const ValueKey('update-download'),onPressed:()=>unawaited(_download(context)),
            icon:const Icon(Icons.download),label:Text(S.t('update.win.download'))),
        ])),
      ])),
    );
  });
}
