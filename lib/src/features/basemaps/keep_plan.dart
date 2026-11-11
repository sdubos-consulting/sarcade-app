/// What « Garder sur ce téléphone » takes (card « Cartes hors connexion :
/// téléchargement trop long, choisir la finesse, voir la place prise,
/// purger », validated on 11 Nov 2026 with the levels of the complement):
/// a level of precision (Aperçu 13 … Expert 17, Terrain 15 by default), a
/// zone (the view, 10 / 25 / 50 km around me, or the whole zone of the
/// server), and optionally a « détail local » (zoom 16 within 5 km of a
/// point). Pure code: tiles, estimated size, saved plan.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'basemap_models.dart';
import 'offline_tiles.dart';

/// Levels of precision (complement of 11 Nov 2026): each zoom more is about
/// four times the size.
enum KeepLevel {
  overview(13), roads(14), terrain(15), detail(16), expert(17);
  const KeepLevel(this.zoom);
  final int zoom;
  static const fallback = KeepLevel.terrain;
  static KeepLevel byName(String? n) => KeepLevel.values.firstWhere((l) => l.name == n, orElse: () => fallback);
}

/// A level can be chosen when the package of the server goes up to its zoom,
/// or when it is the first level reaching the last zoom of the package (it
/// then takes the package up to that zoom).
bool keepLevelAvailable(KeepLevel l, OfflinePackage p) => l.index == 0 || KeepLevel.values[l.index - 1].zoom < p.maxZoom;

/// [wanted] when it can be chosen, else the finest level available.
KeepLevel keepLevelFor(KeepLevel wanted, OfflinePackage p) =>
    keepLevelAvailable(wanted, p) ? wanted : KeepLevel.values.lastWhere((l) => keepLevelAvailable(l, p));

/// Zones offered.
enum KeepZoneKind { view, km10, km25, km50, server }

double? zoneRadiusKm(KeepZoneKind k) => switch (k) { KeepZoneKind.km10 => 10, KeepZoneKind.km25 => 25, KeepZoneKind.km50 => 50, _ => null };

/// Radius of the « détail local » (complement: 5 km around a point).
const localDetailKm = 5.0;
/// Zoom of the « détail local »: Détail.
const localDetailZoom = 16;

/// West, south, east, north of a square of [km] around a point.
List<double> boundsAround(double lat, double lon, double km) {
  final dLat = km / 111.32;
  final dLon = km / (111.32 * math.cos(lat * math.pi / 180).abs().clamp(0.01, 1.0));
  return [lon - dLon, lat - dLat, lon + dLon, lat + dLat];
}

/// Common part of two zones, or null.
List<double>? intersect(List<double> a, List<double> b) {
  final w = math.max(a[0], b[0]), s = math.max(a[1], b[1]), e = math.min(a[2], b[2]), n = math.min(a[3], b[3]);
  return w < e && s < n ? [w, s, e, n] : null;
}

/// One zone of tiles, zooms [minZoom] to [maxZoom].
typedef KeepPart = ({List<double> bounds, int minZoom, int maxZoom});

/// The plan chosen: [parts] are taken one after the other.
class KeepPlan {
  final KeepLevel level;
  final KeepZoneKind zone;
  final List<double> bounds;
  /// Centre of the « détail local », null without it.
  final ({double lat, double lon})? detailAt;
  final int minZoom, maxZoom;
  const KeepPlan({required this.level, required this.zone, required this.bounds, required this.minZoom, required this.maxZoom, this.detailAt});

  /// The plan of [p] for a level, a zone and a « détail local »; null when
  /// the zone is outside the package of the server. Zooms beyond those of
  /// the package are not offered (the server could not give them).
  static KeepPlan? of(OfflinePackage p, {required KeepLevel level, required KeepZoneKind zone,
      List<double>? view, ({double lat, double lon})? me, ({double lat, double lon})? detailAt}) {
    final pkg = p.bounds;
    if (pkg == null) return null;
    final List<double>? wanted = switch (zone) {
      KeepZoneKind.server => pkg,
      KeepZoneKind.view => view,
      _ => me == null ? null : boundsAround(me.lat, me.lon, zoneRadiusKm(zone)!),
    };
    final b = wanted == null ? null : intersect(wanted, pkg);
    if (b == null) return null;
    return KeepPlan(level: level, zone: zone, bounds: b, minZoom: p.minZoom, maxZoom: math.min(level.zoom, p.maxZoom),
        detailAt: detailAt);
  }

  List<KeepPart> parts(OfflinePackage p) {
    final out = <KeepPart>[(bounds: bounds, minZoom: minZoom, maxZoom: maxZoom)];
    final d = detailAt, pkg = p.bounds;
    final top = math.min(localDetailZoom, p.maxZoom);
    if (d != null && pkg != null && top > maxZoom) {
      final b = intersect(boundsAround(d.lat, d.lon, localDetailKm), pkg);
      if (b != null) out.add((bounds: b, minZoom: maxZoom + 1, maxZoom: top));
    }
    return out;
  }

  Map<String, dynamic> toJson() => {'level': level.name, 'zone': zone.name, 'bounds': bounds, 'min': minZoom, 'max': maxZoom,
    if (detailAt case final d?) 'detail': [d.lat, d.lon]};
  String encode() => jsonEncode(toJson());
  static KeepPlan? decode(String? s) {
    try {
      final j = jsonDecode(s ?? '') as Map<String, dynamic>;
      final b = (j['bounds'] as List).map((v) => (v as num).toDouble()).toList();
      final d = (j['detail'] as List?)?.map((v) => (v as num).toDouble()).toList();
      return KeepPlan(level: KeepLevel.byName(j['level'] as String?),
          zone: KeepZoneKind.values.firstWhere((z) => z.name == j['zone'], orElse: () => KeepZoneKind.server),
          bounds: b, minZoom: (j['min'] as num).toInt(), maxZoom: (j['max'] as num).toInt(),
          detailAt: d == null || d.length != 2 ? null : (lat: d[0], lon: d[1]));
    } catch (_) {
      return null;
    }
  }
}

/// Tiles of [parts]. Their zooms never overlap (the « détail local »
/// starts above the level), so no tile comes twice.
Iterable<({int z, int x, int y})> partsTiles(List<KeepPart> parts) sync* {
  for (final p in parts) {
    for (var z = p.minZoom; z <= p.maxZoom; z++) {
      final r = tileRange(p.bounds, z);
      for (var x = r.x0; x <= r.x1; x++) {
        for (var y = r.y0; y <= r.y1; y++) {
          yield (z: z, x: x, y: y);
        }
      }
    }
  }
}

int partsTileCount(List<KeepPart> parts) {
  var n = 0;
  for (final p in parts) {
    for (var z = p.minZoom; z <= p.maxZoom; z++) {
      final r = tileRange(p.bounds, z);
      n += (r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1);
    }
  }
  return n;
}

/// Estimated size of [tiles] images of [p]: the mean size of an image of
/// the package of the server (its size divided by its images).
int estimatedBytes(OfflinePackage p, int tiles) {
  final all = p.tiles > 0 ? p.tiles : packageTileCount(p);
  if (all <= 0 || p.sizeBytes <= 0) return 0;
  return (p.sizeBytes / all * tiles).round();
}
