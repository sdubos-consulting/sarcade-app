import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_toolbar.dart';
import 'package:sarcade_app/src/features/map/drawing/import_formats.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';
import 'package:sarcade_app/src/features/measure/coordinates.dart';
import 'package:sarcade_app/src/features/poi/poi_icons.dart';
import 'package:sarcade_app/src/features/poi/poi_move.dart';
import 'package:sarcade_app/src/features/poi/poi_sheet.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/poi.dart';
import 'package:sarcade_app/src/ui/map_sheet.dart';

// Lot 25, points of interest: one way to create a point and its colour,
// one window to modify it, the sheet on a computer, the move.

SarcadePoi _poi({String by='T1',int? color,String? icon})=>SarcadePoi(id:'p1',eventId:'e',kind:'designated',lat:48.8,lon:2.1,
  label:'Gué',createdAt:DateTime.utc(2026,11,3,14),createdBy:by,color:color,icon:icon);

Future<void> _open<T>(WidgetTester t,List<T?> out,Future<T?> Function(BuildContext) show) async {
  await t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(c)=>TextButton(
    onPressed:() async {out.add(await show(c));},child:const Text('go'))))));
  await t.tap(find.text('go'));
  await t.pumpAndSettle();
}

/// Window of [size] logical pixels (MediaQuery follows it).
void _size(WidgetTester t,Size size){
  t.view.physicalSize=size;
  t.view.devicePixelRatio=1;
  addTearDown(t.view.reset);
}

Future<void> _tapVisible(WidgetTester t,Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main(){
  setUp(()=>S.setLanguage('fr'));
  tearDown(()=>S.setLanguage('fr'));

  group('one way to create a point (card 1)', (){
    test('no « Point » in the drawing bar',(){
      expect(drawingToolbarKinds, isNot(contains(FeatureKind.point)));
      expect(drawingToolbarKinds, contains(FeatureKind.line));
    });

    test('default colour by icon: red Danger, blue Eau, the author for the pin',(){
      expect(poiDefaultColor('danger',0xFF43A047),0xFFE53935);
      expect(poiDefaultColor('water',0xFF43A047),0xFF1E88E5);
      expect(poiDefaultColor('pin',0xFF43A047),0xFF43A047);
      for(final k in poiIcons){if(k!='pin')expect(drawingPalette, contains(poiIconColors[k]),reason:k);}
    });

    testWidgets('the window gives the colour, which follows the icon until chosen',(t) async {
      _size(t,const Size(800,1000));
      final out=<PoiDraft?>[];
      await _open(t,out,(c)=>showPoiDialog(c,pinColor:0xFF43A047,name:'Point 14:00'));
      expect(find.text(S.t('poi.createHere')), findsOneWidget);
      expect(find.text(S.t('poi.colorTitle')), findsOneWidget);
      await _tapVisible(t,find.byKey(const ValueKey('poi-icon-danger')));
      await _tapVisible(t,find.byKey(const ValueKey('poi-create-ok')));
      expect(out.single?.icon,'danger');
      expect(out.single?.color,0xFFE53935);

      out.clear();
      await _open(t,out,(c)=>showPoiDialog(c,pinColor:0xFF43A047));
      await _tapVisible(t,find.byKey(const ValueKey('palette-${0xFF8E24AA}')));
      await _tapVisible(t,find.byKey(const ValueKey('poi-icon-water')));
      await _tapVisible(t,find.byKey(const ValueKey('poi-create-ok')));
      expect(out.single?.icon,'water');
      expect(out.single?.color,0xFF8E24AA,reason:'a colour chosen stays when the icon changes');
    });

    test('imported isolated points become points of interest',(){
      final split=splitImportedPoints(const [
        ImportedShape(kind:FeatureKind.point,points:[LatLng(48.8,2.1)],label:'Gué',color:0xFF1E88E5),
        ImportedShape(kind:FeatureKind.line,points:[LatLng(48.8,2.1),LatLng(48.81,2.11)]),
        ImportedShape(kind:FeatureKind.point,points:[LatLng(48.9,2.2)]),
      ]);
      expect(split.shapes.map((s)=>s.kind), [FeatureKind.line]);
      var n=0;
      final json=importedPoiJson(split.points,newId:()=>'id${n++}',eventId:'e',actor:'T1',drawColor:0xFF43A047);
      final pois=json.map(SarcadePoi.fromJson).toList();
      expect(pois.map((p)=>p.id), ['id0','id1']);
      expect(pois.first.label,'Gué');
      expect(pois.first.color,0xFF1E88E5);
      expect(pois.last.label, startsWith('Point '));
      expect(pois.last.color,0xFF43A047);
      expect(pois.last.createdBy,'T1');
    });

    test('a new point keeps the colour chosen, red included',(){
      final p=SarcadePoi.fromJson(newPoiJson(id:'p',eventId:'e',at:const LatLng(48.8,2.1),actor:'T1',drawColor:0xFF43A047,icon:'danger',color:0xFFE53935));
      expect(poiColor(p),0xFFE53935);
      expect(p.icon,'danger');
    });
  });

  group('modify with the window of creation (card 2)', (){
    testWidgets('« Modifier le point d’intérêt », filled, « Enregistrer »',(t) async {
      _size(t,const Size(800,1000));
      final out=<PoiDraft?>[];
      await _open(t,out,(c)=>editPoiDialog(c,_poi(icon:'water',color:0xFF1E88E5)));
      expect(find.text(S.t('poi.editTitle')), findsOneWidget);
      expect(find.text(S.t('common.save')), findsOneWidget);
      expect(t.widget<TextField>(find.byKey(const ValueKey('poi-create-name'))).controller!.text,'Gué');
      await t.enterText(find.byKey(const ValueKey('poi-create-name')),'Gué du moulin');
      await _tapVisible(t,find.byKey(const ValueKey('poi-create-ok')));
      expect(out.single, (name:'Gué du moulin',icon:'water',color:0xFF1E88E5));
    });

    testWidgets('the sheet: one « Modifier », « Déplacer », « Supprimer » last in red',(t) async {
      _size(t,const Size(390,844));
      final out=<String?>[];
      await _open(t,out,(c)=>showPoiSheet(c,_poi(),format:CoordFormat.dd,canEdit:true));
      expect(find.text(S.t('poi.edit')), findsOneWidget);
      expect(find.text(S.t('poi.rename')), findsNothing);
      expect(find.text(S.t('poi.changeIcon')), findsNothing);
      expect(find.text(S.t('poi.move')), findsOneWidget);
      final tiles=t.widgetList<ListTile>(find.descendant(of:find.byKey(const ValueKey('poi-sheet')),matching:find.byType(ListTile))).toList();
      expect(tiles.last.key, const ValueKey('poi-delete'));
      final del=t.widget<Text>(find.descendant(of:find.byKey(const ValueKey('poi-delete')),matching:find.text(S.t('common.delete'))));
      expect(del.style?.color, isNotNull);
      await _tapVisible(t,find.byKey(const ValueKey('poi-edit')));
      expect(out.single,'edit');
    });

    testWidgets('neither author nor PCO: no Modifier, Déplacer nor Supprimer',(t) async {
      final out=<String?>[];
      await _open(t,out,(c)=>showPoiSheet(c,_poi(),format:CoordFormat.dd,canEdit:false));
      expect(find.byKey(const ValueKey('poi-edit')), findsNothing);
      expect(find.byKey(const ValueKey('poi-move')), findsNothing);
      expect(find.byKey(const ValueKey('poi-delete')), findsNothing);
    });
  });

  group('sheet on a computer and small window (card 3)', (){
    for(final size in const [Size(320,360),Size(1280,360)]){
      testWidgets('« Supprimer » reachable, sheet within 90 % (${size.width.toInt()} × ${size.height.toInt()})',(t) async {
        _size(t,size);
        final out=<String?>[];
        await _open(t,out,(c)=>showPoiSheet(c,_poi(),format:CoordFormat.dd,canEdit:true));
        expect(find.byKey(const ValueKey('map-sheet-side')), mapSheetIsSide(size)?findsOneWidget:findsNothing);
        expect(t.getSize(find.byKey(const ValueKey('map-sheet'))).height, lessThanOrEqualTo(size.height*mapSheetMaxShare));
        await _tapVisible(t,find.byKey(const ValueKey('poi-delete')));
        expect(out.single,'delete');
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('a wide screen opens the sheet on the right',(t) async {
      _size(t,const Size(1280,800));
      final out=<String?>[];
      await _open(t,out,(c)=>showPoiSheet(c,_poi(),format:CoordFormat.dd,canEdit:true));
      final box=t.getRect(find.byKey(const ValueKey('map-sheet-side')));
      expect(box.right, greaterThan(1200));
      expect(box.width, lessThanOrEqualTo(mapSheetPanelWidth));
      await t.tap(find.byKey(const ValueKey('map-sheet-close')));
      await t.pumpAndSettle();
      expect(out, [null]);
    });

    testWidgets('any long sheet of the map scrolls at the smallest height',(t) async {
      _size(t,const Size(320,300));
      final out=<int?>[];
      await _open(t,out,(c)=>showMapSheet<int>(c,builder:(s)=>Column(mainAxisSize:MainAxisSize.min,children:[
        for(var i=0;i<12;i++)ListTile(key:ValueKey('row-$i'),title:Text('Ligne $i'),onTap:()=>Navigator.pop(s,i))])));
      await _tapVisible(t,find.byKey(const ValueKey('row-11')));
      expect(out.single,11);
      expect(t.takeException(), isNull);
    });
  });

  group('move (card 4)', (){
    test('start, follow, finish or cancel',(){
      final m=PoiMove();
      expect(m.active, isFalse);
      m.start(_poi());
      expect(m.active, isTrue);
      expect(m.finish(), isNull, reason:'not moved');
      m.start(_poi());
      m.moveTo(const LatLng(48.801,2.1));
      expect(m.movedM, closeTo(111,2));
      final r=m.finish();
      expect(r?.to, const LatLng(48.801,2.1));
      expect(m.active, isFalse);
      m.start(_poi());
      m.moveTo(const LatLng(48.9,2.2));
      m.cancel();
      expect(m.active, isFalse);
    });

    test('the move joins the history: undo, redo, undo from its message',(){
      final c=DrawingController(eventId:'e',actorId:'T1');
      final log=<String>[];
      final tag=Object();
      c.recordExternal(tag:tag,undo:()=>log.add('back'),redo:()=>log.add('again'));
      expect(c.canUndo, isTrue);
      c.undo();
      c.redo();
      expect(log, ['back','again']);
      expect(c.undoTagged(tag), isTrue);
      expect(log, ['back','again','back']);
      expect(c.undoTagged(tag), isFalse);
      expect(c.canUndo, isFalse);
    });

    testWidgets('banner: hint, Annuler and Valider',(t) async {
      final m=PoiMove()..start(_poi());
      var ok=0, cancel=0;
      await t.pumpWidget(MaterialApp(home:Scaffold(body:PoiMoveBanner(move:m,onValidate:()=>ok++,onCancel:()=>cancel++))));
      expect(find.textContaining(S.t('poi.moveHint')), findsOneWidget);
      m.moveTo(const LatLng(48.801,2.1));
      await t.pump();
      expect(find.textContaining('m'), findsWidgets);
      await t.tap(find.byKey(const ValueKey('poi-move-ok')));
      await t.tap(find.byKey(const ValueKey('poi-move-cancel')));
      expect((ok,cancel), (1,1));
    });
  });
}
