/// Search of the map, lot 19 (card « Recherche : nœuds MeshCore et avions »,
/// validated on 1 Nov 2026, 21 h 42): the MeshCore nodes heard by the
/// module of this device (name and start of the public key; kind and age of
/// the last advert in words). A node with a position: the map on it and its
/// floating card (« Écrire » for a companion); without position: Outils ›
/// MeshCore on this node. The aircraft (module ADRASEC) are searched by
/// lib/src/modules/adrasec/adsb/adsb_search.dart.
library;

import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../meshcore/meshcore_link.dart';
import '../meshcore/meshcore_map.dart' show meshCoreHasPosition, meshCoreShowOnMap;
import '../meshcore/meshcore_page.dart' show meshCoreAge;
import '../meshcore/meshcore_protocol.dart';
import 'map_search.dart';

export '../meshcore/meshcore_protocol.dart' show MeshCoreContact;

/// Placeholder point of a node without position (never shown).
const _nowhere=LatLng(0,0);

/// « Compagnon · il y a 3 min », « · sans position » when it has none.
String meshCoreSearchSubtitle(MeshCoreContact c,DateTime now)=>[
  S.t('mesh.kind.${c.kind}'),meshCoreAge(c.lastAdvert,now),if(!meshCoreHasPosition(c))S.t('mesh.noPosition')].join(' · ');

/// The MeshCore nodes heard by the module of this device.
List<Searchable> meshCoreSearchables(Iterable<MeshCoreContact> nodes,DateTime now)=>[
  for(final c in nodes)Searchable(SearchKind.meshNode,c.name.isEmpty?c.shortKey:c.name,'',
    meshCoreHasPosition(c)?LatLng(c.lat!,c.lon!):_nowhere,
    prefix:c.key,ref:c.key,placed:meshCoreHasPosition(c),subtitle:meshCoreSearchSubtitle(c,now))];

/// What the map does with a MeshCore node found; false for the other
/// results (the map moves to their point as before; the aircraft: see
/// adsb_search.dart of the module ADRASEC). [nodes]: those of the module of
/// this device by default.
bool openFoundOnMap(SearchResult r,{required MapController map,required void Function(MeshCoreContact) openNodeInTool,
    Iterable<MeshCoreContact>? nodes}){
  switch(r.kind){
    case SearchKind.meshNode:
      final c=(nodes??MeshCoreLink.instance.contacts).where((x)=>x.key==r.ref).firstOrNull;
      if(c==null)return true;
      if(r.placed&&meshCoreHasPosition(c)){unawaited(meshCoreShowOnMap(map,c));}else{openNodeInTool(c);}
      return true;
    default:
      return false;
  }
}
