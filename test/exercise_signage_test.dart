// Signage of the validated mockup (1 Nov 2026): exercise zone with an
// orange dashed contour and its label linked to the circle.
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/bearings/bearing_layers.dart';
import 'package:sarcade_app/src/features/bearings/bearing_models.dart';
import 'package:sarcade_app/src/features/map/drawing/geometry.dart' as geo;

const target = LatLng(48.85, 1.95);
Bearing towards(String id, double d, double from, {bool exercise = false}) {
  final o = geo.destination(target, d, from);
  return Bearing(id: id, eventId: 'e', origin: o, azimuthDeg: geo.bearingDeg(o, target), exercise: exercise, search: 'Balise',
      takenAt: DateTime.utc(2026, 11, 1), createdBy: 'A', updatedBy: 'A', updatedAt: DateTime.utc(2026, 11, 1));
}

int outlinePolylines(List layers) => layers.whereType<PolylineLayer>().fold(0, (n, l) => n + l.polylines.length);

void main() {
  test('exercise: dashed contour and leader line; real search: leader only', () {
    final ex = buildBearingLayers(bearings: [towards('1', 3000, 200, exercise: true), towards('2', 4000, 300), towards('3', 2500, 90)],
        onTapBearing: (_) {}, onTapZone: (_, _) {});
    final real = buildBearingLayers(bearings: [towards('1', 3000, 200), towards('2', 4000, 300), towards('3', 2500, 90)],
        onTapBearing: (_) {}, onTapZone: (_, _) {});
    expect(outlinePolylines(ex), outlinePolylines(real) + 1);
  });
}
