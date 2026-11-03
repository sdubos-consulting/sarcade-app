import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';
import 'package:sarcade_app/src/features/map/drawing/multi_select.dart';
import 'package:sarcade_app/src/features/poi/poi_selection.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/poi.dart';

// Lot 25, card « Sélection : inclure les points d'intérêt (Maj+clic,
// rectangle) », and the direct drag of a selected point.

SarcadePoi _poi(String id,{String by='T1',double lat=48.8,double lon=2.1})=>SarcadePoi(id:id,eventId:'e',kind:'designated',lat:lat,lon:lon,
  label:'Point $id',createdAt:DateTime.utc(2026,11,3,14),createdBy:by,color:0xFF1E88E5);

MapFeature _line(String id)=>MapFeature(id:id,eventId:'e',kind:FeatureKind.line,points:const [LatLng(48.8,2.1),LatLng(48.81,2.11)],
  color:0xFFE53935,strokeWidth:4,label:'Axe',createdBy:'T1',updatedBy:'T1',updatedAt:DateTime.utc(2026));

class _Fake {
  final pois=<String,SarcadePoi>{};
  final moved=<Map<String,LatLng>>[]; final deleted=<List<String>>[]; final coloured=<(List<String>,int)>[];
  PoiSelectionHooks hooks(String actor)=>PoiSelectionHooks(
    positionOf:(id){final p=pois[id];return p==null?null:LatLng(p.lat,p.lon);},
    canSelect:(id)=>pois[id]?.createdBy==actor||actor=='PCO',
    onMoved:(to){moved.add(Map.of(to));to.forEach((id,at){final p=pois[id]!;pois[id]=_poi(id,by:p.createdBy!,lat:at.latitude,lon:at.longitude);});},
    onDelete:(ids){deleted.add(List.of(ids));for(final id in ids){pois.remove(id);}},
    onColor:(ids,c)=>coloured.add((List.of(ids),c)),
    asFeature:(id){final p=pois[id];return p==null?null:poiAsFeature(p);},
    message:(d,ids)=>selectionMessageText(d,[for(final id in ids)?pois[id]],(l)=>'${l.latitude.toStringAsFixed(3)} ${l.longitude.toStringAsFixed(3)}'),
  );
}

void main(){
  setUp(()=>S.setLanguage('fr'));

  late _Fake fake; late DrawingController c;
  setUp((){
    fake=_Fake()..pois.addAll({'a':_poi('a'),'b':_poi('b',lat:48.9),'x':_poi('x',by:'T2')});
    c=DrawingController(eventId:'e',actorId:'T1',initial:[_line('l1'),_line('l2')])..poiHooks=fake.hooks('T1');
  });

  test('Maj+clic adds or removes a point; own points only (choices 1 and 4)',(){
    c.togglePoi('a');
    expect(c.selectedPois, ['a']);
    expect(c.hasSelection, isTrue);
    expect(c.showsCommonBar, isTrue, reason:'one point: the common bar');
    c.togglePoi('x');
    expect(c.selectedPois, ['a'], reason:'a point of another operator');
    c.togglePoi('a');
    expect(c.hasSelection, isFalse);
    final pco=DrawingController(eventId:'e',actorId:'PCO')..poiHooks=fake.hooks('PCO');
    pco.togglePoi('x');
    expect(pco.selectedPois, ['x']);
  });

  test('rectangle: drawings and points together; counter « 2 dessins · 2 points » (choices 2 and 5)',(){
    c.addToSelection(['l1','l2']);
    c.addPoisToSelection(['a','b','x']);
    expect(c.selectionCount, 4);
    expect(c.selected, isNull);
    expect(c.isMulti, isTrue);
    expect(selectionCountText(2,2), '2 dessins · 2 points');
    expect(selectionCountText(1,1), '1 dessin · 1 point');
    expect(selectionCountText(0,3), '3 points');
    c.select(null);
    expect(c.selectedPois, isEmpty);
    c.addPoisToSelection(['a']);
    c.endSelection();
    expect(c.selectedPois, isEmpty);
  });

  test('points in the rectangle and under the click',(){
    Offset project(LatLng l)=>Offset((l.longitude-2)*1000,(49-l.latitude)*1000);
    final all=fake.pois.values;
    expect(poisInRect(all,const Rect.fromLTWH(90,190,20,20),project), containsAll(['a','x']));
    expect(poisInRect(all,const Rect.fromLTWH(90,190,20,20),project), isNot(contains('b')));
    expect(poiAtOffset(all,const Offset(105,95),project)?.id,'b');
    expect(poiAtOffset(all,const Offset(300,300),project), isNull);
  });

  test('move together: drawings and points, one undo step (choice 3)',(){
    c.addToSelection(['l1']);
    c.addPoisToSelection(['a']);
    c.beginEdit();
    c.moveSelected(0.01,0);
    expect(c.poiPlace('a')!.latitude, closeTo(48.81,1e-9), reason:'the point follows the drag');
    expect(fake.moved, isEmpty);
    c.endEdit();
    expect(fake.moved.single['a']!.latitude, closeTo(48.81,1e-9));
    expect(c.feature('l1')!.points.first.latitude, closeTo(48.81,1e-9));
    expect(c.poiLive, isEmpty);
    c.undo();
    expect(fake.moved.last['a']!.latitude, closeTo(48.8,1e-9));
    expect(c.feature('l1')!.points.first.latitude, closeTo(48.8,1e-9));
    c.redo();
    expect(fake.moved.last['a']!.latitude, closeTo(48.81,1e-9));
  });

  test('a point alone is dragged and moved',(){
    c.togglePoi('b');
    c.beginEdit();
    c.moveSelected(0,0.002);
    c.endEdit();
    expect(fake.moved.single.keys, ['b']);
    expect(fake.moved.single['b']!.longitude, closeTo(2.102,1e-9));
  });

  test('delete, colour and export apply to the points too',(){
    c.addToSelection(['l1']);
    c.addPoisToSelection(['a','b']);
    c.setColor(0xFF43A047);
    expect(fake.coloured.single.$1, ['a','b']);
    expect(fake.coloured.single.$2, 0xFF43A047);
    expect(c.feature('l1')!.color, 0xFF43A047);
    final out=c.exportSelection;
    expect(out.map((f)=>f.id), ['l1','a','b']);
    expect(out.last.kind, FeatureKind.point);
    expect(c.selectionMessage, contains('Point a'));
    expect(c.selectionMessage, contains('Ligne « Axe »'));
    c.deleteSelected();
    expect(fake.deleted.single, ['a','b']);
    expect(c.feature('l1'), isNull);
    expect(c.hasSelection, isFalse);
  });

  test('a click with the « Sélection » mode selects the point',(){
    expect(poiTapSelects(c,fake.pois['a']!), isFalse, reason:'no key, no mode: the sheet opens');
    c.startSelection();
    expect(poiTapSelects(c,fake.pois['a']!), isTrue);
    expect(c.selectedPois, ['a']);
  });

  testWidgets('common bar: counter, Envoyer en message, delete with confirmation',(t) async {
    c.addToSelection(['l1']);
    c.addPoisToSelection(['a']);
    final sent=<String>[];
    await t.pumpWidget(MaterialApp(home:Scaffold(body:ListenableBuilder(listenable:c,builder:(ctx,_)=>Column(children:[
      MultiSelectionBar(controller:c,onExport:(_){},onSend:sent.add),
      TextButton(onPressed:()=>deleteSelection(ctx,c),child:const Text('suppr')),
    ])))));
    expect(find.text('1 dessin · 1 point'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('multi-send')));
    expect(sent.single, contains('Point a'));
    await t.tap(find.text('suppr'));
    await t.pumpAndSettle();
    expect(find.text(S.t('poi.deleteSel',{'what':'1 dessin · 1 point'})), findsOneWidget);
    await t.tap(find.text(S.t('routes.delete')));
    await t.pumpAndSettle();
    expect(fake.deleted.single, ['a']);
  });
}
