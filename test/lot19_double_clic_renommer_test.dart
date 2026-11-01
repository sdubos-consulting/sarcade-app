import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/drawing/double_tap_rename.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_layers.dart';
import 'package:sarcade_app/src/features/map/drawing/hit_test.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';
import 'package:sarcade_app/src/features/map/rename_dialog.dart';
import 'package:sarcade_app/src/features/poi/poi_list.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/poi.dart';

// Card « Point d'intérêt : double-clic pour le renommer » (lot 19, choices
// 1 to 5, points of interest and drawn objects).

const _centre=LatLng(48.8,2.1);

SarcadePoi _poi({String by='T1'})=>SarcadePoi(id:'p1',eventId:'e',kind:'designated',lat:48.8,lon:2.1,label:'Parc de Versailles',
  createdAt:DateTime.utc(2026,11,1),createdBy:by);

MapFeature _zone()=>MapFeature(id:'z',eventId:'e',kind:FeatureKind.zone,
  points:const [LatLng(48.795,2.09),LatLng(48.795,2.11),LatLng(48.805,2.11),LatLng(48.805,2.09)],
  color:0xFFE53935,strokeWidth:4,label:'Secteur',createdBy:'T2',updatedBy:'T2',updatedAt:DateTime.utc(2026));

Future<void> _doubleTap(WidgetTester t,Offset at) async {
  await t.tapAt(at);
  await t.pump(const Duration(milliseconds:60));
  await t.tapAt(at);
  await t.pump(const Duration(milliseconds:400));
  await t.pumpAndSettle();
}

void main() {
  setUp(()=>S.setLanguage('fr'));

  group('rename window', () {
    Future<void> open(WidgetTester t,List<String?> out) async {
      await t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(c)=>TextButton(
        onPressed:() async {out.add(await askNewName(c,title:'Modifier le nom',initial:'Parc de Versailles',fieldKey:const ValueKey('name')));},
        child:const Text('go'))))));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
    }

    testWidgets('current name selected, Entrée saves', (t) async {
      final out=<String?>[];
      await open(t,out);
      final field=t.widget<TextField>(find.byKey(const ValueKey('name')));
      expect(field.controller!.selection, const TextSelection(baseOffset:0,extentOffset:18));
      await t.enterText(find.byKey(const ValueKey('name')),'Château ');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(out, ['Château']);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Échap cancels', (t) async {
      final out=<String?>[];
      await open(t,out);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(out, [null]);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('point of interest', () {
    Widget map({required MapController m,required void Function(SarcadePoi) onTap,required void Function(BuildContext,SarcadePoi) onDouble})=>
      MaterialApp(home:Scaffold(body:FlutterMap(mapController:m,options:const MapOptions(initialCenter:_centre,initialZoom:14),
        children:[Builder(builder:(c)=>PoiClusterLayer(pois:[_poi()],onTap:onTap,onDoubleTap:(p)=>onDouble(c,p)))])));

    testWidgets('double click: rename window, name changed, no zoom; simple click: the sheet', (t) async {
      final m=MapController();
      final renamed=<String>[]; var sheets=0;
      await t.pumpWidget(map(m:m,onTap:(_)=>sheets++,onDouble:(c,p)=>doubleTapPoi(c,p,actor:'T1',rename:(n) async=>renamed.add(n),openSheet:()=>sheets++)));
      await t.pump();
      final zoom=m.camera.zoom;
      final pin=t.getCenter(find.byKey(const ValueKey('poi-p1')));
      await _doubleTap(t,pin);
      expect(find.text(S.t('poi.rename')), findsOneWidget, reason:'the rename window opens');
      expect(sheets, 0);
      expect(m.camera.zoom, zoom, reason:'a double click on a point does not zoom');
      await t.enterText(find.byKey(const ValueKey('poi-name')),'Parc du château');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(renamed, ['Parc du château']);

      await t.tapAt(pin);
      for(var i=0;i<3;i++){await t.pump(const Duration(milliseconds:300));}
      expect(sheets, 1, reason:'a simple click keeps the sheet');
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('neither PCO nor author: the usual sheet', (t) async {
      final renamed=<String>[]; var sheets=0;
      await t.pumpWidget(map(m:MapController(),onTap:(_)=>sheets++,onDouble:(c,p)=>doubleTapPoi(c,p,actor:'T9',rename:(n) async=>renamed.add(n),openSheet:()=>sheets++)));
      await t.pump();
      await _doubleTap(t,t.getCenter(find.byKey(const ValueKey('poi-p1'))));
      expect(find.byType(AlertDialog), findsNothing);
      expect(sheets, 1);
      expect(renamed, isEmpty);
    });
  });

  group('drawn object', () {
    late DrawingController c; late MapController m; late List<MapFeature> synced; late List<LatLng> taps;
    Widget map()=>MaterialApp(home:Scaffold(body:ListenableBuilder(listenable:c,builder:(_,_)=>FlutterMap(mapController:m,
      options:MapOptions(initialCenter:_centre,initialZoom:14,onTap:(_,p)=>taps.add(p)),
      children:[...buildDrawingLayers(c),Builder(builder:(ctx)=>DrawingDoubleTapLayer(controller:c,onDoubleTap:(f)=>renameDrawing(ctx,c,f)))]))));

    setUp((){
      synced=[];taps=[];m=MapController();
      c=DrawingController(eventId:'e',actorId:'T1',initial:[_zone()],onChanged:(f,{required isNew})=>synced.add(f));
    });

    testWidgets('double click on a zone: rename window, label changed and synchronised, no zoom', (t) async {
      await t.pumpWidget(map());
      await t.pump();
      final zoom=m.camera.zoom;
      await _doubleTap(t,t.getCenter(find.byType(FlutterMap)));
      expect(find.text(S.t('draw.rename')), findsOneWidget);
      expect(m.camera.zoom, zoom, reason:'a double click on an object does not zoom');
      expect(c.selected?.id, 'z');
      await t.enterText(find.byKey(const ValueKey('draw-name')),'Secteur nord');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(c.feature('z')!.label, 'Secteur nord');
      expect(synced.single.label, 'Secteur nord', reason:'synchronised like any change of name');
      expect(c.canUndo, isTrue);
    });

    testWidgets('Échap: nothing changes', (t) async {
      await t.pumpWidget(map());
      await t.pump();
      await _doubleTap(t,t.getCenter(find.byType(FlutterMap)));
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(c.feature('z')!.label, 'Secteur');
      expect(synced, isEmpty);
    });

    testWidgets('simple click on a zone still reaches the map (selection)', (t) async {
      await t.pumpWidget(map());
      await t.pump();
      await t.tapAt(t.getCenter(find.byType(FlutterMap)));
      // The double click is waited for, then the delay of the map itself.
      for(var i=0;i<4;i++){await t.pump(const Duration(milliseconds:300));}
      expect(taps, hasLength(1));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('double click elsewhere: the map still zooms, no window', (t) async {
      await t.pumpWidget(map());
      await t.pump();
      final zoom=m.camera.zoom;
      await _doubleTap(t,const Offset(40,40));
      expect(find.byType(AlertDialog), findsNothing);
      expect(m.camera.zoom, greaterThan(zoom));
    });

    testWidgets('off while drawing: nothing is caught', (t) async {
      await t.pumpWidget(MaterialApp(home:Scaffold(body:FlutterMap(mapController:m,options:const MapOptions(initialCenter:_centre,initialZoom:14),
        children:[DrawingDoubleTapLayer(controller:c,enabled:false,onDoubleTap:(_){})]))));
      await t.pump();
      expect(find.byKey(const ValueKey('draw-double-tap')), findsNothing);
    });

    test('hit test of the layer: the zone, not outside', () {
      Offset project(LatLng p)=>Offset((p.longitude-2.0)*10000,(49-p.latitude)*10000);
      expect(hitTest([_zone()],project(_centre),project)?.id, 'z');
      expect(hitTest([_zone()],project(const LatLng(48.9,2.3)),project), isNull);
      expect(renameTitle(_zone()), S.t('draw.rename'));
    });
  });
}
