/// Card L1 of the cinématique review of lot 16 (decided by the project
/// owner, 1 Nov 2026, 12 h 15, choice 1): while a shape is drawn, a measure
/// is made or a bearing is taken, the markers of the map (operators, points,
/// stations…) ignore touches, and the point is placed where the map was
/// touched. Out of these modes, nothing changes.
library;

import 'package:flutter/widgets.dart';

/// True while a touch on the map is work in progress: [drawing] a shape
/// (drawing tool, route, closure), [picking] a point (« Toucher la carte »),
/// [measuring] (measure shown or its origin being picked), [bearing] (bearing
/// taken, aimed with the mouse or adjusted).
bool markersIgnoreTouches({bool drawing=false,bool picking=false,bool measuring=false,bool bearing=false})=>
  drawing||picking||measuring||bearing;

/// A marker layer of the map that lets touches through to the map while
/// [ignoring] (see [markersIgnoreTouches]).
Widget touchableMarkers({required bool ignoring,required Widget child})=>IgnorePointer(ignoring:ignoring,child:child);
