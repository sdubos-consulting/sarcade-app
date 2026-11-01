/// « Module MeshCore (essai) » in Paramètres › Diagnostic (card « Essai :
/// SARCADE parle en Bluetooth à un module MeshCore », 1 Nov 2026): search,
/// connect, read what the module says about itself. Read only, nothing is
/// sent on the LoRa network nor stored on the server. Core (no radio
/// licence needed, rule of 1 Nov 2026).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../l10n/strings.dart';
import 'meshcore_protocol.dart';

class MeshCoreTrialCard extends StatefulWidget {
  const MeshCoreTrialCard({super.key});
  @override State<MeshCoreTrialCard> createState()=>_MeshCoreTrialCardState();
}

class _MeshCoreTrialCardState extends State<MeshCoreTrialCard> {
  final _found=<String,BleDevice>{};
  final _journal=<String>[];
  StreamSubscription<BleDevice>? _scanSub;
  StreamSubscription<Uint8List>? _valueSub;
  String? _connected, _state, _error;
  bool _scanning=false, _busy=false;
  int? _linkRssi;
  MeshCoreInfo _info=MeshCoreInfo();

  void _log(String line){
    final t=DateTime.now(); String two(int v)=>v.toString().padLeft(2,'0');
    _journal.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} $line');
    if(_journal.length>200)_journal.removeAt(0);
  }

  Future<void> _scan() async {
    setState((){_error=null;_found.clear();_scanning=true;_state=S.t('mesh.searching');});
    try{
      try{await UniversalBle.requestPermissions();}catch(_){/* not needed on every platform */}
      final av=await UniversalBle.getBluetoothAvailabilityState();
      if(av!=AvailabilityState.poweredOn&&av!=AvailabilityState.unknown){
        _log('Bluetooth : $av');
        setState((){_scanning=false;_state=null;_error=S.t('mesh.bluetoothOff');});
        return;
      }
      await _scanSub?.cancel();
      _scanSub=UniversalBle.scanStream.listen((d){
        if(!mounted)return;
        final fresh=!_found.containsKey(d.deviceId);
        setState(()=>_found[d.deviceId]=d);
        if(fresh)_log('trouvé ${d.name??'?'} (${d.deviceId}) RSSI ${d.rssi??'?'}');
      });
      _log('recherche du service $meshCoreService');
      await UniversalBle.startScan(scanFilter:ScanFilter(withServices:[meshCoreService]));
      await Future<void>.delayed(const Duration(seconds:10));
      await _stopScan();
      if(mounted)setState(()=>_state=_found.isEmpty?S.t('mesh.noneFound'):null);
    }catch(e){
      _log('erreur de recherche : $e');
      if(mounted)setState((){_scanning=false;_state=null;_error='${S.t('mesh.failed')} ($e)';});
    }
  }

  Future<void> _stopScan() async {
    try{await UniversalBle.stopScan();}catch(_){}
    await _scanSub?.cancel(); _scanSub=null;
    if(mounted)setState(()=>_scanning=false);
  }

  Future<void> _send(String id,Uint8List frame,String what) async {
    _log('→ $what ${meshCoreHex(frame)}');
    await UniversalBle.write(id,meshCoreService,meshCoreRx,frame);
  }

  Future<void> _connect(BleDevice d) async {
    await _stopScan();
    setState((){_busy=true;_error=null;_info=MeshCoreInfo();_state=S.t('mesh.connecting');});
    final id=d.deviceId;
    try{
      _log('connexion à ${d.name??id}');
      await UniversalBle.connect(id);
      final services=await UniversalBle.discoverServices(id);
      _log('services : ${services.map((s)=>s.uuid).join(', ')}');
      if(!services.any((s)=>s.uuid.toLowerCase()==meshCoreService)){
        throw StateError(S.t('mesh.notCompanion'));
      }
      try{final mtu=await UniversalBle.requestMtu(id,512);_log('MTU $mtu');}catch(e){_log('MTU non négociée ($e)');}
      await _valueSub?.cancel();
      _valueSub=UniversalBle.characteristicValueStream(id,meshCoreTx).listen((v){
        final kind=readMeshCoreFrame(v,_info);
        _log('← $kind ${meshCoreHex(v)}');
        if(mounted)setState((){});
      });
      await UniversalBle.subscribeNotifications(id,meshCoreService,meshCoreTx);
      setState(()=>_connected=id);
      await _send(id,deviceQuery(),'DEVICE_QUERY');
      await Future<void>.delayed(const Duration(milliseconds:400));
      await _send(id,appStart(),'APP_START');
      await Future<void>.delayed(const Duration(milliseconds:400));
      await _send(id,batteryQuery(),'BATTERY');
      await Future<void>.delayed(const Duration(seconds:2));
      try{_linkRssi=await UniversalBle.readRssi(id);}catch(_){}
      if(mounted)setState(()=>_state=_info.empty?S.t('mesh.noAnswer'):S.t('mesh.talking'));
    }catch(e){
      _log('échec : $e');
      if(mounted)setState((){_state=null;_error='${S.t('mesh.failed')} ($e)';});
    }finally{
      if(mounted)setState(()=>_busy=false);
    }
  }

  Future<void> _refresh() async {
    final id=_connected; if(id==null)return;
    setState(()=>_busy=true);
    try{
      await _send(id,batteryQuery(),'BATTERY');
      await Future<void>.delayed(const Duration(seconds:1));
      try{_linkRssi=await UniversalBle.readRssi(id);}catch(_){}
    }catch(e){_log('échec : $e');}
    if(mounted)setState(()=>_busy=false);
  }

  Future<void> _disconnect() async {
    final id=_connected; if(id==null)return;
    await _valueSub?.cancel(); _valueSub=null;
    try{await UniversalBle.disconnect(id);}catch(_){}
    _log('déconnecté');
    if(mounted)setState((){_connected=null;_state=null;_linkRssi=null;});
  }

  @override void dispose(){
    _scanSub?.cancel(); _valueSub?.cancel();
    final id=_connected; if(id!=null){UniversalBle.disconnect(id).catchError((_){});}
    if(_scanning){UniversalBle.stopScan().catchError((_){});}
    super.dispose();
  }

  @override Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme, small=Theme.of(context).textTheme.bodySmall;
    final lines=meshCoreLines(_info);
    return Card(key:const ValueKey('meshcore-trial'),margin:const EdgeInsets.only(top:12),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(children:[
        Icon(Icons.settings_input_antenna,color:s.primary),const SizedBox(width:10),
        Expanded(child:Text(S.t('mesh.title'),style:Theme.of(context).textTheme.titleSmall)),
      ]),
      Padding(padding:const EdgeInsets.only(top:4,bottom:8),child:Text(S.t('mesh.help'),style:small)),
      Wrap(spacing:8,runSpacing:8,children:[
        if(_connected==null)FilledButton.icon(key:const ValueKey('meshcore-scan'),onPressed:_scanning||_busy?null:_scan,icon:const Icon(Icons.bluetooth_searching),label:Text(S.t('mesh.search'))),
        if(_connected!=null)OutlinedButton.icon(onPressed:_busy?null:_refresh,icon:const Icon(Icons.refresh),label:Text(S.t('mesh.refresh'))),
        if(_connected!=null)OutlinedButton.icon(onPressed:_busy?null:_disconnect,icon:const Icon(Icons.bluetooth_disabled),label:Text(S.t('mesh.disconnect'))),
        if(_journal.isNotEmpty)TextButton.icon(onPressed:() async {
          final m=ScaffoldMessenger.of(context);
          await Clipboard.setData(ClipboardData(text:['SARCADE · module MeshCore (essai)',..._journal].join('\n')));
          m.showSnackBar(SnackBar(content:Text(S.t('common.copied'))));
        },icon:const Icon(Icons.copy_all),label:Text(S.t('mesh.copyJournal'))),
        if(_scanning||_busy)const Padding(padding:EdgeInsets.all(8),child:SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2))),
      ]),
      if(_state!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(_state!,key:const ValueKey('meshcore-state'))),
      if(_error!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(_error!,style:TextStyle(color:s.error))),
      if(_connected==null)for(final d in _found.values)ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.memory),
        title:Text(d.name??d.deviceId),subtitle:Text(['RSSI ${d.rssi??'?'} dBm',d.deviceId].join(' · '),style:small),
        trailing:TextButton(onPressed:_busy?null:()=>_connect(d),child:Text(S.t('mesh.connect')))),
      if(_connected!=null)...[
        const SizedBox(height:6),
        for(final (k,v) in lines)Padding(padding:const EdgeInsets.symmetric(vertical:2),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          SizedBox(width:120,child:Text(S.t('mesh.field.$k'),style:small)),Expanded(child:Text(v))])),
        if(_linkRssi!=null)Padding(padding:const EdgeInsets.symmetric(vertical:2),child:Row(children:[
          SizedBox(width:120,child:Text(S.t('mesh.field.link'),style:small)),Text('$_linkRssi dBm')])),
      ],
    ])));
  }
}
