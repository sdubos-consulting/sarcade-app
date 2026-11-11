// Card « Personnes, À proximité : séparer récents et anciens comme dans
// l'onglet Liste », validated on 11 Nov 2026 (choices 1 to 5).
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/stations.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

typedef Item = ({String name, LatLng at, DateTime? time});

void main() {
  final now = DateTime.utc(2026, 11, 11, 21, 55);
  const centre = LatLng(48.80, 2.10);
  final items = <Item>[
    (name: 'PCO-demo', at: const LatLng(48.801, 2.10), time: now.subtract(const Duration(days: 18))),
    (name: 'PC-demo', at: const LatLng(48.802, 2.10), time: now.subtract(const Duration(days: 10))),
    (name: 'F4JPO', at: const LatLng(48.85, 2.10), time: now.subtract(const Duration(minutes: 3))),
    (name: 'F4HKS', at: const LatLng(48.82, 2.10), time: now.subtract(const Duration(minutes: 40))),
    (name: 'Point haut', at: const LatLng(48.83, 2.10), time: null),
  ];

  test('choices 1 to 3: same threshold as the list, both parts sorted by distance', () {
    final s = nearbySections<Item>(centre, items, (i) => i.at, (i) => i.time, now);
    expect(s.recent.map((n) => n.item.name), ['F4HKS', 'Point haut', 'F4JPO']);
    expect(s.older.map((n) => n.item.name), ['PCO-demo', 'PC-demo']);
    // Same rule as the Liste tab: what the list puts in « Anciens ».
    for (final n in s.older) {
      expect(sectionOf(n.item.time!, now), Section.old);
    }
  });

  test('the threshold of the PCO (position_old_min) applies here too', () {
    final s = nearbySections<Item>(centre, items, (i) => i.at, (i) => i.time, now, oldMin: 30);
    expect(s.older.map((n) => n.item.name), ['PCO-demo', 'PC-demo', 'F4HKS']);
  });

  test('old positions no longer push the recent ones out of the 30 lines', () {
    final many = [
      for (var k = 0; k < 40; k++) (name: 'old$k', at: LatLng(48.80 + k / 100000, 2.10), time: now.subtract(const Duration(days: 12))),
      (name: 'F4JPO', at: const LatLng(49.5, 2.10), time: now),
    ];
    final s = nearbySections<Item>(centre, many, (i) => i.at, (i) => i.time, now);
    expect(s.recent.single.item.name, 'F4JPO');
    expect(s.older, hasLength(30));
  });

  test('choice 3 and 4: texts', () {
    S.setLanguage('fr');
    expect(S.t('nearby.older', {'n': '21'}), 'Plus anciens · 21');
    expect(S.t('nearby.noRecent'), 'Personne vue récemment à proximité');
    S.setLanguage('en');
    expect(S.t('nearby.noRecent'), 'Nobody seen nearby recently');
  });
}
