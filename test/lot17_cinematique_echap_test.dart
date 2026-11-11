import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/cinematique_escape.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';

// Card « Échap : fiche d'opérateur et forme en cours » (lot 17, constat L3):
// a first Échap drops the shape being drawn, a second one closes the bar.
void main() {
  test('line with two points: 1st Échap drops the shape, 2nd closes the bar', () {
    var closed=0;
    final c=DrawingController(eventId:'e',actorId:'T1')..selectTool(FeatureKind.line);
    c.tapAt(const LatLng(48.80,2.10));
    c.tapAt(const LatLng(48.81,2.11));
    expect(c.draft, hasLength(2));

    expect(escapeDrawing(c,closeBar:()=>closed++), isTrue);
    expect(c.draft, isEmpty, reason: 'the shape being drawn is dropped');
    expect(c.tool, FeatureKind.line, reason: 'the tool stays chosen');
    expect(closed, 0, reason: 'the bar stays open');
    expect(c.features, isEmpty, reason: 'nothing saved');

    expect(escapeDrawing(c,closeBar:()=>closed++), isTrue);
    expect(c.isDrawing, isFalse);
    expect(closed, 1, reason: 'the second Échap closes the bar');
  });

  test('tool chosen, nothing drawn: Échap closes the bar at once', () {
    var closed=0;
    final c=DrawingController(eventId:'e',actorId:'T1')..selectTool(FeatureKind.zone);
    expect(escapeDrawing(c,closeBar:()=>closed++), isTrue);
    expect(c.isDrawing, isFalse);
    expect(closed, 1);
  });

  test('no tool: Échap goes on to the next thing open', () {
    var closed=0;
    final c=DrawingController(eventId:'e',actorId:'T1');
    expect(escapeDrawing(c,closeBar:()=>closed++), isFalse);
    expect(closed, 0);
  });
}
