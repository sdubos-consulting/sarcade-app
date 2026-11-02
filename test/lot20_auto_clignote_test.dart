// Android Auto, lot 20 (card « Android Auto : l'écran clignote toutes les
// quelques secondes… », choices 1 to 5): rounded distances, the car written
// at once for what counts, at most every 15 s for the distances.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/features/car/car_screen_channel.dart';
import 'package:sarcade_app/src/features/orders/move_orders.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/message.dart';
import 'package:sarcade_app/src/models/poi.dart';

final now=DateTime.utc(2026,11,2,8,0);

MoveOrder order(String id,{String status='sent'})=>MoveOrder({
  'id':id,'target_id':'TEL-1','created_by':'PCO','status':status,'note':'',
  'destination':{'lat':48.83,'lon':1.95,'label':'P2'},'updated_at':'2026-11-02T07:59:00Z'});

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>S.setLanguage('fr'));

  test('distances by 50 m under 1 km, by 0,5 km beyond',(){
    expect(carDistance(21),'50 m');
    expect(carDistance(251),'250 m');
    expect(carDistance(276),'300 m');
    expect(carDistance(949),'950 m');
    expect(carDistance(980),'1 km');
    expect(carDistance(3010),'3 km');
    expect(carDistance(3336),'3,5 km');
    expect(carDistance(25200),'25 km');
    // A few metres of GPS noise: same text.
    const here=LatLng(48.80,1.95);
    expect(carAway(here,const LatLng(48.8301,1.95)),carAway(here,const LatLng(48.8299,1.9501)));
  });

  test('what counts: messages, orders, distress; not the distances',(){
    CarScreenInput at(LatLng here,{List<MoveOrder> orders=const [],bool sos=false,List<SarcadeMessage> messages=const []})=>CarScreenInput(
      me:'TEL-1',eventId:'e',now:now,here:here,orders:orders,inDistress:sos,messages:messages,
      pois:[SarcadePoi(id:'p1',eventId:'e',kind:'designated',lat:48.9,lon:1.95,createdAt:now,label:'PC',createdBy:'PCO')]);
    final a=carUrgentKey(carSnapshot(at(const LatLng(48.80,1.95))));
    expect(carUrgentKey(carSnapshot(at(const LatLng(48.75,1.95)))),a,reason:'only the distances moved');
    expect(carUrgentKey(carSnapshot(at(const LatLng(48.80,1.95),orders:[order('o1')]))),isNot(a));
    expect(carUrgentKey(carSnapshot(at(const LatLng(48.80,1.95),sos:true))),isNot(a));
    final m=SarcadeMessage(id:'m1',eventId:'e',senderId:'PCO',recipientIds:const ['user:TEL-1'],priority:'routine',body:'Allez',createdAt:now);
    expect(carUrgentKey(carSnapshot(at(const LatLng(48.80,1.95),messages:[m]))),isNot(a));
  });

  group('writes to the car',(){
    final messenger=TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<String> updates;
    Future<void> settle() async {for(var i=0;i<20;i++){await Future<void>.delayed(Duration.zero);}}

    setUp((){
      updates=[];
      messenger.setMockMethodCallHandler(carScreenChannel,(call) async {
        if(call.method=='update')updates.add(call.arguments as String);
        if(call.method=='takeActions')return '[]';
        return null;
      });
    });
    tearDown(()=>messenger.setMockMethodCallHandler(carScreenChannel,null));

    test('distances at most every 15 s, a new order at once, unchanged every minute',() async {
      var t=now, lat=48.80;
      var orders=<MoveOrder>[];
      final b=CarScreenBridge(enabled:true,clock:()=>t,
        read:()=>CarScreenInput(me:'TEL-1',eventId:'e',now:t,here:LatLng(lat,1.95),orders:orders,
          pois:[SarcadePoi(id:'p1',eventId:'e',kind:'designated',lat:48.90,lon:1.95,createdAt:now,label:'PC',createdBy:'PCO')]),
        actions:CarScreenActions(order:(o,s) async {},ack:(a,m) async {},send:(m) async {},sos:() async {},sosEnd:() async {}));
      await b.push();
      expect(updates,hasLength(1));
      // The car moves (« 11 km » becomes « 12 km »), 3 s later: not written.
      t=t.add(const Duration(seconds:3)); lat=48.79;
      await b.push();
      expect(updates,hasLength(1));
      // 15 s after the last write: written.
      t=now.add(const Duration(seconds:15));
      await b.push();
      expect(updates,hasLength(2));
      // A new order: written at once.
      t=t.add(const Duration(seconds:3)); orders=[order('o1')];
      await b.push();
      expect(updates,hasLength(3));
      expect((jsonDecode(updates.last) as Map)['orders'],hasLength(1));
      // Nothing changes: written again after a minute only (time of the data).
      t=t.add(const Duration(seconds:30));
      await b.push();
      expect(updates,hasLength(3));
      t=t.add(const Duration(seconds:30));
      await b.push();
      expect(updates,hasLength(4));
      await settle();
      b.dispose();
    });
  });
}
