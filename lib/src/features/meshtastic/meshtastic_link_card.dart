// SPDX-License-Identifier: MPL-2.0
// © SDUBOS Consulting et contributeurs SARCADE

/// « Module Meshtastic » (lot 28, card « Module Meshtastic, sur le modèle
/// de MeshCore », point 1): search once, choose; the module is remembered
/// and joined again by itself; « Déconnecter », « Oublier ce module »,
/// journal. Web: « Connecter un module Meshtastic » (Web Bluetooth, Chrome
/// and Edge) and the bar « Reconnecter le module » with « Plus tard »
/// (point 4), as for MeshCore.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../l10n/strings.dart';
import '../lora/lora_link.dart';
import 'meshtastic_link.dart';
import 'meshtastic_protocol.dart';

/// « Plus tard » pressed: hidden until SARCADE is opened again (memory
/// only, never saved).
final ValueNotifier<bool> meshtasticBannerLater=ValueNotifier(false);

/// Number of Meshtastic screens open (Outils › Meshtastic): one bar only.
final ValueNotifier<int> meshtasticScreensOpen=ValueNotifier(0);

/// Web app without a module yet: the browser's window, or a clear message
/// without Web Bluetooth (Safari, Firefox).
class MeshtasticWebConnect extends StatelessWidget {
  final bool bluetooth;
  final VoidCallback? onConnect;
  const MeshtasticWebConnect({super.key,required this.bluetooth,this.onConnect});
  @override Widget build(BuildContext context){
    final small=Theme.of(context).textTheme.bodySmall;
    if(!bluetooth){
      return Row(key:const ValueKey('meshtastic-web-unsupported'),children:[
        Icon(Icons.info_outline,color:Theme.of(context).colorScheme.error),const SizedBox(width:8),
        Expanded(child:Text(S.t('mesh.web.unsupported'),style:const TextStyle(fontWeight:FontWeight.w600))),
      ]);
    }
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      FilledButton.icon(key:const ValueKey('meshtastic-web-connect'),onPressed:onConnect,icon:const Icon(Icons.bluetooth_searching),label:Text(S.t('meshtastic.web.connect'))),
      Padding(padding:const EdgeInsets.only(top:6),child:Text(S.t('meshtastic.web.help'),style:small)),
    ]);
  }
}

/// Bar « Reconnecter le module » (web), with « Plus tard ».
class MeshtasticReconnectBar extends StatelessWidget {
  final VoidCallback onReconnect;
  final VoidCallback? onLater;
  const MeshtasticReconnectBar({super.key,required this.onReconnect,this.onLater});
  @override Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    return Material(key:const ValueKey('meshtastic-reconnect-bar'),color:s.tertiaryContainer,child:SafeArea(bottom:false,child:Padding(padding:const EdgeInsets.fromLTRB(14,6,8,6),child:Row(children:[
      Icon(Icons.bluetooth_disabled,color:s.onTertiaryContainer),const SizedBox(width:10),
      Expanded(child:Text(S.t('meshtastic.web.reconnectHelp'),style:TextStyle(color:s.onTertiaryContainer))),
      if(onLater!=null)TextButton(key:const ValueKey('meshtastic-later'),onPressed:onLater,
        style:TextButton.styleFrom(foregroundColor:s.onTertiaryContainer),child:Text(S.t('meshcore.banner.later'))),
      FilledButton(key:const ValueKey('meshtastic-reconnect'),onPressed:onReconnect,child:Text(S.t('mesh.web.reconnect'))),
    ]))));
  }
}

/// The bar above the map and in Outils › Meshtastic, only when needed; one
/// bar only while the Meshtastic screen is open.
class MeshtasticReconnectBanner extends StatelessWidget {
  final bool inScreen;
  const MeshtasticReconnectBanner({super.key,this.inScreen=false});
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:Listenable.merge([MeshtasticLink.instance,meshtasticBannerLater,meshtasticScreensOpen]),builder:(context,_){
    final link=MeshtasticLink.instance;
    if(!loraBannerShown(state:link.state,later:meshtasticBannerLater.value,inScreen:inScreen,screensOpen:meshtasticScreensOpen.value))return const SizedBox.shrink();
    return MeshtasticReconnectBar(onReconnect:()=>unawaited(link.reconnectInBrowser()),onLater:()=>meshtasticBannerLater.value=true);
  });
}

/// « Déconnecter » / « Se connecter »: the module stays remembered.
class MeshtasticConnectButton extends StatelessWidget {
  const MeshtasticConnectButton({super.key});
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:MeshtasticLink.instance,builder:(context,_){
    final link=MeshtasticLink.instance;
    if(!link.remembered||link.state==LoraLinkState.waitingClick||link.state==LoraLinkState.unavailable)return const SizedBox.shrink();
    if(link.state==LoraLinkState.disconnected){
      return Column(key:const ValueKey('meshtastic-off'),mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(S.t('mesh.off.help'),style:Theme.of(context).textTheme.bodySmall),
        const SizedBox(height:6),
        FilledButton.icon(key:const ValueKey('meshtastic-connect'),onPressed:()=>unawaited(link.connect()),
          icon:const Icon(Icons.bluetooth_connected),label:Text(S.t('mesh.connect'))),
      ]);
    }
    return OutlinedButton.icon(key:const ValueKey('meshtastic-disconnect'),onPressed:()=>unawaited(link.disconnect()),
      icon:const Icon(Icons.link_off),label:Text(S.t('mesh.disconnect')));
  });
}

class MeshtasticLinkCard extends StatefulWidget {
  const MeshtasticLinkCard({super.key});
  @override State<MeshtasticLinkCard> createState()=>_MeshtasticLinkCardState();
}

class _MeshtasticLinkCardState extends State<MeshtasticLinkCard> {
  final link=MeshtasticLink.instance;
  final _found=<String,BleDevice>{};
  StreamSubscription<BleDevice>? _scanSub;
  bool _scanning=false;
  String? _note;

  @override void initState(){super.initState();link.addListener(_changed);}
  void _changed(){if(mounted)setState((){});}

  Future<void> _scan() async {
    setState((){_found.clear();_scanning=true;_note=S.t('meshtastic.searching');});
    try{
      try{await UniversalBle.requestPermissions();}catch(_){/* not needed on every platform */}
      final av=await UniversalBle.getBluetoothAvailabilityState();
      if(av!=AvailabilityState.poweredOn&&av!=AvailabilityState.unknown){
        link.log('Bluetooth : $av');
        setState((){_scanning=false;_note=S.t('mesh.bluetoothOff');});
        return;
      }
      await _scanSub?.cancel();
      _scanSub=UniversalBle.scanStream.listen((d){if(mounted)setState(()=>_found[d.deviceId]=d);});
      await UniversalBle.startScan(scanFilter:ScanFilter(withServices:[meshtasticService]));
      await Future<void>.delayed(const Duration(seconds:10));
      await _stopScan();
      if(mounted)setState(()=>_note=_found.isEmpty?S.t('meshtastic.noneFound'):null);
    }catch(e){
      link.log('erreur de recherche : $e');
      if(mounted)setState((){_scanning=false;_note='${S.t('mesh.failed')} ($e)';});
    }
  }

  Future<void> _stopScan() async {
    try{await UniversalBle.stopScan();}catch(_){}
    await _scanSub?.cancel(); _scanSub=null;
    if(mounted)setState(()=>_scanning=false);
  }

  Future<void> _choose(BleDevice d) async {
    await _stopScan();
    setState((){_found.clear();_note=null;});
    await link.choose(d);
  }

  @override void dispose(){
    link.removeListener(_changed);
    _scanSub?.cancel();
    if(_scanning){UniversalBle.stopScan().catchError((_){});}
    super.dispose();
  }

  @override Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme, small=Theme.of(context).textTheme.bodySmall;
    final problem=loraProblem(state:link.state,trying:link.trying,error:link.error,retryIn:link.retryIn);
    return Card(key:const ValueKey('meshtastic-link'),margin:const EdgeInsets.only(top:12),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(children:[
        Icon(Icons.wifi_tethering,color:s.primary),const SizedBox(width:10),
        Expanded(child:Text(S.t('meshtastic.title'),style:Theme.of(context).textTheme.titleSmall)),
      ]),
      Padding(padding:const EdgeInsets.only(top:4,bottom:8),child:Text(S.t('meshtastic.help'),style:small)),
      if(link.remembered)...[
        Text('${link.deviceName??link.deviceId} · ${loraStateText(link.state)}',key:const ValueKey('meshtastic-state')),
        if(link.state==LoraLinkState.waitingClick||link.state==LoraLinkState.unavailable)Padding(padding:const EdgeInsets.only(top:8),child:FilledButton.icon(key:const ValueKey('meshtastic-web-reconnect'),
          onPressed:()=>unawaited(link.reconnectInBrowser()),icon:const Icon(Icons.bluetooth_searching),label:Text(S.t('mesh.web.reconnect')))),
        if(problem!=null)Padding(padding:const EdgeInsets.only(top:4),child:Text(problem,key:const ValueKey('meshtastic-problem'),style:small?.copyWith(color:s.error))),
        const SizedBox(height:8),
        Wrap(spacing:8,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
          const MeshtasticConnectButton(),
          OutlinedButton.icon(onPressed:link.connected?()=>unawaited(link.refresh()):null,icon:const Icon(Icons.refresh),label:Text(S.t('mesh.refresh'))),
          OutlinedButton.icon(key:const ValueKey('meshtastic-forget'),onPressed:()=>unawaited(link.forget()),icon:const Icon(Icons.bluetooth_disabled),label:Text(S.t('mesh.forget'))),
          if(link.trying)const Padding(padding:EdgeInsets.all(8),child:SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2))),
        ]),
      ]else if(kIsWeb)
        MeshtasticWebConnect(bluetooth:link.browserReady,onConnect:()=>unawaited(link.chooseInBrowser()))
      else...[
        Wrap(spacing:8,runSpacing:8,children:[
          FilledButton.icon(key:const ValueKey('meshtastic-scan'),onPressed:_scanning?null:_scan,icon:const Icon(Icons.bluetooth_searching),label:Text(S.t('mesh.search'))),
          if(_scanning)const Padding(padding:EdgeInsets.all(8),child:SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2))),
        ]),
        if(_note!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(_note!)),
        for(final d in _found.values)ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.memory),
          title:Text(d.name??d.deviceId),subtitle:Text(['RSSI ${d.rssi??'?'} dBm',d.deviceId].join(' · '),style:small),
          trailing:TextButton(onPressed:()=>_choose(d),child:Text(S.t('mesh.connect')))),
      ],
      if(link.journal.isNotEmpty)Align(alignment:Alignment.centerLeft,child:TextButton.icon(onPressed:() async {
        final m=ScaffoldMessenger.of(context);
        await Clipboard.setData(ClipboardData(text:['SARCADE · module Meshtastic',...link.journal].join('\n')));
        m.showSnackBar(SnackBar(content:Text(S.t('common.copied'))));
      },icon:const Icon(Icons.copy_all),label:Text(S.t('mesh.copyJournal')))),
    ])));
  }
}
