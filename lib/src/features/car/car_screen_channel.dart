/// Channel between the application and the car screen with tabs (lot 17):
/// see car_screen.dart and the plugin `third_party/sarcade_car`.
///
/// - while Android Auto shows SARCADE (`active` from the plugin), the data
///   are checked every few seconds and written as [push] says (lot 20);
/// - the actions of the driver wait in the plugin until they are taken
///   here (`actions` from the plugin, at start, and after each write), then
///   applied by [applyCarAction].
///
/// Android Auto, and CarPlay once Apple grants its entitlement (step 2b);
/// nothing happens elsewhere.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'car_screen.dart';

const carScreenChannel=MethodChannel('org.sarcade.car/screen');

/// Interval of the checks while the car shows SARCADE.
const carScreenRefresh=Duration(seconds:3);
/// Lot 20 (card « Android Auto : l'écran clignote… », choices 2 and 3):
/// when only distances or ages changed, written at most this often; a new
/// message, order or distress is written at once (see [carUrgentKey]).
const carScreenMinorRefresh=Duration(seconds:15);
/// Written again at least this often, unchanged, so that the car does not
/// take the data for old (« Données de 10:42 » after 2 minutes).
const carScreenKeepAlive=Duration(seconds:60);

class CarScreenBridge {
  /// Current data of the application; null when it cannot tell yet.
  final CarScreenInput? Function() read;
  final CarScreenActions actions;
  final MethodChannel channel;
  /// False on the platforms without Android Auto nor CarPlay (tests may force it).
  final bool enabled;
  /// Clock of the writes (tests).
  final DateTime Function() clock;
  /// Called when the car starts showing SARCADE (lot 20): the application
  /// fetches the move orders at once, without waiting for the realtime
  /// channel, often cut while the phone sleeps in the car.
  final VoidCallback? onActive;
  CarScreenBridge({required this.read,required this.actions,this.channel=carScreenChannel,bool? enabled,DateTime Function()? clock,this.onActive})
    : enabled=enabled??(!kIsWeb&&(defaultTargetPlatform==TargetPlatform.android||defaultTargetPlatform==TargetPlatform.iOS)),
      clock=clock??DateTime.now;

  bool _active=false, _draining=false, _started=false;
  Timer? _timer;
  String? _last, _lastKey;
  DateTime? _lastAt;

  /// True while a car session shows SARCADE.
  bool get active=>_active;

  void start(){
    if(!enabled||_started)return;
    _started=true;
    channel.setMethodCallHandler(_onCall);
    unawaited(_init());
  }

  Future<void> _init() async {
    try{
      _setActive(await channel.invokeMethod<bool>('state')??false);
    }catch(e){
      debugPrint('SARCADE car screen unavailable: $e');
      return;
    }
    await drain();
  }

  Future<Object?> _onCall(MethodCall call) async {
    switch(call.method){
      case 'active': _setActive(call.arguments==true);
      case 'actions': await drain();
    }
    return null;
  }

  void _setActive(bool on){
    final was=_active;
    _active=on;
    if(on&&!was)onActive?.call();
    if(on){
      _timer??=Timer.periodic(carScreenRefresh,(_)=>unawaited(push()));
      unawaited(push(force:true));
    }else{
      _timer?.cancel();
      _timer=null;
    }
  }

  /// Writes the data: at once when something that counts changed (message,
  /// order, distress), at most every 15 s when only distances or ages
  /// changed, every minute when nothing changed (lot 20).
  Future<void> push({bool force=false}) async {
    if(!enabled)return;
    final input=read();
    if(input==null)return;
    final snap=carSnapshot(input);
    final body=jsonEncode({...snap}..remove('at'));
    final key=carUrgentKey(snap);
    final now=clock();
    final since=_lastAt==null?null:now.difference(_lastAt!);
    final write=force||since==null||key!=_lastKey||since>=carScreenKeepAlive||(body!=_last&&since>=carScreenMinorRefresh);
    if(!write)return;
    try{
      await channel.invokeMethod<void>('update',jsonEncode(snap));
      _last=body; _lastKey=key; _lastAt=now;
    }catch(e){
      debugPrint('SARCADE car screen not updated: $e');
    }
  }

  /// Takes and applies the actions done in the car, then shows the result.
  Future<void> drain() async {
    if(!enabled||_draining)return;
    _draining=true;
    var applied=false;
    try{
      final raw=await channel.invokeMethod<String>('takeActions');
      final list=parseCarActions(raw==null||raw.isEmpty?null:jsonDecode(raw));
      for(final a in list){
        final input=read();
        if(input==null)break;
        try{
          await applyCarAction(a,input,actions);
          applied=true;
        }catch(e){
          debugPrint('SARCADE car action ${a.type} not applied: $e');
        }
      }
    }catch(e){
      debugPrint('SARCADE car actions not read: $e');
    }finally{
      _draining=false;
    }
    if(applied)await push();
  }

  void dispose(){
    _timer?.cancel();
    _timer=null;
    if(_started)channel.setMethodCallHandler(null);
  }
}
