/// Search of the map, lot 19 (card « Recherche : nœuds MeshCore et avions »,
/// validated on 1 Nov 2026, 21 h 42): the MeshCore nodes heard by the
/// module of this device (name and start of the public key; kind and age of
/// the last advert in words) and the aircraft received now (module ADRASEC;
/// callsign and 24-bit ICAO code; altitude and kind in words). A node with a
/// position: the map on it and its floating card (« Écrire » for a
/// companion); without position: Outils › MeshCore on this node. An
/// aircraft: the map on it, its floating sheet (« Suivre » there), the
/// layer Aéronefs switched on when it was off.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../../modules/adrasec/adsb/adsb_controller.dart';
import '../../modules/adrasec/adsb/adsb_models.dart';
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

String _feet(int v){
  final s=v.abs().toString(), out=StringBuffer(v<0?'-':'');
  for(var i=0;i<s.length;i++){if(i>0&&(s.length-i)%3==0)out.write(' ');out.write(s[i]);}
  return '$out ft';
}

/// « 3 100 ft · Hélicoptère · 3C6444 » (the code when the title is the
/// callsign).
String aircraftSearchSubtitle(Aircraft a)=>[
  if(a.onGround)S.t('adsb.onGround') else if(a.altFt!=null)_feet(a.altFt!),
  S.t(a.rotorcraft?'adsb.kind.rotorcraft':'adsb.kind.plane'),
  if(a.callsign!=null)a.icao24.toUpperCase(),
].join(' · ');

/// The aircraft received now.
List<Searchable> aircraftSearchables(Iterable<Aircraft> list)=>[
  for(final a in list)Searchable(SearchKind.aircraft,a.name,'',a.position,prefix:a.icao24,ref:a.icao24,subtitle:aircraftSearchSubtitle(a))];

/// What the map does with a MeshCore node or an aircraft found; false for
/// the other results (the map moves to their point as before). [nodes]:
/// those of the module of this device by default.
bool openFoundOnMap(SearchResult r,{required MapController map,AdsbController? adsb,required void Function(MeshCoreContact) openNodeInTool,
    Iterable<MeshCoreContact>? nodes}){
  switch(r.kind){
    case SearchKind.meshNode:
      final c=(nodes??MeshCoreLink.instance.contacts).where((x)=>x.key==r.ref).firstOrNull;
      if(c==null)return true;
      if(r.placed&&meshCoreHasPosition(c)){unawaited(meshCoreShowOnMap(map,c));}else{openNodeInTool(c);}
      return true;
    case SearchKind.aircraft:
      if(adsb==null)return true;
      final a=adsb.received(DateTime.now()).where((x)=>x.icao24==r.ref).firstOrNull;
      if(a==null)return true;
      try{map.move(aircraftEstimated(a,adsb.serverNow),math.max(map.camera.zoom,11));}catch(_){/* map not ready */}
      unawaited(adsb.showFound(a));
      return true;
    default:
      return false;
  }
}
