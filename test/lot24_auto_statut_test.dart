// Android Auto, lot 24:
// - card « Android Auto : statut en un appui »: PUT …/status with its
//   time, queued for /sync (operator_status) without network, my status
//   shown in the car, his status in the card of an operator;
// - card « Android Auto : arrivée détectée près du point d'un ordre »:
//   « near » within 100 m of the point of an accepted order, « Oui » sets
//   the order to « Arrivé » and the status to « Sur place ».
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/car/car_field.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/features/orders/move_orders.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/position.dart';

final now=DateTime.utc(2026,11,3,9,0);
const point=LatLng(48.80,1.95);

MoveOrder order(String id,String status)=>MoveOrder({'id':id,'event_id':'e','target_id':'TEL-1','created_by':'PCO','status':status,
  'destination':{'lat':point.latitude,'lon':point.longitude,'label':'P2'},'updated_at':now.toIso8601String()});

class Sent {
  final List<http.Request> requests=[];
  final List<Map<String,dynamic>> queued=[];
}

CarField field(Sent sent,{int status=200,bool offline=false})=>CarField(baseUrl:'https://s/',eventId:'e',me:'TEL-1',clock:()=>now,
  client:()=>MockClient((r) async {
    sent.requests.add(r);
    if(offline)throw http.ClientException('offline');
    return http.Response(jsonEncode({'changed':true}),status);
  }),
  queue:({required String objectId,required String objectType,required Map<String,dynamic> payload,String action='create'}) async =>
    sent.queued.add({'object_id':objectId,'object_type':objectType,'action':action,'payload':payload}));

CarScreenInput input({CarField? f,LatLng? here,List<MoveOrder> orders=const [],Map<String,Map<String,dynamic>> devices=const {}})=>CarScreenInput(
  me:'TEL-1',eventId:'e',now:now,here:here,field:f,orders:orders,devices:devices,
  positions:[SarcadePosition(id:'p',eventId:'e',deviceId:'TEL-2',lat:48.81,lon:1.95,time:now)]);

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>S.setLanguage('fr'));

  group('status in one touch',(){
    test('PUT …/status with its time',() async {
      final sent=Sent(), f=field(sent);
      await applyCarAction(const CarAction('status',{'status':'en_route'}),input(f:f),
        CarScreenActions(order:(o,s) async {},ack:(a,m) async {},send:(m) async {},sos:() async {},sosEnd:() async {}));
      final r=sent.requests.single;
      expect(r.method,'PUT');
      expect(r.url.toString(),'https://s/api/v0.1/events/e/devices/TEL-1/status');
      expect(jsonDecode(r.body),{'status':'en_route','at':'2026-11-03T09:00:00.000Z','actor_id':'TEL-1'});
      expect(sent.queued,isEmpty);
      expect(f.myStatus(null),'en_route');
    });

    test('without network: queued for /sync, the most recent time wins there',() async {
      final sent=Sent();
      await field(sent,offline:true).setStatus('pause');
      expect(sent.queued.single,{'object_id':'TEL-1','object_type':'operator_status','action':'update',
        'payload':{'device_id':'TEL-1','status':'pause','at':'2026-11-03T09:00:00.000Z'}});
      // Server error: queued too; refused (422): not.
      final again=Sent();
      await field(again,status:503).setStatus('disponible');
      await field(again,status:422).setStatus('disponible');
      expect(again.queued.length,1);
    });

    test('unknown status ignored',() async {
      final sent=Sent();
      await field(sent).setStatus('dodo');
      expect(sent.requests,isEmpty);
    });

    test('my status: the one chosen here unless the server knows a newer one',() async {
      final f=field(Sent());
      expect(f.myStatus({'operator_status':'pause','operator_status_at':'2026-11-03T08:00:00Z'}),'pause');
      await f.setStatus('en_route');
      expect(f.myStatus({'operator_status':'pause','operator_status_at':'2026-11-03T08:00:00Z'}),'en_route');
      expect(f.myStatus({'operator_status':'disponible','operator_status_at':'2026-11-03T09:05:00Z'}),'disponible');
      final snap=carSnapshot(input(f:f));
      expect(snap['me'],{'status':'en_route'});
      expect(carLabels()['status.sur_place'],'Sur place');
      expect(carLabels()['myStatus'],'Mon statut');
    });

    test('his status in the card of an operator',(){
      final t=carTeam(input(devices:{'TEL-2':{'operator_status':'en_route'}})).single;
      expect(t['status'],'En route');
      expect(carTeam(input(devices:{'TEL-2':{'status':'ok'}})).single.containsKey('status'),isFalse);
    });
  });

  group('arrival detected',(){
    test('« near » within 100 m of the point of an accepted order only',(){
      List<Object?> near(LatLng here,String status)=>[for(final o in carSnapshot(input(here:here,orders:[order('o1',status)]))['orders'] as List)(o as Map)['near']];
      expect(near(const LatLng(48.8008,1.95),'accepted'),[true]);
      expect(near(const LatLng(48.8012,1.95),'accepted'),[null]);
      expect(near(point,'sent'),[null]);
      expect(carSnapshot(input(orders:[order('o1','accepted')]))['orders'],isNot(contains(containsPair('near',true))));
    });

    test('« near » reaches the car at once',(){
      final a=carUrgentKey(carSnapshot(input(here:const LatLng(48.81,1.95),orders:[order('o1','accepted')])));
      final b=carUrgentKey(carSnapshot(input(here:point,orders:[order('o1','accepted')])));
      expect(a,isNot(b));
    });

    test('« Oui »: the order arrived, my status « Sur place »',() async {
      final sent=Sent(), f=field(sent), done=<String>[];
      final act=CarScreenActions(order:(o,s) async=>done.add('${o.id} $s'),ack:(a,m) async {},send:(m) async {},sos:() async {},sosEnd:() async {});
      await applyCarAction(const CarAction('arrival',{'id':'o1'}),input(f:f,here:point,orders:[order('o1','accepted')]),act);
      await applyCarAction(const CarAction('arrival',{'id':'o2'}),input(f:f,here:point,orders:[order('o2','sent')]),act);
      expect(done,['o1 arrived']);
      expect(jsonDecode(sent.requests.single.body)['status'],'sur_place');
    });

    test('texts of the question',(){
      expect(carLabels()['arrivalTitle'],'Vous êtes arrivé à {point}');
      expect(carLabels()['arrivalAsk'],'Signaler l’arrivée ?');
      S.setLanguage('en');
      expect(carLabels()['later'],'Later');
    });
  });
}
