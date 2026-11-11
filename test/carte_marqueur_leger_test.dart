// Card « Carte : marqueur d'une personne plus léger » (validated on 9 Nov 2026).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/marker_style.dart';

void main() {
  test('names from zoom 15, rounds alone further', () {
    expect(markerNamesShown(14.9), isFalse);
    expect(markerNamesShown(15), isTrue);
    expect(markerNamesShown(null), isTrue, reason: 'no camera yet');
  });

  test('beyond 24 h, a small grey point', () {
    final now = DateTime.utc(2026, 11, 9, 22);
    expect(markerForgotten(now.subtract(const Duration(hours: 4)), now), isFalse);
    expect(markerForgotten(now.subtract(const Duration(hours: 25)), now), isTrue);
  });

  test('one round: status as the ring, no dot, no struck name, no frame', () {
    final src = File('lib/src/features/map/operational_map_page.dart').readAsStringSync();
    final icon = src.substring(src.indexOf('Widget _stationIcon('), src.indexOf('/// Station markers, grouped'));
    expect(icon, isNot(contains('withStatusDot')));
    expect(icon, contains('operatorStatusColors'));
    final marker = src.substring(src.indexOf('Marker _stationMarker('), src.indexOf('String _sourceLabel('));
    expect(marker, isNot(contains('lineThrough')));
    expect(marker, contains('markerTextHalo'));
    expect(marker, contains('markerNamesShown'));
  });
}
