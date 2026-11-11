/// Images of the base maps on the device (card « Cartes hors connexion sur
/// le téléphone », validated on 9 Nov 2026, choices 3 to 5): the images
/// kept for a zone (« Garder sur ce téléphone ») and those already seen
/// online (cache of 500 MB at most). Files on Android, iPhone and Windows;
/// nothing on the web (choice 7 not retained).
library;

import 'dart:typed_data';

import 'tile_files_stub.dart' if (dart.library.io) 'tile_files_io.dart' as impl;

/// Images already seen online: at most this much, the oldest removed.
const tileCacheMaxBytes = 500 * 1024 * 1024;

enum TileShelf { kept, cache }

/// Storage of the images, one folder per base map and per shelf.
abstract class TileFiles {
  /// Null on the web.
  static TileFiles? get instance => impl.tileFiles;

  Future<Uint8List?> read(TileShelf shelf, String basemap, int z, int x, int y);
  Future<void> write(TileShelf shelf, String basemap, int z, int x, int y, List<int> bytes);
  Future<bool> exists(TileShelf shelf, String basemap, int z, int x, int y);

  /// Number of files and their size of the shelf of [basemap].
  Future<({int files, int bytes})> usage(TileShelf shelf, String basemap);
  Future<void> clear(TileShelf shelf, String basemap);

  /// Removes the oldest images of the cache (every base map) beyond [maxBytes].
  Future<int> prune({int maxBytes = tileCacheMaxBytes});
}
