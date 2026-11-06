/// « Tous les opérateurs » (card « affiche le monde entier », lot 29.2):
/// frames only the operators near me, never the whole world.
/// 1. within [radiusKm] (50 by default) of my position, else of the centre
///    of the map;
/// 2. positions older than 24 h and invalid ones (0, 0) are left out;
/// 3. the others are counted (« 3 opérateurs hors zone », a touch shows all).
library;

import 'package:latlong2/latlong.dart';

import '../../models/position.dart';

/// Radii offered (km).
const frameRadii=[10,25,50,100];
const defaultFrameRadiusKm=50;
int frameRadiusFrom(String? v){final r=int.tryParse(v??'');return frameRadii.contains(r)?r!:defaultFrameRadiusKm;}

/// A position worth framing: fresh (24 h) and not (0, 0).
bool frameable(SarcadePosition p,DateTime now)=>
  !(p.lat.abs()<1e-6&&p.lon.abs()<1e-6)&&p.lat.abs()<=90&&p.lon.abs()<=180&&now.difference(p.time).inHours<24;

/// Points to frame around [centre] and how many are left outside.
({List<LatLng> inside,List<LatLng> all,int outside}) operatorsFrame(Iterable<SarcadePosition> positions,LatLng centre,DateTime now,{int radiusKm=defaultFrameRadiusKm}){
  const d=Distance();
  final all=<LatLng>[],inside=<LatLng>[];
  for(final p in positions){
    if(!frameable(p,now))continue;
    final at=LatLng(p.lat,p.lon); all.add(at);
    if(d.as(LengthUnit.Kilometer,centre,at)<=radiusKm)inside.add(at);
  }
  return (inside:inside,all:all,outside:all.length-inside.length);
}

/// Corners of a square of [radiusKm] around [centre] (nobody in the radius).
List<LatLng> radiusBox(LatLng centre,int radiusKm){
  const d=Distance(); final m=radiusKm*1000.0;
  return [d.offset(centre,m,0),d.offset(centre,m,90),d.offset(centre,m,180),d.offset(centre,m,270)];
}
