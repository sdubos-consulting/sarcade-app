// Card « Cartes hors connexion sur le téléphone » (validated on 9 Nov 2026,
// choices 1 to 5): images already seen, online, kept on the phone, from the
// server, else a lower zoom enlarged; « Garder sur ce téléphone ».
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/basemaps/basemap_models.dart';
import 'package:sarcade_app/src/features/basemaps/keep_on_phone.dart';
import 'package:sarcade_app/src/features/basemaps/offline_tiles.dart';
import 'package:sarcade_app/src/features/basemaps/tile_files.dart';
import 'package:sarcade_app/src/features/basemaps/tile_files_io.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

class MemoryFiles implements TileFiles {
  final shelves = {for (final s in TileShelf.values) s: <String, Uint8List>{}};
  String k(String b, int z, int x, int y) => '$b/$z/$x/$y';
  @override
  Future<Uint8List?> read(TileShelf s, String b, int z, int x, int y) async => shelves[s]![k(b, z, x, y)];
  @override
  Future<void> write(TileShelf s, String b, int z, int x, int y, List<int> bytes) async {
    shelves[s]![k(b, z, x, y)] = Uint8List.fromList(bytes);
  }
  @override
  Future<bool> exists(TileShelf s, String b, int z, int x, int y) async => shelves[s]!.containsKey(k(b, z, x, y));
  @override
  Future<({int files, int bytes})> usage(TileShelf s, String b) async {
    final e = shelves[s]!.entries.where((e) => e.key.startsWith('$b/'));
    return (files: e.length, bytes: e.fold(0, (a, e) => a + e.value.length));
  }
  @override
  Future<void> clear(TileShelf s, String b) async => shelves[s]!.removeWhere((key, _) => key.startsWith('$b/'));
  @override
  Future<int> prune({int maxBytes = tileCacheMaxBytes}) async => 0;
}

Uint8List b(String s) => Uint8List.fromList(s.codeUnits);

const yvelines = OfflinePackage(bounds: [1.44, 48.43, 2.24, 49.09], minZoom: 6, maxZoom: 16, tiles: 35752, sizeBytes: 500 * 1024 * 1024);

void main() {
  setUp(() => S.setLanguage('fr'));

  test('package of the server read from the catalogue', () {
    final m = Basemap.fromJson({'id': 'osm', 'name': 'OpenStreetMap', 'offline_package': {'bounds': '1.44,48.43,2.24,49.09',
      'min_zoom': 6, 'max_zoom': 16, 'tiles': 35752, 'size_bytes': 524288000}});
    expect(m.hasOfflinePackage, isTrue);
    expect(m.package!.keepable, isTrue);
    expect(m.package!.maxZoom, 16);
    expect(Basemap.fromJson(m.toJson()).package!.bounds, [1.44, 48.43, 2.24, 49.09]);
    expect(Basemap.fromJson({'id': 'osm'}).package, isNull);
  });

  test('same tiles as the server tool (render_mbtiles.py: 35 752 for the Yvelines, zooms 6 to 16)', () {
    expect(packageTileCount(yvelines), 35752);
    expect(packageTiles(yvelines).length, 35752);
    final r = tileRange(yvelines.bounds!, 16);
    expect([r.x0, r.x1, r.y0, r.y1], [33030, 33175, 22481, 22663]);
  });

  test('order: seen before, online, kept, server; online images kept in the cache', () async {
    final files = MemoryFiles();
    var online = true;
    final asked = <String>[];
    final net = <String, Uint8List>{'web/10/1/2': b('web'), 'srv/10/3/4': b('srv')};
    final src = TileSource(basemap: 'osm', serverTemplate: 'srv/{z}/{x}/{y}', files: files, online: () => online,
        fetch: (u, _) async {
          asked.add(u);
          return net[u];
        });
    expect(await src.load('web/10/1/2', 10, 1, 2), b('web'));
    await Future<void>.delayed(Duration.zero);
    expect(await files.read(TileShelf.cache, 'osm', 10, 1, 2), b('web'), reason: 'kept in the cache');
    asked.clear();
    expect(await src.load('web/10/1/2', 10, 1, 2), b('web'));
    expect(asked, isEmpty, reason: 'seen before: no network');
    online = false;
    await files.write(TileShelf.kept, 'osm', 10, 5, 6, b('kept'));
    expect(await src.load('web/10/5/6', 10, 5, 6), b('kept'));
    expect(asked, isEmpty, reason: 'no network: Internet not asked');
    expect(await src.load('web/10/3/4', 10, 3, 4), b('srv'), reason: 'package of the server');
    expect(await src.load('web/10/9/9', 10, 9, 9), isNull);
  });

  testWidgets('beyond the zoom kept: the image of the lower zoom enlarged', (t) async {
    await t.runAsync(() async {
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, 256, 256), ui.Paint()..color = const ui.Color(0xFF336699));
      final img = await rec.endRecording().toImage(256, 256);
      final png = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      final files = MemoryFiles();
      await files.write(TileShelf.kept, 'osm', 16, 33100, 22560, png);
      final src = TileSource(basemap: 'osm', files: files, online: () => false, fetch: (_, _) async => null);
      final out = await src.load('web/18/132401/90242', 18, 132401, 90242);
      expect(out, isNotNull);
      final c = await ui.instantiateImageCodec(out!);
      expect((await c.getNextFrame()).image.width, 256);
    });
  });

  test('keep: every image of the package, one by one, resumed after a stop', () async {
    final files = MemoryFiles();
    const small = OfflinePackage(bounds: [1.9, 48.7, 2.0, 48.8], minZoom: 10, maxZoom: 12, tiles: 0, sizeBytes: 1000);
    const m = Basemap(id: 'osm', name: 'OSM', attribution: '', hasOfflinePackage: true, package: small);
    var calls = 0;
    final keeper = TileKeeper(filesOverride: files, fetch: (u, _) async {
      calls++;
      return b(u);
    });
    expect(await keeper.keep(m, 'https://s'), 0);
    final total = packageTileCount(small);
    expect((await files.usage(TileShelf.kept, 'osm')).files, total);
    final first = packageTiles(small).first;
    expect(await files.read(TileShelf.kept, 'osm', first.z, first.x, first.y),
        b('https://s/api/v0.1/basemaps/osm/tiles/${first.z}/${first.x}/${first.y}'));
    calls = 0;
    expect(await keeper.keep(m, 'https://s'), 0);
    expect(calls, 0, reason: 'already on the phone: nothing taken again');
  });

  test('files on the device: write, read, usage, cache brought under its limit', () async {
    final dir = await Directory.systemTemp.createTemp('tiles');
    addTearDown(() => dir.delete(recursive: true));
    final f = IoTileFiles(root: dir);
    await f.write(TileShelf.kept, 'osm', 10, 1, 2, List.filled(100, 1));
    expect(await f.read(TileShelf.kept, 'osm', 10, 1, 2), hasLength(100));
    expect(await f.usage(TileShelf.kept, 'osm'), (files: 1, bytes: 100));
    for (var i = 0; i < 10; i++) {
      await f.write(TileShelf.cache, 'osm', 12, i, 0, List.filled(100, 1));
    }
    expect(await f.prune(maxBytes: 500), greaterThan(4));
    expect((await f.usage(TileShelf.cache, 'osm')).bytes, lessThanOrEqualTo(500));
    await f.clear(TileShelf.kept, 'osm');
    expect((await f.usage(TileShelf.kept, 'osm')).files, 0);
    expect(() => f.write(TileShelf.kept, '../x', 1, 1, 1, [1]), throwsArgumentError);
  });

  testWidgets('panel: offer with the size, Wi-Fi asked before the mobile network', (t) async {
    const small = OfflinePackage(bounds: [1.9, 48.7, 2.0, 48.8], minZoom: 10, maxZoom: 11, tiles: 0, sizeBytes: 3 * 1024 * 1024);
    const m = Basemap(id: 'osm', name: 'OSM', attribution: '', hasOfflinePackage: true, package: small);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: KeepOnPhoneTile(basemap: m, serverUrl: 'https://s', onWifi: () async => false))));
    await t.pump();
    expect(find.text('Garder sur ce téléphone'), findsOneWidget);
    expect(find.textContaining('environ 3 Mo'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('keep-start')));
    await t.pumpAndSettle();
    expect(find.text('Pas de Wi-Fi'), findsOneWidget);
    await t.tap(find.text('Annuler'));
    await t.pumpAndSettle();
    expect(TileKeeper.instance.busy, isFalse);
    expect(sizeLabel(512 * 1024 * 1024), '512 Mo');
    expect(sizeLabel(1288490189), '1,2 Go');
  });
}
