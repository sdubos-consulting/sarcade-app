// SPDX-License-Identifier: MPL-2.0
// © SDUBOS Consulting et contributeurs SARCADE

/// Watch shared by the LoRa links (card « Diagnostic : modules LoRa
/// (MeshCore, Meshtastic) injoignables, lien vers Outils et reconnexion
/// économe », validated on 10 Nov 2026):
/// - choice 4: the Bluetooth of the phone off stops every attempt (grey
///   « Bluetooth coupé »), its return joins the modules again;
/// - choice 3: Android and Windows listen for the module out of reach: a
///   short scan in low power (10 s every minute, filtered on the service of
///   the module); the module that announces itself is joined at once,
///   instead of waiting for the next try every 5 minutes. iPhone (limits of
///   iOS in the background), web, Linux and macOS: tries every 5 minutes
///   only.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'lora_link.dart';

/// What the watch and the Diagnostic need of a link to a LoRa module
/// (MeshCore, Meshtastic).
abstract class LoraModuleLink {
  String? get deviceId;
  /// Name shown in the Diagnostic.
  String get displayName;
  LoraLinkState get state;
  bool get remembered;
  /// First failure of the current series (« hors de portée depuis 09:20 »).
  DateTime? get failingSince;
  /// Joined, but no answer to SARCADE (choice 5: red).
  bool get noAnswer;
  /// Service announced by the module (filter of the scan).
  String get bleService;
  void log(String line);
  /// The module was heard: joined at once.
  void heard();
  /// Bluetooth of the phone off ([on] false) or back.
  void bluetoothChanged(bool on);
  /// « Déconnecter »; [from] goes to the journal (« Diagnostic »).
  Future<void> disconnect({String? from});
  /// « Se connecter ».
  Future<void> connect();
}

class LoraWatch {
  LoraWatch();
  static final LoraWatch instance=LoraWatch();

  /// Length and rhythm of the scans while a module is out of reach.
  static const scanFor=Duration(seconds:10), scanEvery=Duration(minutes:1);

  final List<LoraModuleLink> _links=[];
  /// Bluetooth of the phone usable (unknown counts as on).
  bool bluetoothOn=true;
  /// A search of Outils runs: the watch does not scan meanwhile.
  bool userScanning=false;
  StreamSubscription<AvailabilityState>? _avail;
  StreamSubscription<BleDevice>? _scanSub;
  Timer? _every;
  bool _scanning=false, _started=false;

  /// Tests: the platform listens or not ([passiveOverride]); no Bluetooth
  /// call in [testMode].
  @visibleForTesting bool? passiveOverride;
  @visibleForTesting bool testMode=false;
  @visibleForTesting int testScans=0;

  /// Android and Windows only (choice 3).
  bool get passiveSupported=>passiveOverride??(!kIsWeb&&(defaultTargetPlatform==TargetPlatform.android||defaultTargetPlatform==TargetPlatform.windows));
  /// The scans run (a module out of reach, Bluetooth on, Android or Windows).
  bool get listening=>_every!=null;

  void attach(LoraModuleLink l){if(!_links.contains(l))_links.add(l);}

  /// At start of a link (not in the tests): follows the Bluetooth of the
  /// phone. Web: nothing (the browser has no such state).
  void start(){
    if(_started||testMode||kIsWeb)return;
    _started=true;
    try{
      _avail=UniversalBle.availabilityStream.listen(availability,onError:(Object _){});
      unawaited(UniversalBle.getBluetoothAvailabilityState().then(availability,onError:(Object _){}));
    }catch(_){/* platform without this state */}
  }

  /// New state of the Bluetooth of the phone (choice 4).
  void availability(AvailabilityState a){
    final on=a!=AvailabilityState.poweredOff;
    if(on==bluetoothOn)return;
    bluetoothOn=on;
    for(final l in List.of(_links)){l.bluetoothChanged(on);}
    update();
  }

  /// Called by the links when their state changes: scans while a module is
  /// out of reach, nothing otherwise.
  void update(){
    final wanted=passiveSupported&&bluetoothOn&&_links.any((l)=>l.remembered&&l.state==LoraLinkState.outOfReach);
    if(wanted&&_every==null){
      _every=Timer.periodic(scanEvery,(_)=>unawaited(_scanOnce()));
      unawaited(_scanOnce());
    }else if(!wanted&&_every!=null){
      _every?.cancel(); _every=null;
      unawaited(_stopScan());
    }
  }

  /// An announce heard: the module out of reach with this identifier is
  /// joined at once.
  void advert(String deviceId){
    for(final l in List.of(_links)){
      if(l.state!=LoraLinkState.outOfReach||l.deviceId==null||l.deviceId!.toLowerCase()!=deviceId.toLowerCase())continue;
      l.log('module entendu : connexion');
      unawaited(_stopScan());
      l.heard();
    }
  }

  Future<void> _scanOnce() async {
    if(_scanning||userScanning||!bluetoothOn)return;
    final services={for(final l in _links)if(l.remembered&&l.state==LoraLinkState.outOfReach)l.bleService}.toList();
    if(services.isEmpty)return;
    testScans++;
    if(testMode)return;
    _scanning=true;
    try{
      await _scanSub?.cancel();
      _scanSub=UniversalBle.scanStream.listen((d)=>advert(d.deviceId));
      await UniversalBle.startScan(scanFilter:ScanFilter(withServices:services),
        platformConfig:PlatformConfig(android:AndroidOptions(scanMode:AndroidScanMode.lowPower)));
      await Future<void>.delayed(scanFor);
    }catch(e){
      for(final l in _links){if(l.state==LoraLinkState.outOfReach)l.log('écoute Bluetooth : $e');}
    }finally{
      await _stopScan();
    }
  }

  Future<void> _stopScan() async {
    if(!_scanning)return;
    _scanning=false;
    await _scanSub?.cancel(); _scanSub=null;
    // A search of Outils started meanwhile keeps its scan.
    if(!userScanning&&!testMode){try{await UniversalBle.stopScan();}catch(_){}}
  }

  @visibleForTesting
  void resetForTest(){
    _every?.cancel(); _every=null; _scanning=false; bluetoothOn=true; userScanning=false;
    passiveOverride=null; testScans=0;
  }

  @visibleForTesting
  Future<void> dispose() async {await _avail?.cancel();_avail=null;_started=false;}
}
