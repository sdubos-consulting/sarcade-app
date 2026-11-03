/// What the car sends to the server for the field (lot 24, sub-project
/// car24), apart from the messages and the move orders that go through the
/// same objects as the phone (see car_screen.dart):
/// - status of the operator in one touch (card « Android Auto : statut en
///   un appui »): PUT /events/{id}/devices/{device}/status, else queued for
///   /sync (object « operator_status ») when the server cannot be reached;
/// - « Signal entendu ici » (card « Android Auto : « Signal entendu ici »
///   (SATER) »): listening point, map_feature « listening » through /sync,
///   cancelled within 10 s;
///
/// The phone and PC side (status shown to the PCO…) is not here: this file
/// only sends. Pure Dart; HTTP client of the application (Cloudflare Access),
/// a MockClient in the tests.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

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

  /// [client]: the Cloudflare Access client of the application by default.
  CarField({required this.baseUrl,required this.eventId,required this.me,required this.queue,
      http.Client Function()? client,DateTime Function()? clock})
    : _newClient=client??AccessHttpClient.new,clock=clock??DateTime.now;

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

  void dispose(){
    _client?.close();
    _client=null;
  }
}
