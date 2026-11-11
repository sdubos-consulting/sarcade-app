import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'tile_files.dart';

TileFiles? _instance;
TileFiles? get tileFiles => _instance ??= IoTileFiles();

/// Folders `<support>/tiles/<kept|cache>/<basemap>/<z>/<x>/<y>.png`.
class IoTileFiles implements TileFiles {
  /// [root] for the tests; else the application support folder.
  IoTileFiles({Directory? root}) : _fixed = root;
  final Directory? _fixed;
  Directory? _root;
  int _writes = 0;

  Future<Directory> _base() async {
    if (_root != null) return _root!;
    final base = _fixed ?? Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}tiles');
    return _root = base;
  }

  static final _safe = RegExp(r'^[a-z0-9][a-z0-9-]{0,39}$');

  Future<File> _file(TileShelf shelf, String basemap, int z, int x, int y) async {
    if (!_safe.hasMatch(basemap)) throw ArgumentError('basemap');
    final s = Platform.pathSeparator;
    return File('${(await _base()).path}$s${shelf.name}$s$basemap$s$z$s$x$s$y.png');
  }

  Future<Directory> _dir(TileShelf shelf, [String? basemap]) async {
    final s = Platform.pathSeparator;
    return Directory('${(await _base()).path}$s${shelf.name}${basemap == null ? '' : '$s$basemap'}');
  }

  @override
  Future<Uint8List?> read(TileShelf shelf, String basemap, int z, int x, int y) async {
    try {
      final f = await _file(shelf, basemap, z, x, y);
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> exists(TileShelf shelf, String basemap, int z, int x, int y) async {
    try {
      return await (await _file(shelf, basemap, z, x, y)).exists();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> write(TileShelf shelf, String basemap, int z, int x, int y, List<int> bytes) async {
    final f = await _file(shelf, basemap, z, x, y);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.part');
    await tmp.writeAsBytes(bytes, flush: false);
    await tmp.rename(f.path);
    // The cache is brought back under its limit now and then.
    if (shelf == TileShelf.cache && ++_writes % 500 == 0) await prune();
  }

  @override
  Future<({int files, int bytes})> usage(TileShelf shelf, String basemap) async {
    final d = await _dir(shelf, basemap);
    var files = 0, bytes = 0;
    if (!await d.exists()) return (files: 0, bytes: 0);
    await for (final e in d.list(recursive: true, followLinks: false)) {
      if (e is File && e.path.endsWith('.png')) {
        files++;
        bytes += await e.length();
      }
    }
    return (files: files, bytes: bytes);
  }

  @override
  Future<void> clear(TileShelf shelf, String basemap) async {
    final d = await _dir(shelf, basemap);
    if (await d.exists()) await d.delete(recursive: true);
  }

  @override
  Future<int> prune({int maxBytes = tileCacheMaxBytes}) async {
    final d = await _dir(TileShelf.cache);
    if (!await d.exists()) return 0;
    final all = <(File, int, DateTime)>[];
    var total = 0;
    await for (final e in d.list(recursive: true, followLinks: false)) {
      if (e is File) {
        final st = await e.stat();
        all.add((e, st.size, st.modified));
        total += st.size;
      }
    }
    if (total <= maxBytes) return 0;
    all.sort((a, b) => a.$3.compareTo(b.$3));
    var removed = 0;
    for (final (f, size, _) in all) {
      if (total <= maxBytes * 0.9) break;
      try {
        await f.delete();
        total -= size;
        removed++;
      } catch (_) {/* in use */}
    }
    return removed;
  }
}
