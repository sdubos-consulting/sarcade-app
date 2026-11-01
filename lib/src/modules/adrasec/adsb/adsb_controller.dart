/// ADS-B on the map (module ADRASEC, step 1, 1 Nov 2026). While the
/// « Aéronefs » layer is shown, the application tells the server the box of
/// its map every minute; the server asks OpenSky (30 s at least) and
/// broadcasts the aircraft (``adsb.updated``). Layer hidden: the server is
/// told at once, OpenSky is no longer asked for this terminal.
///
/// Uncluttered view (card validated 1 Nov 2026, 8 h 21): filters kept on the
/// device. Lot 17 (1 Nov 2026, 11 h 34): the sheet of one aircraft floats
/// over the map; no trace by default; several aircraft followed at once,
/// each with its route (30 min, read from the server), kept when the sheet
/// closes; the map stays centred on the last one followed until it is moved
/// by hand.
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
  /// Filtered aircraft; the one of the sheet and those followed stay.
  List<Aircraft> get shown=>[for(final a in aircraft)if(_filters.shows(a)||a.icao24==selectedId||followed.contains(a.icao24))a];
  int get hiddenCount=>aircraft.length-shown.length;

  /// Aircraft of the floating sheet (one at a time).
  String? selectedId;
  Aircraft? get selected=>selectedId==null?null:aircraft.where((a)=>a.icao24==selectedId).firstOrNull;

  /// Aircraft followed (order of « Suivre ») and their routes.
  final Set<String> followed={};
  final Map<String,List<LatLng>> routes={};
  bool isFollowed(String id)=>followed.contains(id);
  /// Last aircraft followed, the map stays on it until moved by hand.
  String? centredId;
  Timer? _centreTimer;
  /// Moves the map onto an estimated position (set by the map page).
  void Function(LatLng)? onCentre;
  /// The aircraft followed changed: « Suivre ma vue » sends them to the TV.
  VoidCallback? onFollowedChanged;

  /// Server clock minus the clock of this device (estimated positions on
  /// the same reference as the TV).
  Duration clockOffset=Duration.zero;
  DateTime get serverNow=>DateTime.now().add(clockOffset);

  /// Opens (or replaces, or with null closes) the floating sheet; the
  /// aircraft followed stay followed.
  Future<void> select(Aircraft? a) async {
    selectedId=a?.icao24;
    notifyListeners();
  }

  /// « Suivre »: adds the aircraft, shows its route, centres the map on it.
  Future<void> follow(Aircraft a) async {
    followed.add(a.icao24);
    if(a.trail.length>1)routes[a.icao24]??=a.trail;
    centredId=a.icao24;
    _centreTimer?.cancel();
    _centreTimer=Timer.periodic(const Duration(seconds:2),(_)=>_centre());
    _centre();
    notifyListeners();
    onFollowedChanged?.call();
    await _readRoute(a.icao24);
  }

  /// « Ne plus suivre »: its route is removed.
  void unfollow(String id){
    if(!followed.remove(id))return;
    routes.remove(id);
    if(centredId==id)stopCentring(notify:false);
    notifyListeners();
    onFollowedChanged?.call();
  }

  /// « Ne plus suivre aucun avion »: every route is removed.
  void unfollowAll(){
    if(followed.isEmpty)return;
    followed.clear(); routes.clear();
    stopCentring(notify:false);
    notifyListeners();
    onFollowedChanged?.call();
  }

  /// The map moved by hand: no more centring, the routes stay.
  void stopCentring({bool notify=true}){
    if(centredId==null)return;
    centredId=null; _centreTimer?.cancel(); _centreTimer=null;
    if(notify)notifyListeners();
  }

  void _centre(){
    final id=centredId; if(id==null)return;
    final a=aircraft.where((x)=>x.icao24==id).firstOrNull;
    if(a!=null)onCentre?.call(aircraftEstimated(a,serverNow));
  }

  Future<void> _readRoute(String id) async {
    try{
      final t=await api.adsbTrack(eventId,id);
      if(followed.contains(id)&&t.length>1){routes[id]=t;notifyListeners();}
    }catch(_){/* the route already known stays */}
  }

  /// Settings pushed to a TV with the view: filters and aircraft followed.
  Map<String,dynamic> tvJson()=>{...filters.tvJson(),'aircraft_followed':followed.toList()};

  Future<void> setOn(bool v) async {
    if(v==_on)return;
    _on=v; notifyListeners();
    _timer?.cancel();
    if(v){
      await _watch();
      _timer=Timer.periodic(const Duration(seconds:60),(_)=>unawaited(_watch()));
    }else{
      aircraft=const []; selectedId=null; followed.clear(); routes.clear(); stopCentring(notify:false); notifyListeners();
      onFollowedChanged?.call();
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
    if(type=='adsb.updated'){_take(data);notifyListeners();for(final id in followed.toList())unawaited(_readRoute(id));}
  }

  void _take(Object? data){
    aircraft=aircraftList(data);
    updatedAt=DateTime.now();
    final now=data is Map?data['now']:null;
    if(now is num)clockOffset=Duration(milliseconds:(now*1000).round()-updatedAt!.millisecondsSinceEpoch);
    for(final a in aircraft){
      if(a.urgent&&_alerted.add('${a.icao24}:${a.squawk}'))onEmergency?.call(a);
    }
  }

  @override void dispose(){_timer?.cancel();_centreTimer?.cancel();super.dispose();}
}
