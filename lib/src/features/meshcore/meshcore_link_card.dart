/// « Module MeshCore » in Paramètres › Liaisons (lot D, card « MeshCore
/// comme transport », 1 Nov 2026; replaces the trial card of the same
/// day): search once, choose; the module is remembered and joined again by
/// itself (see [MeshCoreLink]).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../l10n/strings.dart';
import 'meshcore_link.dart';
import 'meshcore_protocol.dart';

/// Text of the state line ('mesh.state.connected'…).
String meshCoreStateText(MeshCoreState s)=>S.t('mesh.state.${s.name}');

/// Web app (lot 17, card « Application web : se connecter à un module
/// MeshCore », choices validated on 1 Nov 2026, 12 h 04): « Connecter un
/// module MeshCore » opens the browser's window; without Web Bluetooth
/// (Safari, Firefox) a clear message instead of the button.
class MeshCoreWebConnect extends StatelessWidget {
  final bool bluetooth;
  final VoidCallback? onConnect;
  const MeshCoreWebConnect({super.key,required this.bluetooth,this.onConnect});
  @override Widget build(BuildContext context){
    final small=Theme.of(context).textTheme.bodySmall;
    if(!bluetooth){
      return Row(key:const ValueKey('meshcore-web-unsupported'),children:[
        Icon(Icons.info_outline,color:Theme.of(context).colorScheme.error),const SizedBox(width:8),
        Expanded(child:Text(S.t('mesh.web.unsupported'),style:const TextStyle(fontWeight:FontWeight.w600))),
      ]);
    }
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      FilledButton.icon(key:const ValueKey('meshcore-web-connect'),onPressed:onConnect,icon:const Icon(Icons.bluetooth_searching),label:Text(S.t('mesh.web.connect'))),
      Padding(padding:const EdgeInsets.only(top:6),child:Text(S.t('mesh.web.help'),style:small)),
    ]);
  }
}

/// Bar « Reconnecter le module » (web): shown while the browser waits for a
/// click to join the remembered module again.
class MeshCoreReconnectBar extends StatelessWidget {
  final VoidCallback onReconnect;
  const MeshCoreReconnectBar({super.key,required this.onReconnect});
  @override Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    return Material(key:const ValueKey('meshcore-reconnect-bar'),color:s.tertiaryContainer,child:SafeArea(bottom:false,child:Padding(padding:const EdgeInsets.fromLTRB(14,6,8,6),child:Row(children:[
      Icon(Icons.bluetooth_disabled,color:s.onTertiaryContainer),const SizedBox(width:10),
      Expanded(child:Text(S.t('mesh.web.reconnectHelp'),style:TextStyle(color:s.onTertiaryContainer))),
      FilledButton(key:const ValueKey('meshcore-reconnect'),onPressed:onReconnect,child:Text(S.t('mesh.web.reconnect'))),
    ]))));
  }
}

/// The bar above the map and in Outils › MeshCore, only when needed.
class MeshCoreReconnectBanner extends StatelessWidget {
  const MeshCoreReconnectBanner({super.key});
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:MeshCoreLink.instance,builder:(context,_){
    final link=MeshCoreLink.instance;
    if(link.state!=MeshCoreState.waitingClick)return const SizedBox.shrink();
    return MeshCoreReconnectBar(onReconnect:()=>unawaited(link.chooseInBrowser()));
  });
}

class MeshCoreLinkCard extends StatefulWidget {
  const MeshCoreLinkCard({super.key});
  @override State<MeshCoreLinkCard> createState()=>_MeshCoreLinkCardState();
}

class _MeshCoreLinkCardState extends State<MeshCoreLinkCard> {
  final link=MeshCoreLink.instance;
  final _found=<String,BleDevice>{};
  StreamSubscription<BleDevice>? _scanSub;
  bool _scanning=false;
  String? _note;

  @override void initState(){super.initState();link.addListener(_changed);}
  void _changed(){if(mounted)setState((){});}

  Future<void> _scan() async {
    setState((){_found.clear();_scanning=true;_note=S.t('mesh.searching');});
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
      await UniversalBle.startScan(scanFilter:ScanFilter(withServices:[meshCoreService]));
      await Future<void>.delayed(const Duration(seconds:10));
      await _stopScan();
      if(mounted)setState(()=>_note=_found.isEmpty?S.t('mesh.noneFound'):null);
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
    final busy=link.trying;
    final problem=meshCoreProblem(state:link.state,trying:link.trying,error:link.error,retryIn:link.retryIn);
    return Card(key:const ValueKey('meshcore-link'),margin:const EdgeInsets.only(top:12),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(children:[
        Icon(Icons.settings_input_antenna,color:s.primary),const SizedBox(width:10),
        Expanded(child:Text(S.t('mesh.title'),style:Theme.of(context).textTheme.titleSmall)),
      ]),
      Padding(padding:const EdgeInsets.only(top:4,bottom:8),child:Text(S.t('mesh.help'),style:small)),
      if(link.remembered)...[
        Text('${link.deviceName??link.deviceId} · ${meshCoreStateText(link.state)}',key:const ValueKey('meshcore-state')),
        if(link.state==MeshCoreState.waitingClick)Padding(padding:const EdgeInsets.only(top:8),child:FilledButton.icon(key:const ValueKey('meshcore-web-reconnect'),
          onPressed:()=>unawaited(link.chooseInBrowser()),icon:const Icon(Icons.bluetooth_searching),label:Text(S.t('mesh.web.reconnect')))),
        if(problem!=null)Padding(padding:const EdgeInsets.only(top:4),child:Text(problem,key:const ValueKey('meshcore-problem'),style:small?.copyWith(color:s.error))),
        const SizedBox(height:8),
        Wrap(spacing:8,runSpacing:8,children:[
          OutlinedButton.icon(onPressed:link.state==MeshCoreState.connected?()=>unawaited(link.refresh()):null,icon:const Icon(Icons.refresh),label:Text(S.t('mesh.refresh'))),
          OutlinedButton.icon(key:const ValueKey('meshcore-forget'),onPressed:()=>unawaited(link.forget()),icon:const Icon(Icons.bluetooth_disabled),label:Text(S.t('mesh.forget'))),
          if(busy)const Padding(padding:EdgeInsets.all(8),child:SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2))),
        ]),
      ]else if(kIsWeb)
        MeshCoreWebConnect(bluetooth:link.browserReady,onConnect:()=>unawaited(link.chooseInBrowser()))
      else...[
        Wrap(spacing:8,runSpacing:8,children:[
          FilledButton.icon(key:const ValueKey('meshcore-scan'),onPressed:_scanning?null:_scan,icon:const Icon(Icons.bluetooth_searching),label:Text(S.t('mesh.search'))),
          if(_scanning)const Padding(padding:EdgeInsets.all(8),child:SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2))),
        ]),
        if(_note!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(_note!)),
        for(final d in _found.values)ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.memory),
          title:Text(d.name??d.deviceId),subtitle:Text(['RSSI ${d.rssi??'?'} dBm',d.deviceId].join(' · '),style:small),
          trailing:TextButton(onPressed:()=>_choose(d),child:Text(S.t('mesh.connect')))),
      ],
      if(link.journal.isNotEmpty)Align(alignment:Alignment.centerLeft,child:TextButton.icon(onPressed:() async {
        final m=ScaffoldMessenger.of(context);
        await Clipboard.setData(ClipboardData(text:['SARCADE · module MeshCore',...link.journal].join('\n')));
        m.showSnackBar(SnackBar(content:Text(S.t('common.copied'))));
      },icon:const Icon(Icons.copy_all),label:Text(S.t('mesh.copyJournal')))),
    ])));
  }
}
