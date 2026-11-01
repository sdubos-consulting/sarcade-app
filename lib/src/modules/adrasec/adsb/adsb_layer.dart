/// « Aéronefs » layer (module ADRASEC, ADS-B). Uncluttered view (card
/// validated 1 Nov 2026, 8 h 21): the icon alone, coloured by altitude band;
/// a label only for the selected aircraft, an emergency squawk, or when
/// « Afficher les indicatifs » is on.
///
/// Lot 17 (1 Nov 2026): no trace by default, the route (30 min) of each
/// aircraft followed only, in violet; icon by OpenSky category, its centre
/// on the position; position estimated every second (60 s at most, then
/// grey « position ancienne »); aircraft followed circled in violet.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'adsb_icons.dart';
import 'adsb_models.dart';

const adsbColor=Color(adsbMidValue), adsbUrgentColor=Color(adsbUrgentValue), adsbFollowColor=Color(adsbFollowValue);

Color aircraftColor(Aircraft a,[AdsbFilters f=const AdsbFilters()])=>Color(aircraftColorValue(a,f));

/// Routes of the aircraft followed only (no trace for the others).
PolylineLayer aircraftRoutes(Map<String,List<LatLng>> routes)=>PolylineLayer(polylines:[
  for(final r in routes.values)if(r.length>1)Polyline(points:r,strokeWidth:4,color:adsbFollowColor.withValues(alpha:0.85)),
]);

/// Label of an aircraft on the map, or null (uncluttered view).
bool aircraftLabelled(Aircraft a,{required bool labels,String? selectedId})=>labels||a.urgent||a.icao24==selectedId;

/// Icons (and labels when [aircraftLabelled]) at their estimated positions,
/// moved every second; [onTap] opens the floating sheet.
class AircraftMarkers extends StatefulWidget {
  final List<Aircraft> aircraft; final void Function(Aircraft) onTap;
  final AdsbFilters filters; final String? selectedId; final Set<String> followed;
  /// Clock of the server (same reference as the TV).
  final DateTime Function() now;
  const AircraftMarkers({super.key,required this.aircraft,required this.onTap,required this.now,
    this.filters=const AdsbFilters(),this.selectedId,this.followed=const {}});
  @override State<AircraftMarkers> createState()=>_AircraftMarkersState();
}

class _AircraftMarkersState extends State<AircraftMarkers> {
  Timer? _tick;
  @override void initState(){super.initState();_tick=Timer.periodic(const Duration(seconds:1),(_){if(mounted)setState((){});});}
  @override void dispose(){_tick?.cancel();super.dispose();}

  @override Widget build(BuildContext context){
    final now=widget.now(), w=widget;
    return MarkerLayer(markers:[
      for(final a in w.aircraft)aircraftMarker(a,now:now,filters:w.filters,onTap:w.onTap,
        selected:a.icao24==w.selectedId,followed:w.followed.contains(a.icao24)),
    ]);
  }
}

/// One marker: 320 px wide so that the label takes the width of its text;
/// the centre of the icon (left 40 px box) is the position.
Marker aircraftMarker(Aircraft a,{required DateTime now,required void Function(Aircraft) onTap,AdsbFilters filters=const AdsbFilters(),
    bool selected=false,bool followed=false}){
  final stale=aircraftStale(a,now), kind=aircraftKind(a), col=aircraftColor(a,filters);
  final ring=a.urgent?adsbUrgentColor:(followed||selected?adsbFollowColor:null);
  return Marker(point:aircraftEstimated(a,now),width:320,height:40,alignment:const Alignment(0.875,0),
    child:Align(alignment:Alignment.centerLeft,child:GestureDetector(key:ValueKey('adsb-${a.icao24}'),onTap:()=>onTap(a),
      child:Row(mainAxisSize:MainAxisSize.min,children:[
        SizedBox(width:40,height:40,child:Center(child:Opacity(opacity:stale?0.5:1,
          child:AircraftIcon(kind:kind,color:stale?const Color(adsbGroundValue):col,size:aircraftIconSize(kind,selected:selected),
            turnDeg:(a.trackDeg??0).toDouble(),ring:ring)))),
        if(aircraftLabelled(a,labels:filters.labels,selectedId:selected?a.icao24:null))Container(padding:const EdgeInsets.symmetric(horizontal:5,vertical:1),
          decoration:BoxDecoration(color:Colors.white.withValues(alpha:0.9),borderRadius:BorderRadius.circular(4)),
          child:Text(aircraftLabel(a),maxLines:1,softWrap:false,
            style:TextStyle(fontSize:11,fontWeight:a.urgent?FontWeight.w800:FontWeight.w600,color:col))),
      ]))));
}
