/// ADS-B on the map (module ADRASEC, step 1, 1 Nov 2026). While the
/// « Aéronefs » layer is shown, the application tells the server the box of
/// its map every minute; the server asks OpenSky (30 s at least) and
/// broadcasts the aircraft (``adsb.updated``). Layer hidden: the server is
/// told at once, OpenSky is no longer asked for this terminal.
///
/// Uncluttered view (card validated 1 Nov 2026, 8 h 21): filters kept on the
/// device, one aircraft selected at a time with its whole trace (30 min,
/// read from the server), « Suivre » keeps the map on it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../offline/local_store.dart';
import '../../../services/sarcade_api.dart';
import 'adsb_models.dart';

/// The box sent to the server: the visible map.
typedef AdsbBox=({double south,double west,double north,double east});

const adsbFiltersKey='adsb_filters';

class AdsbController extends ChangeNotifier {
  final SarcadeApi api; final String eventId, deviceId;
  final AdsbBox? Function() box;
  final LocalStore? store;
  AdsbController({required this.api,required this.eventId,required this.deviceId,required this.box,this.store}){
    final raw=store?.preference(adsbFiltersKey);
    if(raw!=null){try{_filters=AdsbFilters.fromJson(jsonDecode(raw));}catch(_){/* defaults */}}
  }

  bool _on=false;
  bool get on=>_on;
  /// Every aircraft received; [shown] applies the filters.
  List<Aircraft> aircraft=const [];
  DateTime? updatedAt;
  /// False when the server has no OpenSky identifiers.
  bool? serverEnabled;
  String? error;
  Timer? _timer;
  final Set<String> _alerted={};
  /// Called once per new emergency squawk (aircraft and code).
  void Function(Aircraft)? onEmergency;

  AdsbFilters _filters=const AdsbFilters();
  AdsbFilters get filters=>_filters;
  set filters(AdsbFilters f){
    if(f==_filters)return;
    _filters=f; notifyListeners();
    unawaited(store?.setPreference(adsbFiltersKey,jsonEncode(f.toJson())));
  }
  List<Aircraft> get shown=>[for(final a in aircraft)if(_filters.shows(a)||a.icao24==selectedId)a];
  int get hiddenCount=>aircraft.length-shown.length;

  String? selectedId;
  /// The map stays centred on the selected aircraft.
  bool follow=false;
  /// Whole known trace of the selected aircraft.
  List<LatLng> track=const [];
  Aircraft? get selected=>selectedId==null?null:aircraft.where((a)=>a.icao24==selectedId).firstOrNull;

  Future<void> select(Aircraft? a) async {
    selectedId=a?.icao24; follow=false; track=a?.trail??const [];
    notifyListeners();
    if(a!=null)await _readTrack();
  }

  void setFollow(bool v){follow=v;notifyListeners();}

  Future<void> _readTrack() async {
    final id=selectedId; if(id==null)return;
    try{
      final t=await api.adsbTrack(eventId,id);
      if(id==selectedId){track=t;notifyListeners();}
    }catch(_){/* the short trail stays */}
  }

  Future<void> setOn(bool v) async {
    if(v==_on)return;
    _on=v; notifyListeners();
    _timer?.cancel();
    if(v){
      await _watch();
      _timer=Timer.periodic(const Duration(seconds:60),(_)=>unawaited(_watch()));
    }else{
      aircraft=const []; selectedId=null; track=const []; follow=false; notifyListeners();
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
    if(type=='adsb.updated'){_take(data);notifyListeners();if(selectedId!=null)unawaited(_readTrack());}
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
