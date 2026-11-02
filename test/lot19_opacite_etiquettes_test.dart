import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_layers.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';
import 'package:sarcade_app/src/features/map/layer_opacity.dart';

// Lot 19, card « Opacité des couches : l'appliquer aussi aux étiquettes »:
// the opacity of a layer applies to its drawing and to its label; a label
// is never more opaque than its drawing.

const _centre = LatLng(48.8, 2.1);

/// Product of the [Opacity] above [finder] (what is really drawn).
double _shown(WidgetTester tester, Finder finder) =>
  tester.widgetList<Opacity>(find.ancestor(of: finder, matching: find.byType(Opacity)))
    .fold(1.0, (v, o) => v * o.opacity);

Widget _map(List<Widget> layers) => MaterialApp(home: Scaffold(body: FlutterMap(
  options: const MapOptions(initialCenter: _centre, initialZoom: 14),
  children: layers)));

MapFeature _feature(String id, FeatureKind kind, List<LatLng> points, {String label = '', double opacity = 1}) => MapFeature(
  id: id, eventId: 'e', kind: kind, points: points, color: 0xFFE53935, strokeWidth: 3, label: label,
  updatedAt: DateTime.utc(2026, 11, 1), opacity: opacity);

void main() {
  testWidgets('APRS at 30 %: dot and callsign at 30 %', (tester) async {
    // Same structure as a station of the map: dot and callsign in one marker.
    await tester.pumpWidget(_map([fadedLayer(0.3, const MarkerLayer(markers: [
      Marker(point: _centre, width: 120, height: 60, child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(key: ValueKey('dot'), width: 14, height: 14, child: ColoredBox(color: Colors.blue)),
        Text('F4GVN-14'),
      ])),
    ]))]));
    expect(_shown(tester, find.byKey(const ValueKey('dot'))), closeTo(0.3, 1e-9));
    expect(_shown(tester, find.text('F4GVN-14')), closeTo(0.3, 1e-9));
  });

  testWidgets('drawings at 40 %: labels of zones, points, texts and measures at 40 % at most', (tester) async {
    final c = DrawingController(eventId: 'e', actorId: 'T1', initial: [
      _feature('z', FeatureKind.zone, const [LatLng(48.801, 2.099), LatLng(48.801, 2.101), LatLng(48.799, 2.100)], label: 'Zone A'),
      _feature('p', FeatureKind.point, const [_centre], label: 'Point B'),
      _feature('t', FeatureKind.text, const [LatLng(48.8005, 2.1)], label: 'Texte C', opacity: 0.5),
      _feature('m', FeatureKind.measure, const [LatLng(48.7995, 2.099), LatLng(48.7995, 2.101)], label: 'Mesure D'),
    ]);
    await tester.pumpWidget(_map(fadedLayers(0.4, buildDrawingLayers(c))));
    final zone = _shown(tester, find.byWidgetPredicate((w) => w is PolygonLayer));
    expect(zone, closeTo(0.4, 1e-9));
    for (final label in ['Zone A', 'Point B', 'Mesure D']) {
      expect(_shown(tester, find.text(label)), closeTo(0.4, 1e-9), reason: label);
    }
    // A text drawn at 50 % in a layer at 40 %: 20 %, never above the layer.
    expect(_shown(tester, find.text('Texte C')), closeTo(0.2, 1e-9));
  });

  testWidgets('a layer at 100 % is drawn as it is', (tester) async {
    await tester.pumpWidget(_map([fadedLayer(1, const MarkerLayer(markers: [
      Marker(point: _centre, width: 120, height: 30, child: Text('TEL-01')),
    ]))]));
    expect(find.ancestor(of: find.text('TEL-01'), matching: find.byType(Opacity)), findsNothing);
    expect(fadedLayers(0.5, const [SizedBox(), SizedBox()]).every((w) => w is Opacity && w.opacity == 0.5), isTrue);
  });
}
