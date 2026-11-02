/// Bottom of the map on a phone (card « Téléphone : boutons du bas de la
/// carte cachés par la barre de navigation », lot 19, decided on 1 Nov 2026,
/// 21 h 39 to 21 h 41):
/// - the ⓘ of the base map and the flutter_map button sit above the tab
///   bar (height of the bar + safe area of the device), never under it;
/// - the scale is on the line of « Suivi de position », just on its right;
/// - the bottom of the SOS disc is level with the bottom of « Suivi de
///   position ».
/// Computer and tablet keep their places.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../ui/test_ids.dart';
import 'link_weather_pill.dart' show pillHeight;

/// Phone tab bar (`_TabBar` of operational_map_page.dart): 72 high with
/// margins of 4 above and 8 below. The safe area of the device is added
/// under it by its own SafeArea.
const double phoneTabBarExtent=72+4+8;

/// Gap between the top of the tab bar and the bottom line of the map
/// (« Suivi de position », scale, SOS).
const double phoneBottomGap=12;

/// SOS: the red disc (46) is drawn in a 56 box, 5 under it.
const double sosDiscInset=(56-46)/2;

/// Room kept on the right of the bottom line for the column (SOS, 56 wide).
const double phoneColumnReserve=12+56+8;

/// Bottom of the right column (« Fond et affichage », position, Écrans,
/// SOS): on a phone the SOS disc ends on the line of « Suivi de position ».
double mapColumnBottom({required bool compact})=>compact?phoneBottomGap-sosDiscInset:24;

/// Scale alone (computer, or phone while a card hides « Suivi de
/// position »): on a phone, middle of the bottom line.
double mapScaleBottom({required bool compact})=>compact?phoneBottomGap+7:44;

/// Bottom margin of the ⓘ, inside the map. On a phone in full screen the
/// map goes under the tab bar (it stops only at the safe area of the
/// device), hence the height of the bar; the ⓘ then sits just above
/// « Suivi de position ».
double mapAttributionBottom({required bool compact,required bool fullBleed})=>
  compact?(fullBleed?phoneTabBarExtent:0)+phoneBottomGap+pillHeight+4:0;

/// ⓘ (licence of the base map) at the bottom left, inside the map.
Widget mapAttribution({required bool compact,required bool fullBleed,required String text})=>
  SafeArea(child:Padding(padding:EdgeInsets.only(bottom:mapAttributionBottom(compact:compact,fullBleed:fullBleed)),
    child:RichAttributionWidget(alignment:AttributionAlignment.bottomLeft,
      // Same button as flutter_map's, with a test identifier.
      openButton:(context,open)=>withId('map.attribution',IconButton(onPressed:open,tooltip:'Attributions',
        icon:const Icon(Icons.info_outlined,color:Colors.black,size:24))),
      attributions:[TextSourceAttribution(text)])));

/// Phone: « Suivi de position » then the scale on its right, on one line
/// just above the tab bar, clear of the right column.
Widget phoneBottomLine({required Widget badge,required Widget scale})=>
  Positioned(left:12,right:phoneColumnReserve,bottom:phoneBottomGap,height:pillHeight,
    child:Row(children:[
      Flexible(child:withId('map.tracking',badge)),
      const SizedBox(width:8),
      withId('map.scale',scale),
    ]));
