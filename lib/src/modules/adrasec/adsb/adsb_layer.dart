/// « Aéronefs » layer (module ADRASEC, ADS-B). Uncluttered view (card
/// validated 1 Nov 2026, 8 h 21): the icon alone, turned to the heading and
/// coloured by altitude; a label only for the selected aircraft, an
/// emergency squawk, or when « Afficher les indicatifs » is on; the whole
/// trace (where it comes from) for the selected aircraft only.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'adsb_models.dart';

const adsbColor=Color(0xFF1565C0), adsbUrgentColor=Color(0xFFD32F2F);

Color aircraftColor(Aircraft a)=>Color(aircraftColorValue(a));

/// Traces: short and thin for every aircraft, the whole [track] of the
/// selected one, thick.
PolylineLayer aircraftTrails(List<Aircraft> all,{String? selectedId,List<LatLng> track=const []})=>PolylineLayer(polylines:[
  for(final a in all)if(a.icao24!=selectedId&&a.trail.length>1)Polyline(points:a.trail,strokeWidth:1.5,color:aircraftColor(a).withValues(alpha:0.45)),
  if(selectedId!=null&&track.length>1)Polyline(points:track,strokeWidth:4,color:const Color(0xFF8E24AA).withValues(alpha:0.85)),
]);

/// Label of an aircraft on the map, or null (uncluttered view).
bool aircraftLabelled(Aircraft a,{required bool labels,String? selectedId})=>labels||a.urgent||a.icao24==selectedId;

/// Icons (and labels when [aircraftLabelled]); [onTap] selects.
MarkerLayer aircraftMarkers(List<Aircraft> all,{required void Function(Aircraft) onTap,bool labels=false,String? selectedId})=>MarkerLayer(markers:[
  for(final a in all)
    // 320 px wide: the label takes the width of its text, never cut.
    Marker(point:a.position,width:320,height:40,alignment:const Alignment(0.875,0),
      child:Align(alignment:Alignment.centerLeft,child:GestureDetector(key:ValueKey('adsb-${a.icao24}'),onTap:()=>onTap(a),
        child:Row(mainAxisSize:MainAxisSize.min,children:[
          SizedBox(width:40,height:40,child:Stack(alignment:Alignment.center,children:[
            if(a.urgent||a.icao24==selectedId)Container(width:36,height:36,decoration:BoxDecoration(shape:BoxShape.circle,
              color:(a.urgent?adsbUrgentColor:const Color(0xFF8E24AA)).withValues(alpha:0.25))),
            Transform.rotate(angle:(a.trackDeg??0)*math.pi/180,
              child:Icon(Icons.flight,size:a.icao24==selectedId?30:26,color:aircraftColor(a),shadows:const [Shadow(color:Colors.white,blurRadius:3)])),
            if(a.rotorcraft)Positioned(right:2,bottom:2,child:Container(padding:const EdgeInsets.symmetric(horizontal:3),
              decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(4)),
              child:Text('H',style:TextStyle(fontSize:10,fontWeight:FontWeight.w800,color:aircraftColor(a))))),
          ])),
          if(aircraftLabelled(a,labels:labels,selectedId:selectedId))Container(padding:const EdgeInsets.symmetric(horizontal:5,vertical:1),
            decoration:BoxDecoration(color:Colors.white.withValues(alpha:0.9),borderRadius:BorderRadius.circular(4)),
            child:Text(aircraftLabel(a),maxLines:1,softWrap:false,
              style:TextStyle(fontSize:11,fontWeight:a.urgent?FontWeight.w800:FontWeight.w600,color:aircraftColor(a)))),
        ])))),
]);
