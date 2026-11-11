/// Search of the map, lot 19 (card « Recherche : nœuds MeshCore et avions »,
/// validated on 1 Nov 2026, 21 h 42), module ADRASEC: the aircraft received
/// now, by callsign (ex. AFR92SC) and 24-bit ICAO code (its start too);
/// altitude and kind in words. The choice centres the map, opens the
/// floating sheet of the aircraft (« Suivre » there) and switches the layer
/// Aéronefs on when it was off.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';

import '../../../features/search/map_search.dart';
import '../../../l10n/strings.dart';
import 'adsb_controller.dart';
import 'adsb_models.dart';

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

/// The map on an aircraft found, its sheet open, the layer on; false for
/// the other results.
bool openAircraftFound(SearchResult r,{required MapController map,required AdsbController adsb}){
  if(r.kind!=SearchKind.aircraft)return false;
  final a=adsb.received(DateTime.now()).where((x)=>x.icao24==r.ref).firstOrNull;
  if(a==null)return true;
  try{map.move(aircraftEstimated(a,adsb.serverNow),math.max(map.camera.zoom,11));}catch(_){/* map not ready */}
  unawaited(adsb.showFound(a));
  return true;
}
