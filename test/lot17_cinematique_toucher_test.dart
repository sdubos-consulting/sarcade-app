import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/cinematique_touch.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_toolbar.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';
import 'package:sarcade_app/src/ui/test_ids.dart';

// Card L1 of the cinématique review of lot 16 (lot 17, choice 1): while
// drawing, measuring or taking a bearing, the markers ignore touches and
// the point is placed where the map was touched.

/// A map with one operator marker in the middle.
Widget _map({required bool ignoring,required void Function(LatLng) onMapTap,required VoidCallback onMarkerTap})=>MaterialApp(home:Scaffold(body:FlutterMap(
  options:MapOptions(initialCenter:const LatLng(48.8,2.1),initialZoom:12,onTap:(_,p)=>onMapTap(p)),
  children:[touchableMarkers(ignoring:ignoring,child:MarkerLayer(markers:[Marker(point:const LatLng(48.8,2.1),width:80,height:40,
    child:GestureDetector(key:const ValueKey('tel-02'),onTap:onMarkerTap,child:const ColoredBox(color:Colors.blue,child:Text('TEL-02'))))]))],
)));

void main() {
  test('markers ignore touches while drawing, picking, measuring or taking a bearing', () {
    expect(markersIgnoreTouches(), isFalse, reason: 'out of these modes, nothing changes');
    expect(markersIgnoreTouches(drawing: true), isTrue);
    expect(markersIgnoreTouches(picking: true), isTrue);
    expect(markersIgnoreTouches(measuring: true), isTrue);
    expect(markersIgnoreTouches(bearing: true), isTrue);
  });

  testWidgets('drawing: a touch on an operator places the point on the map', (t) async {
    final placed=<LatLng>[]; var opened=0;
    await t.pumpWidget(_map(ignoring:true,onMapTap:placed.add,onMarkerTap:()=>opened++));
    await t.pump();
    await t.tapAt(t.getCenter(find.byKey(const ValueKey('tel-02'))));
    await t.pump(const Duration(milliseconds:500));
    expect(opened, 0, reason: 'the sheet of the operator does not open');
    expect(placed, hasLength(1));
    expect(placed.single.latitude, closeTo(48.8,0.01));
    expect(placed.single.longitude, closeTo(2.1,0.01));
  });

  testWidgets('out of a drawing: a touch on an operator opens it, as before', (t) async {
    final placed=<LatLng>[]; var opened=0;
    await t.pumpWidget(_map(ignoring:false,onMapTap:placed.add,onMarkerTap:()=>opened++));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('tel-02')));
    await t.pump(const Duration(milliseconds:500));
    expect(opened, 1);
    expect(placed, isEmpty);
  });

  testWidgets('each drawing tool has a stable identifier for the CI journeys', (t) async {
    final c=DrawingController(eventId:'e',actorId:'T1');
    await t.pumpWidget(MaterialApp(home:Scaffold(body:DrawingToolbar(controller:c,onClose:(){}))));
    final line=find.byWidgetPredicate((w)=>hasTestId(w,'map.draw-line'));
    expect(line, findsOneWidget);
    await t.tap(line);
    await t.pump();
    expect(c.tool, FeatureKind.line);
  });
}
