/// Lighter markers of the persons on the map (card « Carte : marqueur d'une
/// personne plus léger », validated on 9 Nov 2026).
library;

import 'package:flutter/painting.dart';

/// Names under the rounds from this zoom; further, the rounds alone.
const markerNamesZoom=15.0;
/// Beyond this age, a small grey point instead of the round.
const markerForgottenAfter=Duration(hours:24);

bool markerNamesShown(double? zoom)=>zoom==null||zoom>=markerNamesZoom;

bool markerForgotten(DateTime time,DateTime now)=>now.difference(time)>markerForgottenAfter;

/// White edge around the small text of a marker, readable on any map
/// (as on Google Maps), instead of a framed label.
const markerTextHalo=[
  Shadow(color:Color(0xFFFFFFFF),blurRadius:2),
  Shadow(color:Color(0xFFFFFFFF),offset:Offset(1,0)),
  Shadow(color:Color(0xFFFFFFFF),offset:Offset(-1,0)),
  Shadow(color:Color(0xFFFFFFFF),offset:Offset(0,1)),
  Shadow(color:Color(0xFFFFFFFF),offset:Offset(0,-1)),
];
