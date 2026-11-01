/// ADS-B on the map (module ADRASEC, step 1, 1 Nov 2026). While the
/// « Aéronefs » layer is shown, the application tells the server the box of
/// its map every minute; the server asks OpenSky (30 s at least) and
/// broadcasts the aircraft (``adsb.updated``). Layer hidden: the server is
/// told at once, OpenSky is no longer asked for this terminal.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../services/sarcade_api.dart';
import 'adsb_models.dart';

/// The box sent to the server: the visible map.
typedef AdsbBox=({double south,double west,double north,double east});

class AdsbController extends ChangeNotifier {
  final SarcadeApi api; final String eventId, deviceId;
  final AdsbBox? Function() box;
  AdsbController({required this.api,required this.eventId,required this.deviceId,required this.box});

  bool _on=false;
  bool get on=>_on;
  List<Aircraft> aircraft=const [];
  DateTime? updatedAt;
  /// False when the server has no OpenSky identifiers.
  bool? serverEnabled;
  String? error;
  Timer? _timer;
  final Set<String> _alerted={};
  /// Called once per new emergency squawk (aircraft and code).
  void Function(Aircraft)? onEmergency;

  Future<void> setOn(bool v) async {
    if(v==_on)return;
    _on=v; notifyListeners();
    _timer?.cancel();
    if(v){
      await _watch();
      _timer=Timer.periodic(const Duration(seconds:60),(_)=>unawaited(_watch()));
    }else{
      aircraft=const []; notifyListeners();
      final b=box();
      if(b!=null){
        try{await api.adsbWatch(eventId,deviceId,south:b.south,west:b.west,north:b.north,east:b.east,on:false);}catch(_){/* expires by itself */}
      }
    }
  }

  /// After a large move of the map, without waiting for the minute.
  Future<void> mapMoved() async {if(_on)await _watch();}

  Future<void> _watch() async {
    final b=box(); if(b==null)return;
    try{
      final j=await api.adsbWatch(eventId,deviceId,south:b.south,west:b.west,north:b.north,east:b.east);
      serverEnabled=j['enabled']==true; error=null;
      if(j['time']!=null)_take(j);
    }catch(e){error='$e';}
    notifyListeners();
  }

  /// Realtime events of the event.
  void onRealtime(String type,Object? data){
    if(!_on)return;
    if(type=='adsb.updated'){_take(data);notifyListeners();}
  }

  void _take(Object? data){
    aircraft=aircraftList(data);
    updatedAt=DateTime.now();
    for(final a in aircraft){
      if(a.urgent&&_alerted.add('${a.icao24}:${a.squawk}'))onEmergency?.call(a);
    }
  }

  @override void dispose(){_timer?.cancel();super.dispose();}
}
