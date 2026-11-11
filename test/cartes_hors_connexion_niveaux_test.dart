// Card « Cartes hors connexion : téléchargement trop long, choisir la
// finesse, voir la place prise, purger » (10 Nov 2026) and its complement
// of 11 Nov 2026: levels Aperçu → Expert, Terrain by default, zone, détail
// local, room taken, erase with confirmation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/basemaps/basemap_models.dart';
import 'package:sarcade_app/src/features/basemaps/keep_on_phone.dart';
import 'package:sarcade_app/src/features/basemaps/keep_plan.dart';
import 'package:sarcade_app/src/features/basemaps/offline_tiles.dart';
import 'package:sarcade_app/src/features/basemaps/tile_files.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

import 'cartes_hors_connexion_test.dart' show MemoryFiles;

// The package of the server measured on 10 Nov 2026: 464 Mo up to zoom 16.
const yvelines = OfflinePackage(bounds: [1.44, 48.43, 2.24, 49.09], minZoom: 6, maxZoom: 16, tiles: 35752, sizeBytes: 464 * 1024 * 1024);

int mb(KeepLevel l, {KeepZoneKind zone = KeepZoneKind.server, ({double lat, double lon})? me, ({double lat, double lon})? detail}) {
  final plan = KeepPlan.of(yvelines, level: l, zone: zone, me: me, detailAt: detail)!;
  return estimatedBytes(yvelines, partsTileCount(plan.parts(yvelines))) ~/ (1024 * 1024);
}

void main() {
  setUp(() => S.setLanguage('fr'));

  test('sizes of the levels for the whole zone, about ×4 per zoom (table of 11 Nov)', () {
    expect(mb(KeepLevel.detail), 464, reason: 'measured');
    expect(mb(KeepLevel.terrain), inInclusiveRange(100, 130), reason: '≈ 115 Mo');
    expect(mb(KeepLevel.roads), inInclusiveRange(25, 35), reason: '≈ 30 Mo');
    expect(mb(KeepLevel.overview), inInclusiveRange(5, 10), reason: '≈ 7 Mo, under a minute on Wi-Fi');
    expect(KeepLevel.fallback, KeepLevel.terrain);
  });

  test('Expert only when the server gives zoom 17', () {
    expect(keepLevelAvailable(KeepLevel.detail, yvelines), isTrue);
    expect(keepLevelAvailable(KeepLevel.expert, yvelines), isFalse);
    expect(keepLevelAvailable(KeepLevel.expert, const OfflinePackage(bounds: [1, 48, 2, 49], maxZoom: 17)), isTrue);
    expect(keepLevelFor(KeepLevel.terrain, const OfflinePackage(bounds: [1, 48, 2, 49], maxZoom: 14)), KeepLevel.roads);
  });

  test('zones: around me (10, 25, 50 km), the view, inside the zone of the server', () {
    const me = (lat: 48.80, lon: 2.13);
    expect(mb(KeepLevel.terrain, zone: KeepZoneKind.km10, me: me), lessThan(mb(KeepLevel.terrain, zone: KeepZoneKind.km25, me: me)));
    expect(mb(KeepLevel.terrain, zone: KeepZoneKind.km50, me: me), lessThanOrEqualTo(mb(KeepLevel.terrain)));
    final view = KeepPlan.of(yvelines, level: KeepLevel.terrain, zone: KeepZoneKind.view, view: [2.0, 48.7, 2.1, 48.8])!;
    expect(view.bounds, [2.0, 48.7, 2.1, 48.8]);
    expect(KeepPlan.of(yvelines, level: KeepLevel.terrain, zone: KeepZoneKind.km10, me: (lat: 45.0, lon: 5.0)), isNull,
        reason: 'far from the zone of the server');
    expect(KeepPlan.of(yvelines, level: KeepLevel.terrain, zone: KeepZoneKind.km10), isNull, reason: 'position unknown');
  });

  test('détail local: zoom 16 within 5 km, on top of a lighter level', () {
    const pc = (lat: 48.80, lon: 2.13);
    final base = mb(KeepLevel.roads), withDetail = mb(KeepLevel.roads, detail: pc);
    expect(withDetail, greaterThan(base));
    expect(withDetail, lessThan(mb(KeepLevel.terrain)), reason: 'much less than the whole zone in Terrain');
    final plan = KeepPlan.of(yvelines, level: KeepLevel.roads, zone: KeepZoneKind.server, detailAt: pc)!;
    final parts = plan.parts(yvelines);
    expect(parts.map((p) => (p.minZoom, p.maxZoom)), [(6, 14), (15, 16)]);
    expect(partsTiles(parts).length, partsTileCount(parts));
    expect(partsTiles(parts).toSet().length, partsTileCount(parts), reason: 'no tile twice');
  });

  test('plan kept and read back', () {
    final plan = KeepPlan.of(yvelines, level: KeepLevel.roads, zone: KeepZoneKind.km25, me: (lat: 48.8, lon: 2.1), detailAt: (lat: 48.8, lon: 2.1))!;
    final back = KeepPlan.decode(plan.encode())!;
    expect(back.encode(), plan.encode());
    expect(back.level, KeepLevel.roads);
    expect(KeepPlan.decode('nonsense'), isNull);
  });

  test('the keeper takes only the images of the plan', () async {
    final files = MemoryFiles();
    final keeper = TileKeeper(filesOverride: files, fetch: (url, h) async => null);
    const m = Basemap(id: 'osm', name: 'OSM', attribution: '', hasOfflinePackage: true, package: yvelines);
    final plan = KeepPlan.of(yvelines, level: KeepLevel.overview, zone: KeepZoneKind.km10, me: (lat: 48.8, lon: 2.1))!;
    final n = partsTileCount(plan.parts(yvelines));
    final failed = await keeper.keep(m, 'https://s', tiles: partsTiles(plan.parts(yvelines)), count: n);
    expect(keeper.total, n);
    expect(failed, n);
    expect(n, lessThan(packageTileCount(yvelines) ~/ 100));
  });

  testWidgets('Terrain by default with its size; room taken by all, erase with confirmation', (t) async {
    final files = MemoryFiles();
    for (final b in ['osm', 'topo']) {
      for (var i = 0; i < 4; i++) {
        await files.write(TileShelf.kept, b, 6, i, 0, List.filled(1024 * 1024, 1));
      }
    }
    const osm = Basemap(id: 'osm', name: 'OSM', attribution: '', hasOfflinePackage: true, package: yvelines);
    const topo = Basemap(id: 'topo', name: 'Topo', attribution: '', hasOfflinePackage: true, package: yvelines);
    final prefs = <String, String?>{};
    await t.pumpWidget(MaterialApp(home: Scaffold(body: KeepOnPhoneTile(basemap: osm, serverUrl: 'https://s', all: const [osm, topo],
      prefs: (read: (k) => prefs[k], save: (k, v) async => prefs[k] = v), keeper: TileKeeper(filesOverride: files)))));
    await t.pumpAndSettle();
    expect(find.textContaining('Incomplète'), findsOneWidget);
    expect(find.text('Toutes les cartes gardées : 8 Mo'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('keep-delete')));
    await t.pumpAndSettle();
    expect(find.text('Effacer cette carte ?'), findsOneWidget);
    await t.tap(find.text('Annuler'));
    await t.pumpAndSettle();
    expect((await files.usage(TileShelf.kept, 'osm')).files, 4, reason: 'nothing erased without confirmation');
    await t.tap(find.byKey(const ValueKey('keep-delete-all')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('keep-erase-ok')));
    await t.pumpAndSettle();
    expect((await files.usage(TileShelf.kept, 'osm')).files, 0);
    expect((await files.usage(TileShelf.kept, 'topo')).files, 0);
    // The choice: Terrain selected, with its size.
    await t.tap(find.byKey(const ValueKey('keep-choose')));
    await t.pumpAndSettle();
    final terrain = t.widget<RadioListTile<KeepLevel>>(find.byKey(const ValueKey('keep-level-terrain')));
    expect(RadioGroup.maybeOf<KeepLevel>(t.element(find.byKey(const ValueKey('keep-level-terrain'))))?.groupValue, KeepLevel.terrain);
    expect(terrain.subtitle, isA<Text>());
    expect((terrain.subtitle! as Text).data, startsWith('chemins, lieux-dits, bâtiments en masse · ≈ 1'));
    expect(find.text('non fourni par ce serveur'), findsOneWidget, reason: 'Expert, the server stops at 16');
    expect(find.textContaining('Télécharger (≈ 1'), findsOneWidget);
  });
}
