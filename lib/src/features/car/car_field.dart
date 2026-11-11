/// What the car sends to the server for the field (lot 24, sub-project
/// car24), apart from the messages and the move orders that go through the
/// same objects as the phone (see car_screen.dart):
/// - status of the operator in one touch (card « Android Auto : statut en
///   un appui »): PUT /events/{id}/devices/{device}/status, else queued for
///   /sync (object « operator_status ») when the server cannot be reached;
/// - « Signal entendu ici » (card « Android Auto : « Signal entendu ici »
///   (SATER) »): listening point, map_feature « listening » through /sync,
///   cancelled within 10 s;
/// - estimated time of arrival (card « Android Auto : heure d'arrivée
///   estimée envoyée au PCO »): PUT /events/{id}/move-orders/{order}/eta;
/// - texts read aloud by the car (answer of a remote, vigilance at the
///   destination, lot 24); weather at the destination (car_weather.dart).
///
/// The phone and PC side (status shown to the PCO…) is not here: this file
/// only sends. Pure Dart; HTTP client of the application (Cloudflare Access),
/// a MockClient in the tests.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../map/drawing/geometry.dart' show distanceM;
import '../remotes/remote.dart' show Remotes;
import 'car_remotes.dart';
import 'car_weather.dart';

import '../../access/access_manager.dart' show AccessHttpClient;

/// Statuses of an operator, in the order of the grid of the car (server:
/// sarcade lot 24, PUT …/status).
const carStatuses=['en_route','sur_place','disponible','pause'];

/// Colours of the statuses (same as the PCO map and the TV, contract of lot 24).
const carStatusColors={'en_route':0xFFFFB020,'sur_place':0xFF4ADE80,'disponible':0xFF3DD6F5,'pause':0xFF9AA3AD};

/// Queues one synchronisation operation (OfflineSyncService.queue).
typedef CarQueue=Future<void> Function({required String objectId,required String objectType,required Map<String,dynamic> payload,String action});

class CarField {
  final String baseUrl, eventId, me;
  final CarQueue queue;
  final http.Client Function() _newClient;
  http.Client? _client;
  /// Clock (tests).
  final DateTime Function() clock;

  /// Last status chosen in the car, and when; null before the first one.
  String? status;
  DateTime? statusAt;

  /// Remotes of relays used from the car (lot 24).
  late final CarRemoteWatch remotes;

  /// Weather and vigilance at the destination (lot 24).
  late final CarWeather weather;

  /// [client]: the Cloudflare Access client of the application by default;
  /// [remotes]: those declared on this device; [pointWeather]: forecast of
  /// a place (SarcadeApi.pointWeather).
  CarField({required this.baseUrl,required this.eventId,required this.me,required this.queue,
      http.Client Function()? client,DateTime Function()? clock,Remotes? remotes,CarFetchWeather? pointWeather})
    : _newClient=client??AccessHttpClient.new,clock=clock??DateTime.now{
    this.remotes=CarRemoteWatch(remotes??Remotes.instance,say:say);
    weather=CarWeather(fetch:pointWeather,say:say);
  }

  /// Last text to read aloud in the car, with an identifier new for each
  /// one (the car reads each once).
  ({String id,String text,DateTime at})? said;
  int _said=0;

  void say(String text){
    final at=clock().toUtc();
    said=(id:'${at.microsecondsSinceEpoch}-${_said++}',text:text,at:at);
  }

  http.Client get client=>_client??=_newClient();

  String get _base=>baseUrl.trim().replaceFirst(RegExp(r'/+$'),'');
  Uri _uri(String path)=>Uri.parse('$_base/api/v0.1/events/${Uri.encodeComponent(eventId)}$path');
  static const _json={'content-type':'application/json'};

  /// My status: the last one chosen here, unless the server knows a newer
  /// one (chosen on the phone or the PC: [device] of GET …/devices).
  String? myStatus(Map<String,dynamic>? device){
    final server=device?['operator_status'];
    final serverAt=DateTime.tryParse('${device?['operator_status_at']}');
    if(statusAt!=null&&(serverAt==null||!serverAt.isAfter(statusAt!)))return status;
    return server is String&&carStatuses.contains(server)?server:null;
  }

  /// Status in one touch: sent at once with its time; queued for /sync
  /// when the server cannot be reached (the most recent time wins there).
  /// A status refused by the server (422, 404) is not queued.
  Future<void> setStatus(String? value) async {
    if(value!=null&&!carStatuses.contains(value))return;
    final at=clock().toUtc();
    status=value; statusAt=at;
    final iso=at.toIso8601String();
    try{
      final r=await client.put(_uri('/devices/${Uri.encodeComponent(me)}/status'),headers:_json,
        body:jsonEncode({'status':value,'at':iso,'actor_id':me})).timeout(const Duration(seconds:8));
      if(r.statusCode==200)return;
      if(r.statusCode==404||r.statusCode==422)return;
    }catch(_){/* no network: queued below */}
    await queue(objectId:me,objectType:'operator_status',action:'update',payload:{'device_id':me,'status':value,'at':iso});
  }

  /// Time given to cancel a listening point (« Annuler », server: 10 s
  /// after heard_at, plus 5 s of margin).
  static const listeningCancel=Duration(seconds:10);

  /// Listening points sent from this car and when they were heard.
  final Map<String,DateTime> _heard={};

  /// « Signal entendu ici » (lot 24): a listening point at [at], heard at
  /// [heardAt], with the heading, speed and accuracy of the vehicle when
  /// known; map_feature « listening » queued for /sync (sent at once,
  /// kept in the Outbox without network). [id] chosen by the car, so that
  /// « Annuler » names it.
  Future<void> sendListening({required String id,required LatLng at,required DateTime heardAt,
      double? headingDeg,double? speedMps,double? accuracyM}) async {
    if(id.isEmpty||_heard.containsKey(id))return;
    final heard=heardAt.toUtc();
    _heard[id]=heard;
    final iso=heard.toIso8601String();
    await queue(objectId:id,objectType:'map_feature',action:'create',payload:{
      'id':id,'event_id':eventId,'kind':'listening','points':[[at.latitude,at.longitude]],
      'listening':{'heard_at':iso,
        if(headingDeg!=null&&headingDeg.isFinite)'heading_deg':((headingDeg%360)+360)%360,
        if(speedMps!=null&&speedMps.isFinite&&speedMps>=0&&speedMps<=150)'speed_mps':speedMps,
        if(accuracyM!=null&&accuracyM.isFinite&&accuracyM>=0)'accuracy_m':accuracyM},
      'created_by':me,'updated_by':me,'updated_at':iso,
    });
  }

  /// « Annuler » within 10 s: the listening point deleted (refused by the
  /// server beyond 10 s + 5 s; not sent at all here after 15 s).
  Future<bool> cancelListening(String id) async {
    final heard=_heard[id];
    final now=clock().toUtc();
    if(heard==null||now.difference(heard)>listeningCancel+const Duration(seconds:5))return false;
    _heard.remove(id);
    await queue(objectId:id,objectType:'map_feature',action:'delete',
      payload:{'id':id,'event_id':eventId,'updated_by':me,'updated_at':now.toIso8601String()});
    return true;
  }

  // --- Estimated time of arrival (lot 24) ----------------------------------

  /// Order followed since « Y aller » towards its point; null: none.
  String? etaOrder;
  final List<({DateTime t,LatLng p})> _track=[];
  DateTime? _etaSentAt, _etaSent;

  /// ETA sent at least this often while the order is followed…
  static const etaEvery=Duration(minutes:2);
  /// …and at once when it moved by more than this.
  static const etaGap=Duration(minutes:3);

  /// « Y aller » towards the point of order [id] (choice 1).
  void followEta(String id){
    if(id.isEmpty||id==etaOrder)return;
    etaOrder=id; _etaSentAt=null; _etaSent=null;
  }

  void stopEta(){etaOrder=null;_etaSentAt=null;_etaSent=null;}

  /// Called every few seconds while the car shows SARCADE: remembers the
  /// position, and sends the estimate of the followed order when due
  /// (choice 2). Stops when the order is no longer accepted (arrived,
  /// refused, cancelled, gone: choice 4; the server clears the ETA itself).
  Future<void> etaTick({required String? status,required LatLng? destination,required LatLng? here}) async {
    final now=clock().toUtc();
    if(here!=null)carTrackAdd(_track,here,now);
    final id=etaOrder;
    if(id==null)return;
    if(status==null||const {'arrived','refused','cancelled'}.contains(status)){stopEta();return;}
    if(status!='accepted'||here==null||destination==null)return;
    final remaining=distanceM(here,destination);
    final eta=carEstimate(remaining,carAverageSpeed(_track,now),now);
    if(eta==null)return;
    final due=_etaSentAt==null||now.difference(_etaSentAt!)>=etaEvery||(_etaSent!=null&&eta.difference(_etaSent!).abs()>etaGap);
    if(!due)return;
    _etaSentAt=now; _etaSent=eta;
    try{
      final r=await client.put(_uri('/move-orders/${Uri.encodeComponent(id)}/eta'),headers:_json,
        body:jsonEncode({'device_id':me,'eta':eta.toIso8601String(),'remaining_m':remaining.round()})).timeout(const Duration(seconds:8));
      // Order no longer ours or no longer accepted: stop.
      if(r.statusCode==403||r.statusCode==404)stopEta();
      if(r.statusCode!=200&&r.statusCode!=403&&r.statusCode!=404)_etaSentAt=null;
    }catch(_){
      _etaSentAt=null; // no network: tried again at the next tick
    }
  }

  void dispose(){
    _client?.close();
    _client=null;
  }
}

/// Positions kept for the average speed: one every 10 s at most, over the
/// last [carSpeedWindow].
const carSpeedWindow=Duration(minutes:5);

void carTrackAdd(List<({DateTime t,LatLng p})> track,LatLng p,DateTime now){
  if(track.isNotEmpty&&now.difference(track.last.t)<const Duration(seconds:10))return;
  track.add((t:now,p:p));
  track.removeWhere((x)=>now.difference(x.t)>carSpeedWindow);
}

/// Average speed of the last minutes (m/s): distance driven over time, at
/// least one minute of track; null when unknown.
double? carAverageSpeed(List<({DateTime t,LatLng p})> track,DateTime now){
  final recent=track.where((x)=>now.difference(x.t)<=carSpeedWindow).toList();
  if(recent.length<2)return null;
  final seconds=recent.last.t.difference(recent.first.t).inMilliseconds/1000;
  if(seconds<60)return null;
  var d=0.0;
  for(var k=1;k<recent.length;k++){d+=distanceM(recent[k-1].p,recent[k].p);}
  return d/seconds;
}

/// Time of arrival: remaining distance at the average speed; null when
/// the vehicle hardly moves (under 1 m/s) or beyond the 48 h the server
/// accepts.
DateTime? carEstimate(double remainingM,double? speedMps,DateTime now){
  if(speedMps==null||speedMps<1)return null;
  final eta=now.add(Duration(seconds:(remainingM/speedMps).round()));
  return eta.difference(now)>const Duration(hours:47)?null:eta.toUtc();
}
