// Drawing help as a thin line of the bar (1 Nov 2026): full the first 3
// times of a tool, then behind ⓘ; none for Point and Texte.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_toolbar.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';

Future<void> _pump(WidgetTester t, DrawingController c, int seen, List<FeatureKind> shown) =>
    t.pumpWidget(MaterialApp(home: Scaffold(body: DraftLine(controller: c, seen: seen, onShown: shown.add))));

void main() {
  testWidgets('circle: full help first, then ⓘ', (t) async {
    final c = DrawingController(eventId: 'e', actorId: 'a')..selectTool(FeatureKind.circle);
    final shown = <FeatureKind>[];
    await _pump(t, c, 0, shown);
    await t.pump();
    expect(find.byKey(const ValueKey('draft-line')), findsOneWidget);
    expect(find.text(toolHint(FeatureKind.circle)), findsOneWidget);
    expect(shown, [FeatureKind.circle]);
    await _pump(t, c, fullHintTimes, shown);
    expect(find.text(toolHint(FeatureKind.circle)), findsNothing);
    expect(find.byKey(const ValueKey('draft-help')), findsOneWidget);
  });

  testWidgets('point: no help', (t) async {
    final c = DrawingController(eventId: 'e', actorId: 'a')..selectTool(FeatureKind.point);
    final shown = <FeatureKind>[];
    await _pump(t, c, 0, shown);
    await t.pump();
    expect(find.text(toolHint(FeatureKind.point)), findsNothing);
    expect(shown, isEmpty);
  });
}
