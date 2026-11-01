/// Channel between the application and the car screen with tabs (lot 17):
/// see car_screen.dart and the plugin `third_party/sarcade_car`.
///
/// - while Android Auto shows SARCADE (`active` from the plugin), the data
///   are written every few seconds, only when they changed;
/// - the actions of the driver wait in the plugin until they are taken
///   here (`actions` from the plugin, at start, and after each write), then
///   applied by [applyCarAction].
///
/// Android only; nothing happens elsewhere.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'car_screen.dart';

const carScreenChannel=MethodChannel('org.sarcade.car/screen');

/// Interval of the writes while the car shows SARCADE.
const carScreenRefresh=Duration(seconds:3);

class CarScreenBridge {
  /// Current data of the application; null when it cannot tell yet.
  final CarScreenInput? Function() read;
  final CarScreenActions actions;
  final MethodChannel channel;
  /// False on the platforms without Android Auto (tests may force it).
  final bool enabled;
  CarScreenBridge({required this.read,required this.actions,this.channel=carScreenChannel,bool? enabled})
    : enabled=enabled??(!kIsWeb&&defaultTargetPlatform==TargetPlatform.android);

  bool _active=false, _draining=false, _started=false;
  Timer? _timer;
  String? _last;

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
    _active=on;
    if(on){
      _timer??=Timer.periodic(carScreenRefresh,(_)=>unawaited(push()));
      unawaited(push());
    }else{
      _timer?.cancel();
      _timer=null;
    }
  }

  /// Writes the data when they changed since the last write.
  Future<void> push({bool force=false}) async {
    if(!enabled)return;
    final input=read();
    if(input==null)return;
    final json=jsonEncode(carSnapshot(input));
    if(!force&&json==_last)return;
    try{
      await channel.invokeMethod<void>('update',json);
      _last=json;
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
