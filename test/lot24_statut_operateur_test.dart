import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/features/team/operator_status.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/offline/local_store.dart';
import 'package:sarcade_app/src/offline/sync_service.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';

// Card « Android Auto : statut en un appui » (lot 24), application side:
// statuses received, shown, and « Mon statut » sent (PUT, else Outbox).

class _Store extends LocalStore {}

class _Sync extends OfflineSyncService {
  _Sync(SarcadeApi api):super(api:api,store:_Store(),eventId:'ev1');
  final queued=<Map<String,dynamic>>[];
  @override Future<void> queue({required String objectId,required String objectType,required Map<String,dynamic> payload,String action='create'}) async {
    queued.add({'object_id':objectId,'object_type':objectType,'action':action,'payload':payload});
  }
}

void main(){
  setUp(()=>S.setLanguage('fr'));
  tearDown(()=>S.setLanguage('fr'));

  group('book of the statuses',(){
    test('the most recent wins, whatever the order',(){
      final b=OperatorStatusBook();
      expect(b.apply('op1','en_route',DateTime.utc(2026,11,3,8,10)),isTrue);
      expect(b.apply('op1','pause',DateTime.utc(2026,11,3,8,5)),isFalse);
      expect(b.statusOf('op1'),'en_route');
      expect(b.apply('op1','sur_place',DateTime.utc(2026,11,3,8,20)),isTrue);
      expect(b.statusOf('op1'),'sur_place');
      // The same status again keeps its first time.
      expect(b.apply('op1','sur_place',DateTime.utc(2026,11,3,8,30)),isFalse);
      expect(b.sinceOf('op1'),DateTime.utc(2026,11,3,8,20));
      // Removed: null with a newer time.
      expect(b.apply('op1',null,DateTime.utc(2026,11,3,8,40)),isTrue);
      expect(b.statusOf('op1'),isNull);
    });

    test('devices, operator.status and changes feed; old servers say nothing',(){
      final saved=<Map<String,dynamic>>[];
      final b=OperatorStatusBook(save:saved.add);
      b.applyAll([
        {'device_id':'op1','status':'ok','operator_status':'disponible','operator_status_at':'2026-11-03T08:00:00Z'},
        {'device_id':'op2','status':'late','operator_status':null,'operator_status_at':null},
        {'device_id':'op3','status':'ok'},
      ]);
      expect(b.statusOf('op1'),'disponible');
      expect(b.statusOf('op2'),isNull);
      expect(b.statusOf('op3'),isNull);
      // Unknown value of a newer server: no pastille.
      b.applyJson({'device_id':'op4','operator_status':'autre','operator_status_at':'2026-11-03T08:00:00Z'});
      expect(b.statusOf('op4'),isNull);
      expect(saved,isNotEmpty);
      // Kept on the device.
      final again=OperatorStatusBook(saved:jsonDecode(jsonEncode(b.toJson())) as Map<String,dynamic>);
      expect(again.statusOf('op1'),'disponible');
      expect(again.sinceOf('op1'),DateTime.utc(2026,11,3,8));
    });

    test('labels and colours of the contract',(){
      expect(operatorStatuses,['en_route','sur_place','disponible','pause']);
      expect(operatorStatusColors['en_route'],const Color(0xFFFFB020));
      expect(operatorStatusColors['sur_place'],const Color(0xFF4ADE80));
      expect(operatorStatusColors['disponible'],const Color(0xFF3DD6F5));
      expect(operatorStatusColors['pause'],const Color(0xFF9AA3AD));
      expect(operatorStatusLabel('en_route'),'En route');
      S.setLanguage('en');
      expect(operatorStatusLabel('sur_place'),'On site');
      expect(statusClock(DateTime(2026,11,3,8,5)),'8:05');
      S.setLanguage('fr');
      expect(statusClock(DateTime(2026,11,3,8,5)),'8 h 05');
      expect(operatorStatusText('pause',DateTime(2026,11,3,8,5)),'Pause · depuis 8 h 05');
    });
  });

  group('sending « Mon statut »',(){
    test('PUT with the time of the choice',() async {
      final calls=<http.Request>[];
      final api=SarcadeApi(baseUrl:'https://s',client:MockClient((r) async {calls.add(r);
        return http.Response(jsonEncode({'event_id':'ev1','device_id':'me','operator_status':'en_route','operator_status_at':'2026-11-03T08:10:00Z','changed':true}),200);}));
      final b=OperatorStatusBook();
      final r=await sendOperatorStatus(api:api,eventId:'ev1',deviceId:'me',status:'en_route',at:DateTime.utc(2026,11,3,8,10),book:b,sync:_Sync(api));
      expect(r,StatusSend.sent);
      expect(calls.single.method,'PUT');
      expect(calls.single.url.path,'/api/v0.1/events/ev1/devices/me/status');
      expect(jsonDecode(calls.single.body),{'device_id':'me','status':'en_route','at':'2026-11-03T08:10:00.000Z','actor_id':'me'});
      expect(b.statusOf('me'),'en_route');
    });

    test('server out of reach: Outbox, shown at once',() async {
      final api=SarcadeApi(baseUrl:'https://s',client:MockClient((_) async=>throw http.ClientException('offline')));
      final sync=_Sync(api); final b=OperatorStatusBook();
      final r=await sendOperatorStatus(api:api,eventId:'ev1',deviceId:'me',status:'pause',at:DateTime.utc(2026,11,3,9),book:b,sync:sync);
      expect(r,StatusSend.queued);
      expect(sync.queued.single['object_type'],'operator_status');
      expect(sync.queued.single['action'],'update');
      expect(sync.queued.single['object_id'],'me');
      expect((sync.queued.single['payload'] as Map)['status'],'pause');
      expect((sync.queued.single['payload'] as Map)['at'],'2026-11-03T09:00:00.000Z');
      expect(b.statusOf('me'),'pause');
    });

    test('refused: the former status comes back',() async {
      final api=SarcadeApi(baseUrl:'https://s',client:MockClient((_) async=>http.Response('{"detail":"invalid_status"}',422)));
      final b=OperatorStatusBook()..apply('me','disponible',DateTime.utc(2026,11,3,8));
      final r=await sendOperatorStatus(api:api,eventId:'ev1',deviceId:'me',status:'pause',at:DateTime.utc(2026,11,3,9),book:b,sync:_Sync(api));
      expect(r,StatusSend.failed);
      expect(b.statusOf('me'),'disponible');
    });
  });

  testWidgets('« Mon statut »: four choices, the current one removed by a touch',(t) async {
    String? chosen='x';
    await t.pumpWidget(MaterialApp(home:Scaffold(body:MyStatusPicker(status:'en_route',since:DateTime(2026,11,3,8,10),onChanged:(v)=>chosen=v))));
    expect(find.text('Mon statut · depuis 8 h 10'),findsOneWidget);
    for(final l in ['En route','Sur place','Disponible','Pause']){expect(find.text(l),findsOneWidget);}
    await t.tap(find.byKey(const ValueKey('my-status-pause')));
    expect(chosen,'pause');
    await t.tap(find.byKey(const ValueKey('my-status-en_route')));
    expect(chosen,isNull);
  });

  testWidgets('pastille on an icon, nothing without status',(t) async {
    await t.pumpWidget(MaterialApp(home:Column(children:[
      withStatusDot(const Icon(Icons.person),'sur_place'),
      withStatusDot(const Icon(Icons.person_outline),null),
    ])));
    expect(find.byKey(const ValueKey('status-dot-sur_place')),findsOneWidget);
    expect(find.byType(StatusDot),findsOneWidget);
  });
}
