/// « Module MeshCore » in Paramètres › Liaisons (lot D, card « MeshCore
/// comme transport », 1 Nov 2026; replaces the trial card of the same
/// day): search once, choose; the module is remembered and joined again by
/// itself (see [MeshCoreLink]).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../l10n/strings.dart';
import 'meshcore_link.dart';
import 'meshcore_protocol.dart';

/// Text of the state line ('mesh.state.connected'…).
String meshCoreStateText(MeshCoreState s)=>S.t('mesh.state.${s.name}');

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
        if(problem!=null)Padding(padding:const EdgeInsets.only(top:4),child:Text(problem,key:const ValueKey('meshcore-problem'),style:small?.copyWith(color:s.error))),
        const SizedBox(height:8),
        Wrap(spacing:8,runSpacing:8,children:[
          OutlinedButton.icon(onPressed:link.state==MeshCoreState.connected?()=>unawaited(link.refresh()):null,icon:const Icon(Icons.refresh),label:Text(S.t('mesh.refresh'))),
          OutlinedButton.icon(key:const ValueKey('meshcore-forget'),onPressed:()=>unawaited(link.forget()),icon:const Icon(Icons.bluetooth_disabled),label:Text(S.t('mesh.forget'))),
          if(busy)const Padding(padding:EdgeInsets.all(8),child:SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2))),
        ]),
      ]else...[
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
