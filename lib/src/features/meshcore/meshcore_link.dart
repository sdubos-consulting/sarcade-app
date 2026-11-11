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
import '../../services/notification_service.dart';
import '../lora/lora_battery.dart';
import '../lora/lora_link.dart';
import '../lora/lora_watch.dart';
import '../remotes/remote_meshcore.dart';
import 'meshcore_chat.dart';
import 'meshcore_protocol.dart';

/// States of the link (lot 28: shared with Meshtastic, lora/lora_link.dart).
typedef MeshCoreState=LoraLinkState;

/// Preference keys of the remembered module.
const meshCoreDeviceKey='meshcore_device', meshCoreNameKey='meshcore_name';
/// « Afficher les nœuds sur la carte » (lot 17), off by default.
const meshCoreMapKey='meshcore_map';
/// « Déconnecter » (lot 19): '1' while the module is left disconnected on
/// purpose, start of the application included.
const meshCoreOffKey='meshcore_off';

/// Colour family of the pill (lora/lora_link.dart).
String meshCorePillTone(MeshCoreState s)=>loraPillTone(s);

/// Delay before the next attempt (lora/lora_link.dart).
Duration meshCoreRetryDelay(int attempt)=>loraRetryDelay(attempt);

/// Text shown when the module cannot be reached (card « MeshCore : message
/// d'erreur lisible », validated 1 Nov 2026, 8 h 15; lora/lora_link.dart).
String? meshCoreProblem({required MeshCoreState state,required bool trying,String? error,Duration? retryIn})=>
  loraProblem(state:state,trying:trying,error:error,retryIn:retryIn);

/// Nodes sorted for the list: heard most recently first, unnamed last.
List<MeshCoreContact> sortedContacts(Iterable<MeshCoreContact> all)=>all.toList()
  ..sort((a,b){
    final t=(b.lastAdvert?.millisecondsSinceEpoch??0).compareTo(a.lastAdvert?.millisecondsSinceEpoch??0);
    return t!=0?t:a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

class MeshCoreLink extends ChangeNotifier implements LoraModuleLink {
  MeshCoreLink._(){LoraWatch.instance.attach(this);}
  static final MeshCoreLink instance=MeshCoreLink._();

  LocalStore? _store;
  @override MeshCoreState state=MeshCoreState.none;
  @override String? deviceId;
  String? deviceName, error;
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
  /// Card « Diagnostic : modules LoRa… » (10 Nov 2026): first failure of
  /// the series (« hors de portée depuis 09:20 », choice 2), and the module
  /// joined but silent (choice 5, red).
  @override DateTime? failingSince;
  @override bool noAnswer=false;
  bool _manual=false;
  Timer? _answerCheck;
  int _framesAtJoin=0;
  @override String get bleService=>meshCoreService;
  @override String get displayName=>deviceName??deviceId??'';

  /// Tests: the clock, and a module off ([testReachable] false).
  @visibleForTesting DateTime Function() now=DateTime.now;
  @visibleForTesting bool testReachable=true;

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
  @override bool get remembered=>deviceId!=null;
  /// Every platform, the web app included (lot 17, card « Application web :
  /// se connecter à un module MeshCore »): in a browser without Web
  /// Bluetooth, Outils › MeshCore says to use Chrome, Edge or the app.
  bool get supported=>true;
  /// Bluetooth usable here: always in the apps, Web Bluetooth in a browser.
  bool get browserReady=>!kIsWeb||webBluetoothAvailable();

  @override void log(String line){
    final t=DateTime.now(); String two(int v)=>v.toString().padLeft(2,'0');
    journal.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} $line');
    if(journal.length>300)journal.removeAt(0);
  }

  void _set(MeshCoreState s,{String? err}){state=s;error=err;notifyListeners();LoraWatch.instance.update();}

  /// At start: joins the remembered module, if any.
  Future<void> restore(LocalStore store) async {
    _store=store;
    _wire(store);
    LoraWatch.instance.start();
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
    _retry?.cancel(); _poll?.cancel(); _answerCheck?.cancel();
    state=MeshCoreState.none; deviceId=null; deviceName=null; error=null; userOff=false; trying=false; retryIn=null;
    failingSince=null; noAnswer=false; _manual=false; now=DateTime.now; testReachable=true;
    _attempt=0; testJoins=0; testPrefs.clear();
  }

  /// « Déconnecter » (lot 19): the Bluetooth link is cut, the module stays
  /// remembered, and it is not joined again by itself, even at the next
  /// start, until « Se connecter ».
  /// [from]: where it was pressed (« Diagnostic », card « Diagnostic :
  /// modules LoRa… », choice 6), written in the journal.
  @override
  Future<void> disconnect({String? from}) async {
    if(deviceId==null)return;
    userOff=true;
    await _setPref(meshCoreOffKey,'1');
    await _drop();
    trying=false; retryIn=null; _attempt=0; failingSince=null;
    log(from==null?'déconnecté à la demande':'déconnecté à la demande ($from)');
    _set(MeshCoreState.disconnected);
  }

  /// « Se connecter » (lot 19): back to the automatic link. Web: the
  /// browser may ask to choose the module again (a click).
  @override
  Future<void> connect() async {
    if(deviceId==null)return;
    // Web: the browser's window first, while the click still counts; the
    // choice clears the « déconnecté » mark (see [choose]).
    if(kIsWeb&&!_webChosen.contains(deviceId)){await chooseInBrowser();return;}
    userOff=false;
    await _setPref(meshCoreOffKey,null);
    _attempt=0; failingSince=null; _manual=true;
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
    _attempt=0; failingSince=null; _manual=true;
    await _join();
  }

  /// « Oublier ce module »: disconnected and no longer joined at start.
  Future<void> forget() async {
    await _drop();
    deviceId=null; deviceName=null; info=MeshCoreInfo(); _contacts.clear(); linkRssi=null;
    await _setPref(meshCoreDeviceKey,null);
    await _setPref(meshCoreNameKey,null);
    userOff=false; await _setPref(meshCoreOffKey,null);
    failingSince=null; retryIn=null; trying=false;
    log('module oublié');
    _set(MeshCoreState.none);
  }

  Future<void> _join() async {
    final id=deviceId; if(id==null||userOff)return;
    // Bluetooth of the phone off: no attempt (choice 4).
    if(!LoraWatch.instance.bluetoothOn){bluetoothChanged(false);return;}
    if(testMode){
      testJoins++;
      if(!testReachable){trying=false;_schedule('TimeoutException after 0:00:20');return;}
      _joinedOk();_set(MeshCoreState.connected);return;
    }
    // Web: only a module chosen in this tab can be joined (the browser asks
    // for a click); after a drop, it is joined again by itself.
    if(kIsWeb&&!_webChosen.contains(id)){_retry?.cancel();trying=false;_set(MeshCoreState.waitingClick);return;}
    _retry?.cancel();
    trying=true; retryIn=null;
    _set(loraTryingState(before:state,attempt:_attempt));
    var joined=false;
    try{
      log('connexion à ${deviceName??id}');
      await UniversalBle.connect(id,timeout:const Duration(seconds:20));
      joined=true;
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
      connectedSince=DateTime.now(); _joinedOk(); trying=false;
      _set(MeshCoreState.connected);
      _watchAnswer();
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
      _schedule('$e',joined:joined);
    }
  }

  void _joinedOk(){_attempt=0;failingSince=null;_manual=false;noAnswer=false;}

  /// Choice 5: joined, but no frame from the module within 15 s: red.
  void _watchAnswer(){
    _answerCheck?.cancel(); _framesAtJoin=framesIn;
    _answerCheck=Timer(const Duration(seconds:15),(){
      if(state!=MeshCoreState.connected||framesIn!=_framesAtJoin)return;
      noAnswer=true; log('le module ne répond pas'); notifyListeners();
    });
  }

  /// The module announced itself while out of reach (choice 3).
  @override
  void heard(){
    if(state!=MeshCoreState.outOfReach||userOff||trying)return;
    _retry?.cancel();
    unawaited(_join());
  }

  /// Bluetooth of the phone off: grey « Bluetooth coupé », no attempt;
  /// back: the module is joined again without any action (choice 4).
  @override
  void bluetoothChanged(bool on){
    if(deviceId==null||userOff)return;
    if(!on){
      if(const {MeshCoreState.bluetoothOff,MeshCoreState.none,MeshCoreState.waitingClick,MeshCoreState.unavailable}.contains(state))return;
      _retry?.cancel(); _poll?.cancel(); _answerCheck?.cancel();
      trying=false; retryIn=null; _attempt=0; failingSince=null;
      log('Bluetooth du téléphone coupé : plus d’essai');
      _set(MeshCoreState.bluetoothOff);
    }else if(state==MeshCoreState.bluetoothOff){
      log('Bluetooth du téléphone rétabli');
      _attempt=0;
      unawaited(_join());
    }
  }

  void _lost(){
    if(_stopping||userOff||state!=MeshCoreState.connected)return;
    log('liaison perdue');
    _poll?.cancel();
    _schedule(null);
  }

  /// After a failure (card « Diagnostic : modules LoRa… », choices 2 and
  /// 5): orange while it tries again (5 s, 15 s, 30 s, then every minute),
  /// grey « hors de portée » after 5 minutes with a try every 5 minutes;
  /// red only for a module joined but silent, or a connection asked by hand.
  void _schedule(String? err,{bool joined=false}){
    if(deviceId==null||userOff)return;
    if(!LoraWatch.instance.bluetoothOn){bluetoothChanged(false);return;}
    final t=now(); final since=failingSince??=t;
    final next=loraAfterFailure(attempt:_attempt++,failing:t.difference(since),manual:_manual,joined:joined);
    _manual=false;
    if(next.state==MeshCoreState.outOfReach&&state!=MeshCoreState.outOfReach)log('hors de portée : un essai toutes les ${loraOutOfReachEvery.inMinutes} min');
    retryIn=next.wait;
    _set(next.state,err:err);
    _retry?.cancel();
    _retry=Timer(next.wait,()=>unawaited(_join()));
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
    // Lot 25: thresholds kept on this device, alert notified.
    final battery=LoraBatteryMonitor.instance;
    battery.read??=store.preference; battery.save??=store.setPreference;
    battery.notify??=(title,body)=>unawaited(NotificationService().message(title:title,body:body,priority:'urgent'));
    if(_wired)return;
    _wired=true;
    showOnMap=store.preference(meshCoreMapKey)=='1';
    chats.attach(load:store.preference,save:store.setPreference);
    // Lot 21: Outils › Télécommandes, MeshCore carries their commands and
    // brings back the answers of the boxes.
    wireMeshCoreRemotes(load:store.preference,save:store.setPreference);
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
    framesIn++; lastFrameAt=DateTime.now(); noAnswer=false;
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
      // Lot 25: low battery of the module (lora_battery.dart).
      case 'battery':
        final mv=info.batteryMv, id=deviceId;
        if(mv!=null&&id!=null)LoraBatteryMonitor.instance.report(id:id,name:info.name??deviceName??id,box:LoraBox.meshcore,millivolts:mv);
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
    _retry?.cancel(); _poll?.cancel(); _answerCheck?.cancel(); noAnswer=false;
    await _valueSub?.cancel(); _valueSub=null;
    await _connSub?.cancel(); _connSub=null;
    final id=deviceId;
    if(id!=null&&!testMode){try{await UniversalBle.disconnect(id);}catch(_){}}
    if(id!=null)LoraBatteryMonitor.instance.forget(id);
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

  /// Web, « Reconnecter » of the bar (lot 25, card « Web, MeshCore :
  /// bandeau affiché en permanence », point 2): when the module cannot be
  /// joined (off or out of reach), the bar goes and the state becomes
  /// « module indisponible », without automatic attempts; the pill stays
  /// to try again later. [pick] and [join] are replaced by the tests.
  Future<void> reconnectInBrowser({Future<BleDevice?> Function()? pick,Future<void> Function(BleDevice)? join}) async {
    final d=await (pick??pickInBrowser)();
    if(d!=null){
      _webChosen.add(d.deviceId);
      await (join??choose)(d);
      if(state==MeshCoreState.connected||state==MeshCoreState.disconnected)return;
    }
    _retry?.cancel(); trying=false; retryIn=null;
    log('module indisponible');
    _set(MeshCoreState.unavailable);
  }
}
