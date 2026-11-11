/// Nodes of the LoRa networks (MeshCore, Meshtastic) grouped on the map
/// (card « Carte : regrouper les ronds des nœuds MeshCore et Meshtastic »,
/// validated on 9 Nov 2026): where they touch, one round with the number;
/// a touch zooms on the group; each node alone from zoom 14. Never grouped:
/// the selected node and a node heard in the last 15 minutes. Same
/// grouping as the stations (clusterOnScreen).
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'stations.dart' show clusterOnScreen;

/// From this zoom every node is shown alone.
const nodeClusterUntilZoom = 14.0;

/// A node heard more recently than this stays alone, with its colour.
const nodeRecentlyHeard = Duration(minutes: 15);

/// Groups of nodes for the camera [cam]: a list of one for a node shown
/// alone. [alone]: never grouped (selected, heard recently).
List<List<T>> groupNodes<T>(MapCamera? cam, List<T> nodes, LatLng Function(T) at, bool Function(T) alone) {
  if (cam == null || cam.zoom >= nodeClusterUntilZoom) return [for (final n in nodes) [n]];
  final single = [for (final n in nodes) if (alone(n)) [n]];
  final rest = [for (final n in nodes) if (!alone(n)) n];
  return [...clusterOnScreen(rest, (n) => cam.latLngToScreenOffset(at(n))), ...single];
}

/// Most frequent value of [kinds] (the icon of a group).
String mostFrequent(Iterable<String> kinds) {
  final count = <String, int>{};
  for (final k in kinds) {
    count[k] = (count[k] ?? 0) + 1;
  }
  return count.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

/// Middle of the positions of a group.
LatLng groupCentre(Iterable<LatLng> points) {
  final l = points.toList();
  return LatLng(l.map((p) => p.latitude).reduce((a, b) => a + b) / l.length,
      l.map((p) => p.longitude).reduce((a, b) => a + b) / l.length);
}

/// Round of a group: the colour of the layer, the icon of the most frequent
/// kind, the number; a touch zooms so that the nodes come apart.
Marker nodeGroupMarker({required Key key, required List<LatLng> points, required Color colour, required IconData icon,
    required MapController map, bool square = false}) {
  return Marker(point: groupCentre(points), width: 46, height: 46, child: GestureDetector(key: key,
    onTap: () {
      try {
        map.fitCamera(CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(60), maxZoom: nodeClusterUntilZoom + 1));
      } catch (_) {/* map not ready */}
    },
    child: Container(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95),
        shape: square ? BoxShape.rectangle : BoxShape.circle, borderRadius: square ? BorderRadius.circular(10) : null,
        border: Border.all(color: colour, width: 2.5), boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black26)]),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 14, color: colour),
        Text('${points.length}', style: TextStyle(fontSize: 13, height: 1.1, fontWeight: FontWeight.w800, color: colour)),
      ]),
    )));
}
