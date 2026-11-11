import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_layers.dart';
import 'package:sarcade_app/src/features/map/drawing/label_declutter.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';
import 'package:sarcade_app/src/features/map/layer_opacity.dart';

// Lot 20, card « Carte : étiquettes des objets dessinés qui se chevauchent
// entre elles et avec les opérateurs »: operators first, then the drawn
// objects; a label overlapping a label of higher priority is hidden and
// comes back when zooming in; always shown when its object is selected.

const _a = LatLng(48.8, 2.1);
const _b = LatLng(48.8, 2.1003); // 3 px from _a at zoom 14, 112 px at zoom 19

MapFeature _circle(String id, LatLng at, String label, {int minute = 0, double opacity = 1}) => MapFeature(
  id: id, eventId: 'e', kind: FeatureKind.circle, points: [at], radiusM: 5, color: 0xFF1E88E5, strokeWidth: 2,
  label: label, updatedAt: DateTime.utc(2026, 11, 2, 8, minute), opacity: opacity);

Rect _box(double left, double top, [double width = 40, double height = 20]) => Rect.fromLTWH(left, top, width, height);

void main() {
  group('masking algorithm', () {
    test('labels apart: all shown', () {
      expect(visibleLabels([LabelCandidate(_box(0, 0)), LabelCandidate(_box(100, 0)), LabelCandidate(_box(0, 50))]), {0, 1, 2});
    });

    test('two labels overlapping: the first one wins, the second is hidden', () {
      expect(visibleLabels([LabelCandidate(_box(0, 0)), LabelCandidate(_box(20, 10))]), {0});
    });

    test('a hidden label does not hide the following ones', () {
      // 1 overlaps 0 and is hidden; 2 overlaps only 1: shown.
      expect(visibleLabels([LabelCandidate(_box(0, 0)), LabelCandidate(_box(30, 0)), LabelCandidate(_box(60, 0))]), {0, 2});
    });

    test('touching boxes do not overlap', () {
      expect(visibleLabels([LabelCandidate(_box(0, 0)), LabelCandidate(_box(40, 0))]), {0, 1});
    });

    test('operators first: a label over an operator is hidden', () {
      expect(visibleLabels([LabelCandidate(_box(10, 10)), LabelCandidate(_box(200, 0))], blockers: [_box(0, 0, 60, 64)]), {1});
    });

    test('a selected label is always shown, over an operator or a label placed before', () {
      final shown = visibleLabels([LabelCandidate(_box(0, 0)), LabelCandidate(_box(10, 5), forced: true)], blockers: [_box(0, 0, 60, 64)]);
      expect(shown, {1});
    });

    test('a selected label wins over a label of higher order', () {
      expect(visibleLabels([LabelCandidate(_box(0, 0)), LabelCandidate(_box(10, 5), forced: true)]), {1});
    });

    test('nothing to place', () {
      expect(visibleLabels(const []), isEmpty);
    });
  });

  group('boxes in screen pixels', () {
    test('drawn label: centred, or under the point of the map', () {
      final c = labelBox(const Offset(100, 100), 'Zone A');
      expect(c.center, const Offset(100, 100));
      expect(c.width, 6 * 7.0 + 14);
      expect(c.height, labelChipHeight);
      final below = labelBox(const Offset(100, 100), 'Zone A', below: true);
      expect(below.top, greaterThanOrEqualTo(100));
    });

    test('a long label is at most as wide as its marker', () {
      expect(labelBox(Offset.zero, 'x' * 100).width, labelMarkerWidth);
    });

    test('operator: box above its position, narrower than its marker for a short name', () {
      final r = operatorBox(const Offset(100, 100), 'F4ABC');
      expect(r.bottom, 100);
      expect(r.top, 100 - operatorMarkerHeight);
      expect(r.center.dx, 100);
      expect(r.width, lessThan(operatorMarkerWidth));
      expect(operatorBox(Offset.zero, 'x' * 60).width, operatorMarkerWidth);
    });

    test('Texte object: inside its marker', () {
      final r = textObjectBox(Offset.zero, 'x' * 200, 15, markerWidth: 200, markerHeight: 48);
      expect(r.width, 200);
      expect(r.height, lessThanOrEqualTo(48));
    });
  });

  group('on the map', () {
    late MapController m;
    Widget map(DrawingController c, {List<LabelOperator> operators = const [], double opacity = 1}) => MaterialApp(home: Scaffold(
      body: ListenableBuilder(listenable: c, builder: (_, _) => FlutterMap(mapController: m,
        options: const MapOptions(initialCenter: _a, initialZoom: 14),
        children: fadedLayers(opacity, buildDrawingLayers(c, operators: operators))))));

    setUp(() => m = MapController());

    testWidgets('two labels overlapping: the most recent one shown, the other comes back when zooming in', (t) async {
      final c = DrawingController(eventId: 'e', actorId: 'T1', initial: [_circle('a', _a, 'Cercle A'), _circle('b', _b, 'Cercle B', minute: 1)]);
      await t.pumpWidget(map(c));
      expect(find.text('Cercle B'), findsOneWidget);
      expect(find.text('Cercle A'), findsNothing, reason: 'hidden, its circle stays on the map');
      expect(find.byType(CircleLayer), findsOneWidget);
      m.move(_a, 19);
      await t.pump();
      expect(find.text('Cercle A'), findsOneWidget);
      expect(find.text('Cercle B'), findsOneWidget);
    });

    testWidgets('selected object: its label shown even when it overlaps', (t) async {
      final c = DrawingController(eventId: 'e', actorId: 'T1', initial: [_circle('a', _a, 'Cercle A'), _circle('b', _b, 'Cercle B', minute: 1)]);
      c.select('a');
      await t.pumpWidget(map(c));
      expect(find.text('Cercle A'), findsOneWidget);
      expect(find.text('Cercle B'), findsNothing);
    });

    testWidgets('a label under an operator is hidden', (t) async {
      final c = DrawingController(eventId: 'e', actorId: 'T1', initial: [_circle('a', _a, 'Cercle A')]);
      await t.pumpWidget(map(c, operators: const [(point: _a, label: 'F4ABC')]));
      expect(find.text('Cercle A'), findsNothing);
      await t.pumpWidget(map(c));
      expect(find.text('Cercle A'), findsOneWidget);
    });

    testWidgets('a Texte object stays shown and hides a label under it', (t) async {
      final text = MapFeature(id: 't', eventId: 'e', kind: FeatureKind.text, points: const [_a], color: 0xFF1E88E5, strokeWidth: 2,
        label: 'PC avancé', updatedAt: DateTime.utc(2026, 11, 2, 8));
      final c = DrawingController(eventId: 'e', actorId: 'T1', initial: [text, _circle('b', _b, 'Cercle B', minute: 1)]);
      await t.pumpWidget(map(c));
      expect(find.text('PC avancé'), findsOneWidget);
      expect(find.text('Cercle B'), findsNothing);
    });

    testWidgets('measure of 2 points: name and length in one label', (t) async {
      final measure = MapFeature(id: 'm', eventId: 'e', kind: FeatureKind.measure, points: const [_a, _b], color: 0xFF1E88E5,
        strokeWidth: 2, label: 'Mesure', updatedAt: DateTime.utc(2026, 11, 2, 8));
      await t.pumpWidget(map(DrawingController(eventId: 'e', actorId: 'T1', initial: [measure])));
      expect(find.text('Mesure · 22 m'), findsOneWidget);
    });

    testWidgets('the opacity of the layer still applies to the labels shown', (t) async {
      final c = DrawingController(eventId: 'e', actorId: 'T1', initial: [_circle('a', _a, 'Cercle A')]);
      await t.pumpWidget(map(c, opacity: 0.4));
      final shown = t.widgetList<Opacity>(find.ancestor(of: find.text('Cercle A'), matching: find.byType(Opacity)))
        .fold(1.0, (v, o) => v * o.opacity);
      expect(shown, closeTo(0.4, 1e-9));
    });
  });
}
