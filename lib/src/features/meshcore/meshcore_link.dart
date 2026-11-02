/// Persistent Bluetooth link to a MeshCore companion module (lot D, card
/// « MeshCore comme transport », 1 Nov 2026). Core: no radio licence needed
/// (rule of 1 Nov 2026).
///
/// The module chosen once in Paramètres › Liaisons is remembered and joined
/// again at start and after a drop. The state shows in the link pill of the
/// map; Outils › MeshCore lists the nodes and the metrics. Lot 17: the
/// nodes on the map and private messages with a companion (see
/// meshcore_chat.dart).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../platform/platform_services.dart' show webBluetoothAvailable;
import '../../offline/local_store.dart';
import '../../l10n/strings.dart';
import '../../services/notification_service.dart';
import 'meshcore_chat.dart';
import 'meshcore_protocol.dart';
import 'meshcore_remote.dart';

/// [waitingClick]: web app (lot 17), the browser lets join the module only
/// after a click in this tab (« Reconnecter le module »). [disconnected]
/// (lot 19): « Déconnecter » was pressed, the module stays remembered but is
/// not joined again until « Se connecter ».
enum MeshCoreState { none, connecting, connected, reconnecting, failed, waitingClick, disconnected }

/// Preference keys of the remembered module.
const meshCoreDeviceKey='meshcore_device', meshCoreNameKey='meshcore_name';
/// « Afficher les nœuds sur la carte » (lot 17), off by default.
const meshCoreMapKey='meshcore_map';
/// « Déconnecter » (lot 19): '1' while the module is left disconnected on
/// purpose, start of the application included.
const meshCoreOffKey='meshcore_off';

/// Colour family of the pill: 'off' (no module, or disconnected on purpose:
/// grey, lot 19), 'ok', 'wait', 'bad'.
String meshCorePillTone(MeshCoreState s)=>switch(s){
  MeshCoreState.none||MeshCoreState.disconnected=>'off', MeshCoreState.connected=>'ok',
  MeshCoreState.connecting||MeshCoreState.reconnecting||MeshCoreState.waitingClick=>'wait', MeshCoreState.failed=>'bad'};

/// Delay before the next attempt to join the module again: 5 s, 15 s,
/// 30 s, then every minute.
Duration meshCoreRetryDelay(int attempt)=>Duration(seconds:const [5,15,30,60][attempt.clamp(0,3)]);

/// Text shown when the module cannot be reached (card « MeshCore : message
/// d'erreur lisible », validated 1 Nov 2026, 8 h 15): the technical error
/// stays in the journal only.
String? meshCoreProblem({required MeshCoreState state,required bool trying,String? error,Duration? retryIn}){
  if(error==null||trying||state==MeshCoreState.connected||state==MeshCoreState.none||state==MeshCoreState.disconnected)return null;
  final wait=retryIn==null?'':' ${S.t('mesh.retryIn',{'s':retryIn.inSeconds})}';
  return '${S.t('mesh.unreachable')}$wait';
}

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
  /// A connection attempt is running (the spinner turns only then).
  bool trying=false;
  /// Delay before the next attempt after a failure.
  Duration? retryIn;
  /// « Nœuds MeshCore » layer of the map (lot 17), off by default.
  bool showOnMap=false;
  /// « Déconnecter » (lot 19): no automatic join until « Se connecter ».
  bool userOff=false;

  /// Tests: no Bluetooth, preferences in [testPrefs], [testJoins] counts
  /// the attempts to join the module.
  @visibleForTesting bool testMode=false;
  @visibleForTesting int testJoins=0;
  @visibleForTesting final Map<String,String?> testPrefs={};
  String? _pref(String key)=>testMode?testPrefs[key]:_store?.preference(key);
  Future<void> _setPref(String key,String? value) async {
    if(testMode){testPrefs[key]=value;return;}
    await _store?.setPreference(key,value);
  }

  StreamSubscription<Uint8List>? _valueSub;
  StreamSubscription<bool>? _connSub;
  Timer? _retry, _poll;
  int _attempt=0;
  bool _stopping=false;
  Map<String,MeshCoreContact> _incoming={};

  List<MeshCoreContact> get contacts=>sortedContacts(_contacts.values);
  bool get remembered=>deviceId!=null;
  /// Every platform, the web app included (lot 17, card « Application web :
  /// se connecter à un module MeshCore »): in a browser without Web
  /// Bluetooth, Outils › MeshCore says to use Chrome, Edge or the app.
  bool get supported=>true;
  /// Bluetooth usable here: always in the apps, Web Bluetooth in a browser.
  bool get browserReady=>!kIsWeb||webBluetoothAvailable();

  void log(String line){
    final t=DateTime.now(); String two(int v)=>v.toString().padLeft(2,'0');
    journal.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} $line');
    if(journal.length>300)journal.removeAt(0);
  }

  void _set(MeshCoreState s,{String? err}){state=s;error=err;notifyListeners();}

  /// At start: joins the remembered module, if any.
  Future<void> restore(LocalStore store) async {
    _store=store;
    _wire(store);
    _restore();
  }

  void _restore(){
    if(!supported||state!=MeshCoreState.none)return;
    deviceId=_pref(meshCoreDeviceKey); deviceName=_pref(meshCoreNameKey);
    if(deviceId==null)return;
    // Disconnected on purpose (lot 19): stays so at the next start.
    userOff=_pref(meshCoreOffKey)=='1';
    if(userOff){log('module déconnecté à la demande : pas de connexion au démarrage');_set(MeshCoreState.disconnected);return;}
    notifyListeners(); unawaited(_join());
  }

  /// Tests: [restore] without a store (see [testPrefs]).
  @visibleForTesting
  void restoreForTest()=>_restore();

  /// Tests: back to the state of a fresh start.
  @visibleForTesting
  void resetForTest(){
    _retry?.cancel(); _poll?.cancel();
    state=MeshCoreState.none; deviceId=null; deviceName=null; error=null; userOff=false; trying=false; retryIn=null;
    _attempt=0; testJoins=0; testPrefs.clear();
  }

  /// « Déconnecter » (lot 19): the Bluetooth link is cut, the module stays
  /// remembered, and it is not joined again by itself, even at the next
  /// start, until « Se connecter ».
  Future<void> disconnect() async {
    if(deviceId==null)return;
    userOff=true;
    await _setPref(meshCoreOffKey,'1');
    await _drop();
    trying=false; retryIn=null; _attempt=0;
    log('déconnecté à la demande');
    _set(MeshCoreState.disconnected);
  }

  /// « Se connecter » (lot 19): back to the automatic link. Web: the
  /// browser may ask to choose the module again (a click).
  Future<void> connect() async {
    if(deviceId==null)return;
    // Web: the browser's window first, while the click still counts; the
    // choice clears the « déconnecté » mark (see [choose]).
    if(kIsWeb&&!_webChosen.contains(deviceId)){await chooseInBrowser();return;}
    userOff=false;
    await _setPref(meshCoreOffKey,null);
    _attempt=0;
    await _join();
  }

  /// Chosen in Paramètres › Liaisons: remembered, then joined.
  Future<void> choose(BleDevice d,{LocalStore? store}) async {
    if(store!=null)_store=store;
    final st=_store; if(st!=null)_wire(st);
    await _drop();
    deviceId=d.deviceId; deviceName=d.name;
    await _setPref(meshCoreDeviceKey,deviceId);
    await _setPref(meshCoreNameKey,deviceName);
    // Choosing a module is asking for the link (lot 19).
    userOff=false; await _setPref(meshCoreOffKey,null);
    _attempt=0;
    await _join();
  }

  /// « Oublier ce module »: disconnected and no longer joined at start.
  Future<void> forget() async {
    await _drop();
    deviceId=null; deviceName=null; info=MeshCoreInfo(); _contacts.clear(); linkRssi=null;
    await _setPref(meshCoreDeviceKey,null);
    await _setPref(meshCoreNameKey,null);
    userOff=false; await _setPref(meshCoreOffKey,null);
    log('module oublié');
    _set(MeshCoreState.none);
  }

  Future<void> _join() async {
    final id=deviceId; if(id==null||userOff)return;
    if(testMode){testJoins++;_attempt=0;_set(MeshCoreState.connected);return;}
    // Web: only a module chosen in this tab can be joined (the browser asks
    // for a click); after a drop, it is joined again by itself.
    if(kIsWeb&&!_webChosen.contains(id)){_retry?.cancel();trying=false;_set(MeshCoreState.waitingClick);return;}
    _retry?.cancel();
    trying=true; retryIn=null;
    _set(_attempt==0?MeshCoreState.connecting:MeshCoreState.reconnecting);
    try{
      log('connexion à ${deviceName??id}');
      await UniversalBle.connect(id,timeout:const Duration(seconds:20));
      // « Déconnecter » pressed meanwhile (lot 19).
      if(userOff){try{await UniversalBle.disconnect(id);}catch(_){}trying=false;return;}
      final services=await UniversalBle.discoverServices(id);
      if(!services.any((s)=>s.uuid.toLowerCase()==meshCoreService))throw StateError('not a companion module');
      try{await UniversalBle.requestMtu(id,512);}catch(_){/* default MTU kept */}
      await _valueSub?.cancel();
      _valueSub=UniversalBle.characteristicValueStream(id,meshCoreTx).listen(_onFrame);
      await UniversalBle.subscribeNotifications(id,meshCoreService,meshCoreTx);
      await _connSub?.cancel();
      _connSub=UniversalBle.connectionStream(id).listen((up){if(!up)_lost();});
      connectedSince=DateTime.now(); _attempt=0; trying=false;
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
      trying=false;
      _schedule('$e');
    }
  }

  void _lost(){
    if(_stopping||userOff||state!=MeshCoreState.connected)return;
    log('liaison perdue');
    _poll?.cancel();
    _schedule(null);
  }

  void _schedule(String? err){
    if(deviceId==null||userOff)return;
    final wait=meshCoreRetryDelay(_attempt++);
    retryIn=wait;
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
      // Messages kept by the module while SARCADE was away (lot 17).
      await Future<void>.delayed(const Duration(milliseconds:300));
      await _send(syncNextMessage(),'SYNC_NEXT_MESSAGE');
      try{linkRssi=await UniversalBle.readRssi(id);}catch(_){}
      notifyListeners();
    }catch(e){log('échec : $e');}
  }

  /// The private messages (lot 17) go through this link; their threads are
  /// kept in the preferences of the device.
  bool _wired=false;
  void _wire(LocalStore store){
    final chats=MeshCoreChats.instance;
    chats.send=(frame,what) async {
      if(state!=MeshCoreState.connected)throw StateError('no module');
      await _send(frame,what);
    };
    chats.notify??=(title,body)=>unawaited(NotificationService().message(title:title,body:body,priority:'routine'));
    if(_wired)return;
    _wired=true;
    showOnMap=store.preference(meshCoreMapKey)=='1';
    chats.attach(load:store.preference,save:store.setPreference);
    // Lot 19: remote control of relays, its answers come as messages.
    final remotes=MeshCoreRemotes.instance;
    remotes.attach(load:store.preference,save:store.setPreference);
    chats.onIncoming??=(prefix,text,at)=>remotes.onIncoming(prefix,text,now:at);
  }

  /// « Afficher les nœuds sur la carte », remembered on this device.
  Future<void> setShowOnMap(bool on) async {
    showOnMap=on; notifyListeners();
    await _store?.setPreference(meshCoreMapKey,on?'1':null);
  }

  /// The node whose public key starts with [prefix], if known.
  MeshCoreContact? contactOf(String prefix)=>_contacts.values.where((c)=>meshCorePrefix(c.key)==meshCorePrefix(prefix)).firstOrNull;

  Future<void> _send(Uint8List frame,String what) async {
    final id=deviceId; if(id==null)return;
    log(what=='SEND_TXT_MSG'?'→ $what':'→ $what ${meshCoreHex(frame)}');
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
      // Private messages (lot 17).
      case 'sent':
        final sent=readMeshCoreSent(v); if(sent!=null)MeshCoreChats.instance.onSent(sent.ack,sent.timeout);
      case 'error':
        MeshCoreChats.instance.onError();
      case 'confirmed':
        final ack=readMeshCoreConfirmed(v); if(ack!=null)MeshCoreChats.instance.onConfirmed(ack);
      case 'waiting': case 'channelMsg':
        unawaited(_send(syncNextMessage(),'SYNC_NEXT_MESSAGE'));
      case 'contactMsg':
        final msg=readMeshCoreMessage(v);
        if(msg!=null)MeshCoreChats.instance.onReceived(msg,nameOf:(p){final n=contactOf(p)?.name;return n==null||n.isEmpty?null:n;});
        unawaited(_send(syncNextMessage(),'SYNC_NEXT_MESSAGE'));
    }
    // The text of a message stays out of the journal.
    if(kind=='contactMsg'){log('← $kind');}else if(kind!='contact'){log('← $kind ${meshCoreHex(v)}');}
    notifyListeners();
  }

  Future<void> _drop() async {
    _stopping=true;
    _retry?.cancel(); _poll?.cancel();
    await _valueSub?.cancel(); _valueSub=null;
    await _connSub?.cancel(); _connSub=null;
    final id=deviceId;
    if(id!=null&&!testMode){try{await UniversalBle.disconnect(id);}catch(_){}}
    connectedSince=null;
    _stopping=false;
  }

  /// Web: modules chosen in the browser's window during this tab.
  final Set<String> _webChosen={};

  /// Web: the browser's window to choose the module (to be called from a
  /// click); null when cancelled.
  Future<BleDevice?> pickInBrowser() async {
    BleDevice? got;
    final sub=UniversalBle.scanStream.listen((d){got??=d;});
    try{
      await UniversalBle.startScan(scanFilter:ScanFilter(withServices:[meshCoreService]));
      await Future<void>.delayed(const Duration(milliseconds:300));
    }catch(e){
      log('choix du module : $e');
    }finally{
      await sub.cancel();
      try{await UniversalBle.stopScan();}catch(_){}
    }
    return got;
  }

  /// Web: « Connecter un module MeshCore » and « Reconnecter le module ».
  Future<void> chooseInBrowser() async {
    final d=await pickInBrowser();
    if(d==null)return;
    _webChosen.add(d.deviceId);
    await choose(d);
  }
}
