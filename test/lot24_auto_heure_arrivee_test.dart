// Android Auto, lot 24, card « Android Auto : heure d'arrivée estimée
// envoyée au PCO »: after « Y aller » towards the point of an order, the
// remaining distance at the average speed of the last minutes; PUT …/eta
// every 2 minutes or when it moved by more than 3 minutes; stopped at the
// arrival or the cancellation of the order.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/car/car_field.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/features/orders/move_orders.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

final t0=DateTime.utc(2026,11,3,8,0);
const dest=LatLng(48.90,1.95);

MoveOrder order(String status)=>MoveOrder({'id':'o1','event_id':'e','target_id':'TEL-1','created_by':'PCO','status':status,
  'destination':{'lat':dest.latitude,'lon':dest.longitude,'label':'P2'},'updated_at':t0.toIso8601String()});

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>S.setLanguage('fr'));

  late DateTime now;
  late List<http.Request> sent;
  late int answer;
  CarField field()=>CarField(baseUrl:'https://s',eventId:'e',me:'TEL-1',clock:()=>now,
    client:()=>MockClient((r) async {sent.add(r);return http.Response('{}',answer);}),
    queue:({required String objectId,required String objectType,required Map<String,dynamic> payload,String action='create'}) async {});
  setUp((){now=t0;sent=[];answer=200;});
  final act=CarScreenActions(order:(o,s) async {},ack:(a,m) async {},send:(m) async {},sos:() async {},sosEnd:() async {});

  CarScreenInput input(CarField f,LatLng here,{String status='accepted'})=>CarScreenInput(me:'TEL-1',eventId:'e',now:now,here:here,field:f,
    orders:[order(status)]);

  /// Drives north at 15 m/s (54 km/h) for [seconds], a tick every 10 s.
  Future<LatLng> drive(CarField f,LatLng from,int seconds,{String status='accepted'}) async {
    var p=from;
    for(var s=0;s<seconds;s+=10){
      now=now.add(const Duration(seconds:10));
      p=LatLng(p.latitude+150/111195,p.longitude);
      await carFieldTick(input(f,p,status:status));
    }
    return p;
  }

  test('average speed over at least one minute; estimate under 1 m/s refused',(){
    final track=<({DateTime t,LatLng p})>[];
    carTrackAdd(track,const LatLng(48.80,1.95),t0);
    carTrackAdd(track,const LatLng(48.801,1.95),t0.add(const Duration(seconds:5)));
    expect(track.length,1,reason:'one position every 10 s at most');
    carTrackAdd(track,const LatLng(48.80,1.95),t0.add(const Duration(seconds:30)));
    expect(carAverageSpeed(track,t0.add(const Duration(seconds:30))),isNull,reason:'less than a minute');
    expect(carEstimate(1000,0.5,t0),isNull);
    expect(carEstimate(9000,15,t0),t0.add(const Duration(minutes:10)));
  });

  test('nothing before « Y aller »; then PUT …/eta with the remaining distance',() async {
    final f=field();
    var p=await drive(f,const LatLng(48.80,1.95),120);
    expect(sent,isEmpty);
    await applyCarAction(const CarAction('go',{'id':'o1'}),input(f,p),act);
    p=await drive(f,p,10);
    final r=sent.single;
    expect(r.method,'PUT');
    expect(r.url.toString(),'https://s/api/v0.1/events/e/move-orders/o1/eta');
    final body=jsonDecode(r.body) as Map;
    expect(body['device_id'],'TEL-1');
    final remaining=body['remaining_m'] as int;
    expect(remaining,closeTo(9000,600));
    final eta=DateTime.parse(body['eta'] as String);
    expect(eta.difference(now).inSeconds,closeTo(remaining/15,30));
  });

  test('every 2 minutes, or at once when it moved by more than 3 minutes',() async {
    final f=field();
    var p=await drive(f,const LatLng(48.80,1.95),120);
    await applyCarAction(const CarAction('go',{'id':'o1'}),input(f,p),act);
    p=await drive(f,p,10);
    expect(sent.length,1);
    p=await drive(f,p,100);
    expect(sent.length,1,reason:'same pace, less than 2 minutes');
    p=await drive(f,p,30);
    expect(sent.length,2,reason:'2 minutes');
    // Stopped in a traffic jam for 4 minutes: the estimate drifts by more
    // than 3 minutes before the next 2 minutes are up, or it is withheld
    // under 1 m/s.
    for(var s=0;s<90;s+=10){now=now.add(const Duration(seconds:10));await carFieldTick(input(f,p));}
    expect(sent.length,3);
  });

  test('stopped at the arrival or the cancellation of the order',() async {
    final f=field();
    var p=await drive(f,const LatLng(48.80,1.95),120);
    await applyCarAction(const CarAction('go',{'id':'o1'}),input(f,p),act);
    p=await drive(f,p,10);
    expect(sent.length,1);
    p=await drive(f,p,10,status:'arrived');
    expect(f.etaOrder,isNull);
    now=now.add(const Duration(minutes:3));
    await carFieldTick(input(f,p));
    expect(sent.length,1);
    await applyCarAction(const CarAction('go',{'id':'o1'}),input(f,p),act);
    await drive(f,p,10,status:'cancelled');
    expect(f.etaOrder,isNull);
  });

  test('order not accepted yet: followed, sent once accepted',() async {
    final f=field();
    var p=await drive(f,const LatLng(48.80,1.95),120,status:'sent');
    await applyCarAction(const CarAction('go',{'id':'o1'}),input(f,p,status:'sent'),act);
    p=await drive(f,p,30,status:'sent');
    expect(sent,isEmpty);
    await drive(f,p,10);
    expect(sent.length,1);
  });
}
