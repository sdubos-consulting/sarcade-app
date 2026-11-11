// SPDX-License-Identifier: MPL-2.0
// © SDUBOS Consulting et contributeurs SARCADE

/// Persistent Bluetooth link to a Meshtastic module (lot 28, card « Module
/// Meshtastic, sur le modèle de MeshCore », choices 1 to 8 validated on
/// 2 Nov 2026, 5 h 06). Core, like MeshCore: no radio licence needed.
///
/// Same behaviour as MeshCore (meshcore_link.dart): the module is chosen
/// once in Outils › Meshtastic, remembered, joined again at start and after
/// a drop; « Déconnecter » keeps it without joining it again, « Oublier »
/// forgets it; web app through Web Bluetooth (Chrome, Edge) with the bar
/// « Reconnecter » and « Plus tard ». The state shows in the link pill of
/// the map, the battery of the module goes to the low battery alert
/// (lora/lora_battery.dart).
///
/// Meshtastic over Bluetooth: the application writes one ToRadio message,
/// and reads FromRadio until it is empty, each time FromNum is notified
/// (meshtastic_protocol.dart).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../offline/local_store.dart';
import '../../platform/platform_services.dart' show webBluetoothAvailable;
import '../../services/notification_service.dart';
import '../lora/lora_battery.dart';
import '../lora/lora_link.dart';
import '../lora/lora_watch.dart';
import 'meshtastic_chat.dart';
import 'meshtastic_protocol.dart';

/// Preference keys of the remembered module.
const meshtasticDeviceKey='meshtastic_device', meshtasticNameKey='meshtastic_name';
/// « Afficher les nœuds sur la carte », off by default.
const meshtasticMapKey='meshtastic_map';
/// « Déconnecter »: '1' while the module is left disconnected on purpose.
const meshtasticOffKey='meshtastic_off';

/// Nodes sorted for the list: heard most recently first, then by name.
List<MeshtasticNode> sortedMeshtasticNodes(Iterable<MeshtasticNode> all)=>all.toList()
  ..sort((a,b){
    final t=(b.lastHeard?.millisecondsSinceEpoch??0).compareTo(a.lastHeard?.millisecondsSinceEpoch??0);
    return t!=0?t:a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

/// Percentage given to the low battery alert: the level of the node, 100
/// on external power, else from the voltage (null when nothing is known).
({int? percent,int? millivolts}) meshtasticBatteryReport(MeshtasticNode n){
  final b=n.battery;
  if(b!=null&&b>0)return (percent:b>100?100:b,millivolts:null);
  final v=n.voltage;
  if(v!=null&&v>0)return (percent:null,millivolts:(v*1000).round());
  return (percent:null,millivolts:null);
}

class MeshtasticLink extends ChangeNotifier implements LoraModuleLink {
  MeshtasticLink._(){LoraWatch.instance.attach(this);}
  static final MeshtasticLink instance=MeshtasticLink._();

  LocalStore? _store;
  @override LoraLinkState state=LoraLinkState.none;
  @override String? deviceId;
  String? deviceName, error;
  MeshtasticInfo info=MeshtasticInfo();
  final Map<int,MeshtasticNode> _nodes={};
  int? linkRssi;
  int framesIn=0, framesOut=0;
  DateTime? lastFrameAt, connectedSince;
  final List<String> journal=[];
  /// A connection attempt is running (the spinner turns only then).
  bool trying=false;
  /// Delay before the next attempt after a failure.
  Duration? retryIn;
  /// « Nœuds Meshtastic » layer of the map, off by default.
  bool showOnMap=false;
  /// « Déconnecter »: no automatic join until « Se connecter ».
  bool userOff=false;
  /// Card « Diagnostic : modules LoRa… » (10 Nov 2026): first failure of
  /// the series (« hors de portée depuis 09:20 », choice 2), and the module
  /// joined but silent (choice 5, red).
  @override DateTime? failingSince;
  @override bool noAnswer=false;
  bool _manual=false;
  Timer? _answerCheck;
  int _framesAtJoin=0;
  @override String get bleService=>meshtasticService;
  @override String get displayName=>deviceName??deviceId??'';

  /// Tests: the clock, and a module off ([testReachable] false).
  @visibleForTesting DateTime Function() now=DateTime.now;
  @visibleForTesting bool testReachable=true;

  /// Every packet heard (messages, acknowledgements: meshtastic_chat.dart).
  final List<void Function(MeshtasticPacket)> _packetListeners=[];
  /// Every QueueStatus (a message taken by the module, or refused).
  final List<void Function(MeshtasticQueue)> _queueListeners=[];
  void addPacketListener(void Function(MeshtasticPacket) l)=>_packetListeners.add(l);
  void addQueueListener(void Function(MeshtasticQueue) l)=>_queueListeners.add(l);

  /// Tests: no Bluetooth, preferences in [testPrefs], [testJoins] counts
  /// the attempts to join the module, [testSent] the messages written.
  @visibleForTesting bool testMode=false;
  @visibleForTesting int testJoins=0;
  @visibleForTesting final Map<String,String?> testPrefs={};
  @visibleForTesting final List<Uint8List> testSent=[];
  String? _pref(String key)=>testMode?testPrefs[key]:_store?.preference(key);
  Future<void> _setPref(String key,String? value) async {
    if(testMode){testPrefs[key]=value;return;}
    await _store?.setPreference(key,value);
  }

  StreamSubscription<Uint8List>? _valueSub;
  StreamSubscription<bool>? _connSub;
  Timer? _retry, _poll;
  int _attempt=0, _ticks=0;
  bool _stopping=false, _draining=false, _drainAgain=false;
  final _random=math.Random();

  List<MeshtasticNode> get nodes=>sortedMeshtasticNodes(_nodes.values);
  /// The other nodes (the module itself apart).
  List<MeshtasticNode> get others=>sortedMeshtasticNodes(_nodes.values.where((n)=>n.num!=info.myNum));
  MeshtasticNode? node(int num)=>_nodes[num];
  /// The node of the module itself.
  MeshtasticNode? get me=>info.myNum==null?null:_nodes[info.myNum];
  @override bool get remembered=>deviceId!=null;
  bool get connected=>state==LoraLinkState.connected;
  /// Bluetooth usable here: always in the apps, Web Bluetooth in a browser.
  bool get browserReady=>!kIsWeb||webBluetoothAvailable();

  @override void log(String line){
    final t=DateTime.now(); String two(int v)=>v.toString().padLeft(2,'0');
    journal.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} $line');
    if(journal.length>300)journal.removeAt(0);
  }

  void _set(LoraLinkState s,{String? err}){state=s;error=err;notifyListeners();LoraWatch.instance.update();}

  /// At start: joins the remembered module, if any.
  Future<void> restore(LocalStore store) async {
    _store=store;
    _wire(store);
    LoraWatch.instance.start();
    _restore();
  }

  void _restore(){
    if(state!=LoraLinkState.none)return;
    deviceId=_pref(meshtasticDeviceKey); deviceName=_pref(meshtasticNameKey);
    if(deviceId==null)return;
    userOff=_pref(meshtasticOffKey)=='1';
    if(userOff){log('module déconnecté à la demande : pas de connexion au démarrage');_set(LoraLinkState.disconnected);return;}
    notifyListeners(); unawaited(_join());
  }

  @visibleForTesting
  void restoreForTest()=>_restore();

  /// Tests: back to the state of a fresh start.
  @visibleForTesting
  void resetForTest(){
    _retry?.cancel(); _poll?.cancel(); _answerCheck?.cancel();
    state=LoraLinkState.none; deviceId=null; deviceName=null; error=null; userOff=false; trying=false; retryIn=null;
    failingSince=null; noAnswer=false; _manual=false; now=DateTime.now; testReachable=true;
    info=MeshtasticInfo(); _nodes.clear(); showOnMap=false; framesIn=0; framesOut=0;
    _attempt=0; testJoins=0; testPrefs.clear(); testSent.clear(); _webChosen.clear();
  }

  /// « Déconnecter »: the link is cut, the module stays remembered and is
  /// not joined again by itself, even at the next start.
  /// [from]: where it was pressed (« Diagnostic », card « Diagnostic :
  /// modules LoRa… », choice 6), written in the journal.
  @override
  Future<void> disconnect({String? from}) async {
    if(deviceId==null)return;
    userOff=true;
    await _setPref(meshtasticOffKey,'1');
    await _drop(polite:true);
    trying=false; retryIn=null; _attempt=0; failingSince=null;
    log(from==null?'déconnecté à la demande':'déconnecté à la demande ($from)');
    _set(LoraLinkState.disconnected);
  }

  /// « Se connecter »: back to the automatic link (web: the browser may
  /// ask to choose the module again).
  @override
  Future<void> connect() async {
    if(deviceId==null)return;
    if(kIsWeb&&!_webChosen.contains(deviceId)){await chooseInBrowser();return;}
    userOff=false;
    await _setPref(meshtasticOffKey,null);
    _attempt=0; failingSince=null; _manual=true;
    await _join();
  }

  /// Chosen in Outils › Meshtastic: remembered, then joined.
  Future<void> choose(BleDevice d,{LocalStore? store}) async {
    if(store!=null)_store=store;
    final st=_store; if(st!=null)_wire(st);
    await _drop();
    deviceId=d.deviceId; deviceName=d.name;
    info=MeshtasticInfo(); _nodes.clear();
    await _setPref(meshtasticDeviceKey,deviceId);
    await _setPref(meshtasticNameKey,deviceName);
    userOff=false; await _setPref(meshtasticOffKey,null);
    _attempt=0; failingSince=null; _manual=true;
    await _join();
  }

  /// « Oublier ce module »: disconnected and no longer joined at start.
  Future<void> forget() async {
    await _drop(polite:true);
    deviceId=null; deviceName=null; info=MeshtasticInfo(); _nodes.clear(); linkRssi=null;
    await _setPref(meshtasticDeviceKey,null);
    await _setPref(meshtasticNameKey,null);
    userOff=false; await _setPref(meshtasticOffKey,null);
    failingSince=null; retryIn=null; trying=false;
    log('module oublié');
    _set(LoraLinkState.none);
  }

  Future<void> _join() async {
    final id=deviceId; if(id==null||userOff)return;
    // Bluetooth of the phone off: no attempt (choice 4).
    if(!LoraWatch.instance.bluetoothOn){bluetoothChanged(false);return;}
    if(testMode){
      testJoins++;
      if(!testReachable){trying=false;_schedule('TimeoutException after 0:00:20');return;}
      _joinedOk();connectedSince=DateTime.now();_set(LoraLinkState.connected);return;
    }
    if(kIsWeb&&!_webChosen.contains(id)){_retry?.cancel();trying=false;_set(LoraLinkState.waitingClick);return;}
    _retry?.cancel();
    trying=true; retryIn=null;
    _set(loraTryingState(before:state,attempt:_attempt));
    var joined=false;
    try{
      log('connexion à ${deviceName??id}');
      await UniversalBle.connect(id,timeout:const Duration(seconds:20));
      joined=true;
      if(userOff){try{await UniversalBle.disconnect(id);}catch(_){}trying=false;return;}
      final services=await UniversalBle.discoverServices(id);
      if(!services.any((s)=>s.uuid.toLowerCase()==meshtasticService))throw StateError('not a Meshtastic module');
      try{await UniversalBle.requestMtu(id,512);}catch(_){/* default MTU kept */}
      await _valueSub?.cancel();
      _valueSub=UniversalBle.characteristicValueStream(id,meshtasticFromNum).listen((_)=>unawaited(_drain()));
      await UniversalBle.subscribeNotifications(id,meshtasticService,meshtasticFromNum);
      await _connSub?.cancel();
      _connSub=UniversalBle.connectionStream(id).listen((up){if(!up)_lost();});
      connectedSince=DateTime.now(); _joinedOk(); trying=false;
      _set(LoraLinkState.connected);
      _watchAnswer();
      await refresh();
      _poll?.cancel(); _ticks=0;
      // Every 15 s: what the module has to say (FromNum is not notified on
      // every platform); every 5 min: a heartbeat.
      _poll=Timer.periodic(const Duration(seconds:15),(_){
        _ticks++;
        if(_ticks%20==0)unawaited(_write(meshtasticHeartbeat(),'heartbeat'));
        unawaited(_drain());
      });
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
      if(state!=LoraLinkState.connected||framesIn!=_framesAtJoin)return;
      noAnswer=true; log('le module ne répond pas'); notifyListeners();
    });
  }

  /// The module announced itself while out of reach (choice 3).
  @override
  void heard(){
    if(state!=LoraLinkState.outOfReach||userOff||trying)return;
    _retry?.cancel();
    unawaited(_join());
  }

  /// Bluetooth of the phone off: grey « Bluetooth coupé », no attempt;
  /// back: the module is joined again without any action (choice 4).
  @override
  void bluetoothChanged(bool on){
    if(deviceId==null||userOff)return;
    if(!on){
      if(const {LoraLinkState.bluetoothOff,LoraLinkState.none,LoraLinkState.waitingClick,LoraLinkState.unavailable}.contains(state))return;
      _retry?.cancel(); _poll?.cancel(); _answerCheck?.cancel();
      trying=false; retryIn=null; _attempt=0; failingSince=null;
      log('Bluetooth du téléphone coupé : plus d’essai');
      _set(LoraLinkState.bluetoothOff);
    }else if(state==LoraLinkState.bluetoothOff){
      log('Bluetooth du téléphone rétabli');
      _attempt=0;
      unawaited(_join());
    }
  }

  void _lost(){
    if(_stopping||userOff||state!=LoraLinkState.connected)return;
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
    if(next.state==LoraLinkState.outOfReach&&state!=LoraLinkState.outOfReach)log('hors de portée : un essai toutes les ${loraOutOfReachEvery.inMinutes} min');
    retryIn=next.wait;
    _set(next.state,err:err);
    _retry?.cancel();
    _retry=Timer(next.wait,()=>unawaited(_join()));
  }

  /// « Relire » and at the opening of Outils › Meshtastic: the module sends
  /// again its settings and the nodes it knows.
  Future<void> refresh() async {
    final id=deviceId; if(id==null||state!=LoraLinkState.connected)return;
    try{
      await _write(meshtasticWantConfig(_random.nextInt(0x7FFFFFFE)+1),'want_config');
      await _drain();
      if(!testMode){try{linkRssi=await UniversalBle.readRssi(id);}catch(_){}}
      notifyListeners();
    }catch(e){log('échec : $e');}
  }

  /// Writes one ToRadio message; throws when no module is connected.
  Future<void> send(Uint8List toRadio,String what) async {
    if(state!=LoraLinkState.connected)throw StateError('no module');
    await _write(toRadio,what);
    unawaited(_drain());
  }

  /// A new packet id (never 0).
  int newPacketId()=>_random.nextInt(0x7FFFFFFE)+1;

  Future<void> _write(Uint8List frame,String what) async {
    final id=deviceId; if(id==null)return;
    log(what=='text'?'→ $what':'→ $what ${meshtasticHex(frame)}');
    framesOut++;
    if(testMode){testSent.add(frame);return;}
    await UniversalBle.write(id,meshtasticService,meshtasticToRadio,frame);
  }

  /// Reads FromRadio until it is empty (one reader at a time).
  Future<void> _drain() async {
    final id=deviceId; if(id==null||testMode||state!=LoraLinkState.connected)return;
    if(_draining){_drainAgain=true;return;}
    _draining=true;
    try{
      do{
        _drainAgain=false;
        for(var i=0;i<1000;i++){
          final v=await UniversalBle.read(id,meshtasticService,meshtasticFromRadio);
          if(v.isEmpty)break;
          onFrame(v);
        }
      }while(_drainAgain);
    }catch(e){
      log('lecture : $e');
    }finally{
      _draining=false;
    }
  }

  /// Name of the primary channel: its own, else the name of the preset.
  String? get channelName{
    final c=info.channelName;
    return c==null?null:c.isEmpty?meshtasticPresetName(info.preset):c;
  }

  /// The messages (point 3) go through this link.
  bool _chatsWired=false;
  void _wireChats(){
    final chats=MeshtasticChats.instance;
    chats.send=send; chats.newId=newPacketId;
    chats.myNum=()=>info.myNum;
    chats.nameOf=(n)=>_nodes[n]?.name;
    chats.channelName=()=>channelName;
    if(_chatsWired)return;
    _chatsWired=true;
    addPacketListener(chats.onPacket);
    addQueueListener(chats.onQueue);
  }

  /// Tests: the messages wired without a store.
  @visibleForTesting
  void wireChatsForTest()=>_wireChats();

  bool _storeWired=false;
  void _wire(LocalStore store){
    _wireChats();
    final chats=MeshtasticChats.instance;
    chats.notify??=(title,body)=>unawaited(NotificationService().message(title:title,body:body,priority:'routine'));
    if(!_storeWired){_storeWired=true;chats.attach(load:store.preference,save:store.setPreference);}
    final battery=LoraBatteryMonitor.instance;
    battery.read??=store.preference; battery.save??=store.setPreference;
    battery.notify??=(title,body)=>unawaited(NotificationService().message(title:title,body:body,priority:'urgent'));
    showOnMap=store.preference(meshtasticMapKey)=='1';
  }

  /// « Afficher les nœuds sur la carte », remembered on this device.
  Future<void> setShowOnMap(bool on) async {
    showOnMap=on; notifyListeners();
    if(testMode){testPrefs[meshtasticMapKey]=on?'1':null;return;}
    await _store?.setPreference(meshtasticMapKey,on?'1':null);
  }

  MeshtasticNode _nodeOf(int num)=>_nodes.putIfAbsent(num,()=>MeshtasticNode(num));

  /// One FromRadio message (tests: a simulated module).
  @visibleForTesting
  void onFrame(Uint8List v){
    framesIn++; lastFrameAt=DateTime.now(); noAnswer=false;
    final MeshtasticFrame f;
    try{f=readMeshtasticFrame(v,info);}catch(e){log('← illisible ($e) ${meshtasticHex(v)}');return;}
    switch(f.kind){
      case 'node':
        final n=f.node!;
        _nodes[n.num]=n;
        if(n.num==info.myNum)_reportBattery(n);
      case 'configComplete':
        log('${_nodes.length} nœud(s) connu(s)');
        final mine=me; if(mine!=null)_reportBattery(mine);
      case 'rebooted':
        log('module redémarré');
        unawaited(refresh());
      case 'queue':
        for(final l in List.of(_queueListeners)){l(f.queue!);}
      case 'packet':
        _onPacket(f.packet!);
    }
    // The text of a message stays out of the journal; the node list is long.
    if(f.kind=='packet'){
      final p=f.packet!;
      log('← packet ${meshtasticId(p.from)} port ${p.portnum}${p.encrypted?' (chiffré)':''}');
    }else if(f.kind!='node'){
      log('← ${f.kind} ${meshtasticHex(v)}');
    }
    notifyListeners();
  }

  void _onPacket(MeshtasticPacket p){
    if(p.encrypted||p.from==0){for(final l in List.of(_packetListeners)){l(p);}return;}
    final n=_nodeOf(p.from);
    n.lastHeard=p.rxTime??DateTime.now().toUtc();
    if(p.snr!=null&&p.snr!=0)n.snr=p.snr;
    n.hops=p.hops??n.hops; n.viaMqtt=p.viaMqtt;
    try{
      switch(p.portnum){
        case meshtasticPortPosition: n.applyPosition(readMeshtasticPosition(p.payload));
        case meshtasticPortNodeInfo: n.applyUser(readMeshtasticUser(p.payload));
        case meshtasticPortTelemetry:
          final m=readMeshtasticTelemetry(p.payload);
          if(m!=null){n.applyMetrics(m);if(n.num==info.myNum)_reportBattery(n);}
      }
    }catch(e){log('← contenu illisible : $e');}
    for(final l in List.of(_packetListeners)){l(p);}
  }

  void _reportBattery(MeshtasticNode n){
    final id=deviceId; if(id==null)return;
    final r=meshtasticBatteryReport(n);
    if(r.percent==null&&r.millivolts==null)return;
    LoraBatteryMonitor.instance.report(id:id,name:n.name,box:LoraBox.meshtastic,percent:r.percent,millivolts:r.millivolts);
  }

  Future<void> _drop({bool polite=false}) async {
    _stopping=true;
    _retry?.cancel(); _poll?.cancel(); _answerCheck?.cancel(); noAnswer=false;
    final id=deviceId;
    if(polite&&id!=null&&state==LoraLinkState.connected&&!testMode){
      try{await UniversalBle.write(id,meshtasticService,meshtasticToRadio,meshtasticDisconnect());}catch(_){}
    }
    await _valueSub?.cancel(); _valueSub=null;
    await _connSub?.cancel(); _connSub=null;
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
      await UniversalBle.startScan(scanFilter:ScanFilter(withServices:[meshtasticService]));
      await Future<void>.delayed(const Duration(milliseconds:300));
    }catch(e){
      log('choix du module : $e');
    }finally{
      await sub.cancel();
      try{await UniversalBle.stopScan();}catch(_){}
    }
    return got;
  }

  /// Web: « Connecter un module Meshtastic » and « Reconnecter le module ».
  Future<void> chooseInBrowser() async {
    final d=await pickInBrowser();
    if(d==null)return;
    _webChosen.add(d.deviceId);
    await choose(d);
  }

  /// Web, « Reconnecter » of the bar: when the module cannot be joined
  /// (off or out of reach), the bar goes and the state becomes « module
  /// indisponible », without automatic attempts. [pick] and [join] are
  /// replaced by the tests.
  Future<void> reconnectInBrowser({Future<BleDevice?> Function()? pick,Future<void> Function(BleDevice)? join}) async {
    final d=await (pick??pickInBrowser)();
    if(d!=null){
      _webChosen.add(d.deviceId);
      await (join??choose)(d);
      if(state==LoraLinkState.connected||state==LoraLinkState.disconnected)return;
    }
    _retry?.cancel(); trying=false; retryIn=null;
    log('module indisponible');
    _set(LoraLinkState.unavailable);
  }

  /// Tests: the state of the web app waiting for a click.
  @visibleForTesting
  void setStateForTest(LoraLinkState s)=>_set(s);
}
