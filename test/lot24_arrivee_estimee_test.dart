import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/orders/move_order_eta.dart';
import 'package:sarcade_app/src/features/orders/move_orders.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

// Card « Android Auto : heure d'arrivée estimée envoyée au PCO » (lot 24),
// PCO side: list of the orders and label on the map.

MoveOrder order({String status='accepted',String? eta,num? remaining})=>MoveOrder({'id':'o1','target_id':'op1','created_by':'PCO',
  'status':status,'destination':{'lat':48.8,'lon':2.0,'label':'Ferme'},'updated_at':'2026-11-03T08:00:00Z',
  'eta':?eta,'eta_updated_at':eta==null?null:'2026-11-03T08:02:00Z','eta_by':'op1','eta_remaining_m':?remaining});

void main(){
  setUp(()=>S.setLanguage('fr'));
  tearDown(()=>S.setLanguage('fr'));
  final eta=DateTime(2026,11,3,8,15).toUtc().toIso8601String();

  test('« arrivée estimée 8 h 15 », distance when sent',(){
    expect(moveOrderEtaText(order(eta:eta)),'arrivée estimée 8 h 15');
    expect(moveOrderEtaText(order(eta:eta,remaining:3200)),'arrivée estimée 8 h 15 · encore 3,20 km');
    expect(moveOrderSubtitle(order(eta:eta)),'accepté, en route · arrivée estimée 8 h 15');
    expect(moveOrderSubtitle(order()),'accepté, en route');
    // Only while accepted.
    expect(moveOrderEtaText(order(status:'arrived',eta:eta)),isNull);
    S.setLanguage('en');
    expect(moveOrderEtaText(order(eta:eta,remaining:850)),'estimated arrival 8:15 · 850 m to go');
  });

  testWidgets('list of the orders shows the estimate',(t) async {
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(c)=>ListView(children:moveOrderList(c,[order(eta:eta)],onOpen:(_){},now:DateTime.utc(2026,11,3,8,5)))))));
    expect(find.text('accepté, en route · arrivée estimée 8 h 15'),findsOneWidget);
  });

  test('map label next to the operator, or the flag',(){
    final o=order(eta:eta,remaining:1200);
    final withPos=buildEtaLayers([o],(_)=>const LatLng(48.7,2.1),(_){});
    expect((withPos.single as MarkerLayer).markers.single.point,const LatLng(48.7,2.1));
    final noPos=buildEtaLayers([o],(_)=>null,(_){});
    expect((noPos.single as MarkerLayer).markers.single.point,const LatLng(48.8,2.0));
    expect(buildEtaLayers([order()],(_)=>null,(_){}),isEmpty);
  });
}
