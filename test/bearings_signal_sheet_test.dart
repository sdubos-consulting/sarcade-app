// 1 Nov 2026: one search whatever the apostrophe; sheets at most 560 px wide.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/bearings/bearing_models.dart';
import 'package:sarcade_app/src/ui/theme.dart';

Bearing b(String id, String search, int minute) => Bearing(id: id, eventId: 'e', origin: const LatLng(48.8, 2.1), azimuthDeg: 10,
    search: search, takenAt: DateTime.utc(2026, 10, 31, 23, minute), createdBy: 'A', updatedBy: 'A', updatedAt: DateTime.utc(2026, 11, 1));

void main() {
  test('« Balise d\'exercice » and « Balise d’exercice » are one search, named after the latest', () {
    expect(searchKey("121,375 MHz · Balise d'exercice"), searchKey('121,375  MHz · balise d’EXERCICE'));
    final g = bySearch([b('1', "121,375 MHz · Balise d'exercice", 1), b('2', '121,375 MHz · Balise d’exercice', 5), b('3', 'Autre', 2)]);
    expect(g.keys, unorderedEquals(['121,375 MHz · Balise d’exercice', 'Autre']));
    expect(g['121,375 MHz · Balise d’exercice']!.map((x) => x.id), ['1', '2']);
  });

  test('sheets at the bottom: at most 560 px wide', () {
    expect(bottomSheetMaxWidth, 560);
    expect(dayTheme().bottomSheetTheme.constraints!.maxWidth, 560);
    expect(nightTheme().bottomSheetTheme.constraints!.maxWidth, 560);
  });
}
