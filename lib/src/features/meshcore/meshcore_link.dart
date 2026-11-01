/// Persistent Bluetooth link to a MeshCore companion module (lot D, card
/// « MeshCore comme transport », 1 Nov 2026). Core: no radio licence needed
/// (rule of 1 Nov 2026).
///
/// The module chosen once in Paramètres › Liaisons is remembered and joined
/// again at start and after a drop. The state shows in the link pill of the
/// map; Outils › MeshCore lists the nodes and the metrics. Read only for
/// now: SARCADE messages over LoRa come with a later step.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../offline/local_store.dart';
import 'meshcore_protocol.dart';

enum MeshCoreState { none, connecting, connected, reconnecting, failed }

/// Preference keys of the remembered module.
const meshCoreDeviceKey='meshcore_device', meshCoreNameKey='meshcore_name';

/// Colour family of the pill: 'off' (no module), 'ok', 'wait', 'bad'.
String meshCorePillTone(MeshCoreState s)=>switch(s){
  MeshCoreState.none=>'off', MeshCoreState.connected=>'ok',
  MeshCoreState.connecting||MeshCoreState.reconnecting=>'wait', MeshCoreState.failed=>'bad'};

/// Delay before the next attempt to join the module again: 5 s, 15 s,
/// 30 s, then every minute.
Duration meshCoreRetryDelay(int attempt)=>Duration(seconds:const [5,15,30,60][attempt.clamp(0,3)]);

/// Nodes sorted for the list: heard most recently first, unnamed last.
List<MeshCoreContact> sortedContacts(Iterable<MeshCoreContact> all)=>all.toList()
  ..sort((a,b){
    final t=(b.lastAdvert?.millisecondsSinceEpoch??0).compareTo(a.lastAdvert?.millisecondsSinceEpoch??0);
    return t!=0?t:a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

class MeshCoreLink extends ChangeNotifier {
  MeshCoreLink._();
  static final MeshCoreLink instance=MeshCoreLink._();

  LocalStore? _store;
  MeshCoreState state=MeshCoreState.none;
  String? deviceId, deviceName, error;
  MeshCoreInfo info=MeshCoreInfo();
  final Map<String,MeshCoreContact> _contacts={};
  int? linkRssi;
  int framesIn=0, framesOut=0;
  DateTime? lastFrameAt, connectedSince, contactsAt;
  final List<String> journal=[];

  StreamSubscription<Uint8List>? _valueSub;
  StreamSubscription<bool>? _connSub;
  Timer? _retry, _poll;
  int _attempt=0;
  bool _stopping=false;
  Map<String,MeshCoreContact> _incoming={};

  List<MeshCoreContact> get contacts=>sortedContacts(_contacts.values);
  bool get remembered=>deviceId!=null;
  bool get supported=>!kIsWeb;

  void log(String line){
    final t=DateTime.now(); String two(int v)=>v.toString().padLeft(2,'0');
    journal.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} $line');
    if(journal.length>300)journal.removeAt(0);
  }

  void _set(MeshCoreState s,{String? err}){state=s;error=err;notifyListeners();}

  /// At start: joins the remembered module, if any.
  Future<void> restore(LocalStore store) async {
    _store=store;
    if(!supported||state!=MeshCoreState.none)return;
    deviceId=store.preference(meshCoreDeviceKey); deviceName=store.preference(meshCoreNameKey);
    if(deviceId!=null){notifyListeners();unawaited(_join());}
  }

  /// Chosen in Paramètres › Liaisons: remembered, then joined.
  Future<void> choose(BleDevice d,{LocalStore? store}) async {
    if(store!=null)_store=store;
    await _drop();
    deviceId=d.deviceId; deviceName=d.name;
    await _store?.setPreference(meshCoreDeviceKey,deviceId);
    await _store?.setPreference(meshCoreNameKey,deviceName);
    _attempt=0;
    await _join();
  }

  /// « Oublier ce module »: disconnected and no longer joined at start.
  Future<void> forget() async {
    await _drop();
    deviceId=null; deviceName=null; info=MeshCoreInfo(); _contacts.clear(); linkRssi=null;
    await _store?.setPreference(meshCoreDeviceKey,null);
    await _store?.setPreference(meshCoreNameKey,null);
    log('module oublié');
    _set(MeshCoreState.none);
  }

  Future<void> _join() async {
    final id=deviceId; if(id==null)return;
    _retry?.cancel();
    _set(_attempt==0?MeshCoreState.connecting:MeshCoreState.reconnecting);
    try{
      log('connexion à ${deviceName??id}');
      await UniversalBle.connect(id,timeout:const Duration(seconds:20));
      final services=await UniversalBle.discoverServices(id);
      if(!services.any((s)=>s.uuid.toLowerCase()==meshCoreService))throw StateError('not a companion module');
      try{await UniversalBle.requestMtu(id,512);}catch(_){/* default MTU kept */}
      await _valueSub?.cancel();
      _valueSub=UniversalBle.characteristicValueStream(id,meshCoreTx).listen(_onFrame);
      await UniversalBle.subscribeNotifications(id,meshCoreService,meshCoreTx);
      await _connSub?.cancel();
      _connSub=UniversalBle.connectionStream(id).listen((up){if(!up)_lost();});
      connectedSince=DateTime.now(); _attempt=0;
      _set(MeshCoreState.connected);
      await _send(deviceQuery(),'DEVICE_QUERY');
      await Future<void>.delayed(const Duration(milliseconds:300));
      await _send(appStart(),'APP_START');
      await Future<void>.delayed(const Duration(milliseconds:300));
      await refresh();
      _poll?.cancel();
      _poll=Timer.periodic(const Duration(minutes:1),(_)=>unawaited(refresh()));
    }catch(e){
      log('échec : $e');
      _schedule('$e');
    }
  }

  void _lost(){
    if(_stopping||state!=MeshCoreState.connected)return;
    log('liaison perdue');
    _poll?.cancel();
    _schedule(null);
  }

  void _schedule(String? err){
    if(deviceId==null)return;
    final wait=meshCoreRetryDelay(_attempt++);
    _set(_attempt>3?MeshCoreState.failed:MeshCoreState.reconnecting,err:err);
    _retry?.cancel();
    _retry=Timer(wait,()=>unawaited(_join()));
  }

  /// « Actualiser » and every minute: battery, Bluetooth signal, nodes.
  Future<void> refresh() async {
    final id=deviceId; if(id==null||state!=MeshCoreState.connected)return;
    try{
      await _send(batteryQuery(),'BATTERY');
      await Future<void>.delayed(const Duration(milliseconds:300));
      await _send(contactsQuery(),'GET_CONTACTS');
      try{linkRssi=await UniversalBle.readRssi(id);}catch(_){}
      notifyListeners();
    }catch(e){log('échec : $e');}
  }

  Future<void> _send(Uint8List frame,String what) async {
    final id=deviceId; if(id==null)return;
    log('→ $what ${meshCoreHex(frame)}');
    framesOut++;
    await UniversalBle.write(id,meshCoreService,meshCoreRx,frame);
  }

  void _onFrame(Uint8List v){
    framesIn++; lastFrameAt=DateTime.now();
    final kind=readMeshCoreFrame(v,info);
    switch(kind){
      case 'contactsStart': _incoming={};
      case 'contact':
        final c=readMeshCoreContact(v); if(c!=null)_incoming[c.key]=c;
      case 'contactsEnd':
        _contacts..clear()..addAll(_incoming); contactsAt=DateTime.now();
        log('${_contacts.length} nœud(s) connu(s)');
      case 'advert':
        unawaited(_send(contactsQuery(),'GET_CONTACTS'));
    }
    if(kind!='contact')log('← $kind ${meshCoreHex(v)}');
    notifyListeners();
  }

  Future<void> _drop() async {
    _stopping=true;
    _retry?.cancel(); _poll?.cancel();
    await _valueSub?.cancel(); _valueSub=null;
    await _connSub?.cancel(); _connSub=null;
    final id=deviceId;
    if(id!=null){try{await UniversalBle.disconnect(id);}catch(_){}}
    connectedSince=null;
    _stopping=false;
  }
}
