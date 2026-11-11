// Lot 27:
// - card « Ordres de déplacement : statut mis à jour automatiquement »: the
//   server sets the status from the order (accepted → En route, arrived →
//   Sur place, refused or cancelled → the status before, « Terminé,
//   disponible » → Disponible); the application offers « Terminé,
//   disponible » on an arrived order (banner, sheet, car) and shows the
//   statuses the server sets;
// - card « Statut de l'opérateur : « Disponible » par défaut »: set by the
//   server; « Aucun statut » stays a choice (car grid).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/features/orders/move_order_eta.dart';
import 'package:sarcade_app/src/features/orders/move_orders.dart';
import 'package:sarcade_app/src/features/team/operator_status.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

final now=DateTime.utc(2026,11,3,22,0);

MoveOrder order(String id,String status,{Duration ago=const Duration(minutes:1),bool finished=false,String target='TEL-1'})=>MoveOrder({
  'id':id,'event_id':'e','target_id':target,'created_by':'PCO','status':status,
  'destination':{'lat':48.80,'lon':1.95,'label':'P2'},'note':'',
  'updated_at':now.subtract(ago).toIso8601String(),
  if(finished)'finished_at':now.toIso8601String(),
});

CarScreenInput input(List<MoveOrder> orders,{Map<String,Map<String,dynamic>> devices=const {}})=>
  CarScreenInput(me:'TEL-1',eventId:'e',now:now,orders:orders,devices:devices);

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>S.setLanguage('fr'));

  group('« Terminé, disponible »',(){
    test('offered on an arrived order not finished yet',(){
      expect(order('o','arrived').awaitingFinish,isTrue);
      expect(order('o','arrived',finished:true).finished,isTrue);
      expect(order('o','arrived',finished:true).awaitingFinish,isFalse);
      expect(order('o','accepted').awaitingFinish,isFalse);
      expect(order('o','accepted',finished:true).finished,isFalse,reason:'only an arrived order is finished');
    });

    test('my banner: the open order first, else the arrived one to finish while on the map',(){
      expect(myMoveOrder([order('a','arrived'),order('s','sent',ago:const Duration(minutes:5))],'TEL-1',now)?.id,'s');
      expect(myMoveOrder([order('a','arrived')],'TEL-1',now)?.id,'a');
      expect(myMoveOrder([order('a','arrived',finished:true)],'TEL-1',now),isNull);
      expect(myMoveOrder([order('a','arrived',ago:const Duration(minutes:40))],'TEL-1',now),isNull,reason:'off the map after 30 min');
      expect(myMoveOrder([order('a','arrived',target:'TEL-2')],'TEL-1',now),isNull);
      expect(myMoveOrder([order('r','refused')],'TEL-1',now),isNull);
    });

    test('subtitle of a finished order',(){
      expect(moveOrderSubtitle(order('o','arrived',finished:true)),'arrivé, terminé');
      expect(moveOrderSubtitle(order('o','arrived')),'arrivé');
      S.setLanguage('en');
      expect(moveOrderSubtitle(order('o','arrived',finished:true)),'arrived, done');
      expect(S.t('orders.status.finish'),'Done, available');
    });

    testWidgets('banner of an arrived order: one button, « Terminé, disponible »',(t) async {
      var finished=0;
      await t.pumpWidget(MaterialApp(home:Scaffold(body:MoveOrderBanner(order:order('o','arrived'),
        onAccept:(){},onRefuse:(){},onNavigate:(){},onArrived:(){},onFinished:()=>finished++))));
      expect(find.text('Terminé, disponible'),findsOneWidget);
      expect(find.text('Je suis arrivé'),findsNothing);
      await t.tap(find.byKey(const ValueKey('order-finished')));
      expect(finished,1);
    });

    test('car: the finished flag, the label, the answer once',() async {
      final snap=carSnapshot(input([order('a','arrived'),order('b','arrived',finished:true)]));
      final orders=(snap['orders'] as List).cast<Map<String,Object?>>();
      expect({for(final o in orders)o['id']:o['finished']},{'a':null,'b':true});
      expect(carLabels()['finish'],'Terminé, disponible');
      expect(carOrderAnswerAllowed('arrived',moveOrderFinished),isTrue);
      expect(carOrderAnswerAllowed('accepted',moveOrderFinished),isFalse);
      final done=<String>[];
      final act=CarScreenActions(order:(o,s) async=>done.add('${o.id} $s'),ack:(a,m) async {},send:(m) async {},sos:() async {},sosEnd:() async {});
      final i=input([order('a','arrived'),order('b','arrived',finished:true),order('c','accepted')]);
      for(final id in const ['a','b','c']){await applyCarAction(CarAction('order',{'id':id,'status':moveOrderFinished}),i,act);}
      expect(done,['a finished']);
    });

    test('car: a finished order reaches the car at once',(){
      final a=carUrgentKey(carSnapshot(input([order('a','arrived')])));
      final b=carUrgentKey(carSnapshot(input([order('a','arrived',finished:true)])));
      expect(a,isNot(b));
    });
  });

  group('statuses set by the server',(){
    test('the car shows the status the server set from an order (operator.status)',(){
      final book=OperatorStatusBook();
      final devices={'TEL-1':{'device_id':'TEL-1','callsign':'F4ABC','operator_status':'disponible','operator_status_at':'2026-11-03T21:00:00Z'}};
      book.applyJson(devices['TEL-1']!);
      book.applyJson({'device_id':'TEL-1','operator_status':'en_route','operator_status_at':'2026-11-03T21:50:00Z'});
      book.applyJson({'device_id':'TEL-2','operator_status':'sur_place','operator_status_at':'2026-11-03T21:55:00Z'});
      final merged=devicesWithStatuses(devices,book);
      expect(merged['TEL-1']!['operator_status'],'en_route');
      expect(merged['TEL-1']!['callsign'],'F4ABC',reason:'the other fields stay');
      expect(merged['TEL-2']!['operator_status'],'sur_place');
      expect(devices['TEL-1']!['operator_status'],'disponible',reason:'the list of the devices is not changed');
      final snap=carSnapshot(input(const [],devices:merged));
      expect(snap['me'],{'status':null},reason:'without CarField (tests), no status of mine');
    });

    test('« Disponible » by default comes like any status',(){
      final book=OperatorStatusBook();
      expect(book.applyJson({'device_id':'TEL-1','operator_status':'disponible','operator_status_at':'2026-11-03T21:00:00Z'}),isTrue);
      expect(book.statusOf('TEL-1'),'disponible');
      // « Aucun statut » chosen afterwards wins.
      expect(book.apply('TEL-1',null,DateTime.utc(2026,11,3,21,5)),isTrue);
      expect(book.statusOf('TEL-1'),isNull);
    });
  });
}
