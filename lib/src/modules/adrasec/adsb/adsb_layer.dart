/// « Aéronefs » layer (module ADRASEC, ADS-B step 1, 1 Nov 2026): an icon
/// turned to the heading, the label callsign · altitude · speed, a short
/// trace; red for the squawks 7700 / 7600 / 7500.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'adsb_models.dart';

const adsbColor=Color(0xFF1565C0), adsbUrgentColor=Color(0xFFD32F2F);

Color aircraftColor(Aircraft a)=>a.urgent?adsbUrgentColor:adsbColor;

/// Traces under the icons.
PolylineLayer aircraftTrails(List<Aircraft> all)=>PolylineLayer(polylines:[
  for(final a in all)if(a.trail.length>1)Polyline(points:a.trail,strokeWidth:2,color:aircraftColor(a).withValues(alpha:0.55)),
]);

/// Icons and labels; [onTap] opens the sheet of the aircraft.
MarkerLayer aircraftMarkers(List<Aircraft> all,{required void Function(Aircraft) onTap,bool labels=true})=>MarkerLayer(markers:[
  for(final a in all)Marker(point:a.position,width:labels?190:40,height:40,alignment:labels?const Alignment(0.79,0):Alignment.center,
    child:GestureDetector(key:ValueKey('adsb-${a.icao24}'),onTap:()=>onTap(a),child:Row(mainAxisSize:MainAxisSize.min,children:[
      SizedBox(width:40,height:40,child:Stack(alignment:Alignment.center,children:[
        if(a.urgent)Container(width:36,height:36,decoration:BoxDecoration(shape:BoxShape.circle,color:adsbUrgentColor.withValues(alpha:0.25))),
        Transform.rotate(angle:(a.trackDeg??0)*math.pi/180,
          child:Icon(Icons.flight,size:28,color:aircraftColor(a),shadows:const [Shadow(color:Colors.white,blurRadius:3)])),
        if(a.rotorcraft)Positioned(right:2,bottom:2,child:Container(padding:const EdgeInsets.symmetric(horizontal:3),
          decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(4)),
          child:Text('H',style:TextStyle(fontSize:10,fontWeight:FontWeight.w800,color:aircraftColor(a))))),
      ])),
      if(labels)Flexible(child:Container(padding:const EdgeInsets.symmetric(horizontal:5,vertical:1),
        decoration:BoxDecoration(color:Colors.white.withValues(alpha:0.88),borderRadius:BorderRadius.circular(4)),
        child:Text(aircraftLabel(a),maxLines:1,overflow:TextOverflow.ellipsis,
          style:TextStyle(fontSize:11,fontWeight:a.urgent?FontWeight.w800:FontWeight.w600,color:aircraftColor(a))))),
    ]))),
]);
