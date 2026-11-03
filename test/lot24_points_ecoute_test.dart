import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/modules/adrasec/listening/listening_points.dart';
import 'package:sarcade_app/src/offline/local_store.dart';
import 'package:sarcade_app/src/offline/sync_service.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';

// Card « Android Auto : « Signal entendu ici » (SATER) » (lot 24), map of
// the PCO: listening points in the « Relevés » layer, sheet, deletion.

class _Store extends LocalStore {
  final deleted=<String>[];
  @override Future<void> deleteMapFeature(String id) async {deleted.add(id);}
}

class _Sync extends OfflineSyncService {
  _Sync():super(api:SarcadeApi(baseUrl:'https://s',client:MockClient((_) async=>http.Response('',500))),store:_Store(),eventId:'ev1');
  final queued=<Map<String,dynamic>>[];
  @override Future<void> queue({required String objectId,required String objectType,required Map<String,dynamic> payload,String action='create'}) async {
    queued.add({'object_id':objectId,'object_type':objectType,'action':action,'payload':payload});
  }
}

Map<String,dynamic> feature({String id='l1',String updated='2026-11-03T08:00:05Z',bool exercise=false,num? heading=135}){
  final heard=DateTime(2026,11,3,8,0).toUtc().toIso8601String();
  return {'id':id,'event_id':'ev1','kind':'listening','points':[[48.75,2.05]],'color':0xFFFF9F1C,'stroke_width':2,
    'listening':{'heard_at':heard,'heading_deg':?heading,'exercise':?(exercise?true:null)},
    'created_by':'VL-12','updated_by':'VL-12','updated_at':updated};
}

void main(){
  setUp(()=>S.setLanguage('fr'));
  tearDown(()=>S.setLanguage('fr'));

  test('listening points: kept, newer version wins, deletion',(){
    final pts=ListeningPoints(initial:[feature(),{'id':'d1','event_id':'ev1','kind':'line','points':[[1,2],[3,4]]}]);
    expect(pts.all.map((l)=>l.id),['l1']);
    final l=pts['l1']!;
    expect(l.point,const LatLng(48.75,2.05));
    expect(l.headingDeg,135);
    expect(l.createdBy,'VL-12');
    expect(listeningLabel(l),'Écoute 08:00');
    expect(pts.apply(feature(updated:'2026-11-03T07:59:00Z',heading:90)),isFalse);
    expect(pts.apply(feature(updated:'2026-11-03T08:01:00Z',exercise:true)),isTrue);
    expect(listeningLabel(pts['l1']!),'EX · Écoute 08:00');
    expect(pts.apply({'id':'bad','kind':'listening','points':[]}),isFalse);
    expect(pts.remove('l1'),isTrue);
    expect(pts.all,isEmpty);
  });

  test('ring and heading line, as the TV',(){
    final layers=buildListeningLayers([ListeningPoint(feature())],onTap:(_){});
    final line=(layers.first as PolylineLayer).polylines.single;
    expect(line.color,listeningColor);
    expect(line.points.first,const LatLng(48.75,2.05));
    expect((layers.last as MarkerLayer).markers.single.point,const LatLng(48.75,2.05));
    // No heading: only the ring.
    expect(buildListeningLayers([ListeningPoint(feature(heading:null))],onTap:(_){}).single,isA<MarkerLayer>());
    expect(buildListeningLayers(const [],onTap:(_){}),isEmpty);
  });

  testWidgets('sheet: author, time, heading; « Supprimer » for the PCO',(t) async {
    var deleted=0;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(c)=>Column(children:[
      TextButton(onPressed:()=>showListeningSheet(c,ListeningPoint(feature()),canDelete:true,onDelete:()=>deleted++),child:const Text('pco')),
      TextButton(onPressed:()=>showListeningSheet(c,ListeningPoint(feature()),canDelete:false,onDelete:()=>deleted++),child:const Text('op')),
    ])))));
    await t.tap(find.text('op'));await t.pumpAndSettle();
    expect(find.textContaining('Signal entendu par VL-12 à 08:00'),findsOneWidget);
    expect(find.textContaining('Cap du véhicule 135°'),findsOneWidget);
    expect(find.byKey(const ValueKey('listening-delete')),findsNothing);
    Navigator.of(t.element(find.byKey(const ValueKey('listening-sheet')))).pop();await t.pumpAndSettle();
    await t.tap(find.text('pco'));await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('listening-delete')));await t.pumpAndSettle();
    expect(deleted,1);
  });

  test('deletion by the PCO leaves through the Outbox',() async {
    final pts=ListeningPoints(initial:[feature()]); final store=_Store(); final sync=_Sync();
    await deleteListeningPoint(pts['l1']!,points:pts,store:store,sync:sync,eventId:'ev1',actorId:'PCO');
    expect(pts.all,isEmpty);
    expect(store.deleted,['l1']);
    expect(sync.queued.single['action'],'delete');
    expect(sync.queued.single['object_type'],'map_feature');
    expect((sync.queued.single['payload'] as Map)['updated_by'],'PCO');
  });
}
