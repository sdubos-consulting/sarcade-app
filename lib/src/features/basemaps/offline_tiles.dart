/// Base map without network (card « Cartes hors connexion sur le
/// téléphone », validated on 9 Nov 2026, choices 3 to 5).
///
/// Each image of the map is looked for, in this order:
/// 1. among the images already seen online on this device (cache, 500 MB
///    at most, the oldest removed);
/// 2. online, when the device has a network (then kept in the cache);
/// 3. in the zone kept on this phone (« Garder sur ce téléphone »);
/// 4. in the offline package of the SARCADE server (local network, mobile
///    server);
/// 5. else a lower zoom found above is enlarged (as beyond the zoom of the
///    base map).
/// « Garder sur ce téléphone » takes every image of the package of the
/// server (zone and zooms of the package), one by one: an interrupted
/// download goes on where it stopped.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import 'basemap_models.dart';
import 'tile_files.dart';

/// The device has a network (Wi-Fi, mobile, cable); kept up to date.
final tileNetworkUp = ValueNotifier<bool>(true);
StreamSubscription<List<ConnectivityResult>>? _network;

void _watchNetwork() {
  if (_network != null || kIsWeb) return;
  try {
    _network = Connectivity().onConnectivityChanged.listen((r) {
      tileNetworkUp.value = r.any((e) => e != ConnectivityResult.none);
    });
    unawaited(Connectivity().checkConnectivity().then((r) {
      tileNetworkUp.value = r.any((e) => e != ConnectivityResult.none);
    }, onError: (_) {}));
  } catch (_) {/* no plugin (tests) */}
}

/// Columns and rows of the tiles of zoom [z] covering [bounds] (west,
/// south, east, north), XYZ numbering (same as render_mbtiles.py).
({int x0, int x1, int y0, int y1}) tileRange(List<double> bounds, int z) {
  final n = 1 << z;
  int xOf(double lon) => ((lon + 180) / 360 * n).floor().clamp(0, n - 1);
  int yOf(double lat) {
    final r = lat * math.pi / 180;
    final m = math.log(math.tan(r) + 1 / math.cos(r));
    return ((1 - m / math.pi) / 2 * n).floor().clamp(0, n - 1);
  }
  return (x0: xOf(bounds[0]), x1: xOf(bounds[2]), y0: yOf(bounds[3]), y1: yOf(bounds[1]));
}

/// Every tile of [p], zoom by zoom.
Iterable<({int z, int x, int y})> packageTiles(OfflinePackage p) sync* {
  for (var z = p.minZoom; z <= p.maxZoom; z++) {
    final r = tileRange(p.bounds!, z);
    for (var x = r.x0; x <= r.x1; x++) {
      for (var y = r.y0; y <= r.y1; y++) {
        yield (z: z, x: x, y: y);
      }
    }
  }
}

int packageTileCount(OfflinePackage p) {
  var n = 0;
  for (var z = p.minZoom; z <= p.maxZoom; z++) {
    final r = tileRange(p.bounds!, z);
    n += (r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1);
  }
  return n;
}

String fillTemplate(String template, int z, int x, int y) =>
    template.replaceAll('{z}', '$z').replaceAll('{x}', '$x').replaceAll('{y}', '$y');

/// Where the images come from; replaceable in the tests.
typedef TileFetch = Future<Uint8List?> Function(String url, Map<String, String> headers);

Future<Uint8List?> _httpFetch(String url, Map<String, String> headers) async {
  try {
    final r = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 15));
    return r.statusCode == 200 && r.bodyBytes.isNotEmpty ? r.bodyBytes : null;
  } catch (_) {
    return null;
  }
}

/// Looks for one image along the order of the library comment.
class TileSource {
  TileSource({required this.basemap, this.serverTemplate, this.headers = const {}, this.serverHeaders = const {},
      TileFiles? files, TileFetch? fetch,
      bool Function()? online})
      : files = files ?? TileFiles.instance,
        _fetch = fetch ?? _httpFetch,
        _online = online ?? (() => tileNetworkUp.value);
  final String basemap;
  /// Tiles of the offline package of the server, null without package.
  final String? serverTemplate;
  final Map<String, String> headers;
  /// Cloudflare Access of the SARCADE server, when it is behind it.
  final Map<String, String> serverHeaders;
  final TileFiles? files;
  final TileFetch _fetch;
  final bool Function() _online;

  Future<Uint8List?> _shelves(int z, int x, int y) async {
    final f = files;
    if (f == null) return null;
    return await f.read(TileShelf.cache, basemap, z, x, y) ?? await f.read(TileShelf.kept, basemap, z, x, y);
  }

  Future<Uint8List?> load(String url, int z, int x, int y) async {
    final f = files;
    final cached = await f?.read(TileShelf.cache, basemap, z, x, y);
    if (cached != null) return cached;
    if (_online()) {
      final got = await _fetch(url, headers);
      if (got != null) {
        if (f != null) unawaited(f.write(TileShelf.cache, basemap, z, x, y, got).catchError((_) {}));
        return got;
      }
    }
    final kept = await f?.read(TileShelf.kept, basemap, z, x, y);
    if (kept != null) return kept;
    final server = serverTemplate;
    if (server != null && fillTemplate(server, z, x, y) != url) {
      final got = await _fetch(fillTemplate(server, z, x, y), {...headers, ...serverHeaders});
      if (got != null) return got;
    }
    // A lower zoom enlarged (up to 6 levels above).
    for (var d = 1; d <= 6 && z - d >= 0; d++) {
      final parent = await _shelves(z - d, x >> d, y >> d);
      if (parent != null) return enlargePart(parent, d, x, y);
    }
    return null;
  }
}

/// The part of [parent] (zoom z - [levels]) that covers tile x, y, enlarged
/// to 256 pixels.
Future<Uint8List?> enlargePart(Uint8List parent, int levels, int x, int y) async {
  try {
    final codec = await ui.instantiateImageCodec(parent);
    final img = (await codec.getNextFrame()).image;
    final n = 1 << levels;
    final size = img.width / n;
    final sx = (x % n) * size, sy = (y % n) * size;
    final rec = ui.PictureRecorder();
    ui.Canvas(rec).drawImageRect(img, ui.Rect.fromLTWH(sx, sy, size, size), const ui.Rect.fromLTWH(0, 0, 256, 256),
        ui.Paint()..filterQuality = ui.FilterQuality.medium);
    final out = await rec.endRecording().toImage(256, 256);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    out.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Tile provider of the map: [TileSource] behind flutter_map.
class SarcadeTileProvider extends TileProvider {
  SarcadeTileProvider({required String basemap, String? serverTemplate, Map<String, String> serverHeaders = const {},
      super.headers}) {
    _watchNetwork();
    source = TileSource(basemap: basemap, serverTemplate: serverTemplate, headers: headers, serverHeaders: serverHeaders);
  }
  late final TileSource source;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _SarcadeTileImage(source, getTileUrl(coordinates, options), coordinates.z, coordinates.x, coordinates.y);
}

class _SarcadeTileImage extends ImageProvider<_SarcadeTileImage> {
  const _SarcadeTileImage(this.source, this.url, this.z, this.x, this.y);
  final TileSource source;
  final String url;
  final int z, x, y;

  @override
  Future<_SarcadeTileImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_SarcadeTileImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _codec(decode), scale: 1);

  Future<ui.Codec> _codec(ImageDecoderCallback decode) async {
    final bytes = await source.load(url, z, x, y);
    if (bytes == null) throw StateError('tile $z/$x/$y unavailable');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is _SarcadeTileImage && other.url == url && other.source.basemap == source.basemap;
  @override
  int get hashCode => Object.hash(url, source.basemap);
}

/// « Garder sur ce téléphone »: the zone of the package of a base map,
/// image by image, from the SARCADE server.
class TileKeeper extends ChangeNotifier {
  TileKeeper({this.filesOverride, TileFetch? fetch}) : _fetch = fetch ?? _httpFetch;
  static final instance = TileKeeper();
  /// Storage for the tests; else the one of the device.
  final TileFiles? filesOverride;
  final TileFetch _fetch;
  TileFiles? get files => filesOverride ?? TileFiles.instance;

  /// Base map being kept, and how far.
  String? running;
  int done = 0, total = 0, failed = 0;
  bool _stop = false;

  bool get busy => running != null;
  void cancel() => _stop = true;

  /// Takes every image of [package] not yet on the phone. Returns the
  /// number of images that could not be taken.
  /// [tiles] and [count]: those of the plan chosen (card of 10 and 11 Nov
  /// 2026), else every tile of the package.
  Future<int> keep(Basemap basemap, String serverUrl, {Map<String, String> headers = const {}, int parallel = 6,
      Iterable<({int z, int x, int y})>? tiles, int? count}) async {
    final f = files, p = basemap.package;
    if (f == null || p == null || !p.keepable || busy) return -1;
    running = basemap.id;
    done = 0;
    failed = 0;
    total = tiles == null ? packageTileCount(p) : count ?? tiles.length;
    _stop = false;
    notifyListeners();
    final template = basemap.offlineUrl(serverUrl);
    final it = (tiles ?? packageTiles(p)).iterator;
    var last = DateTime.now();
    Future<void> worker() async {
      while (!_stop) {
        final ({int z, int x, int y}) t;
        if (!it.moveNext()) return;
        t = it.current;
        if (!await f.exists(TileShelf.kept, basemap.id, t.z, t.x, t.y)) {
          final got = await _fetch(fillTemplate(template, t.z, t.x, t.y), headers);
          if (got == null) {
            failed++;
          } else {
            await f.write(TileShelf.kept, basemap.id, t.z, t.x, t.y, got);
          }
        }
        done++;
        if (DateTime.now().difference(last) > const Duration(milliseconds: 300)) {
          last = DateTime.now();
          notifyListeners();
        }
      }
    }
    try {
      await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
    } finally {
      running = null;
      notifyListeners();
    }
    return failed;
  }
}
