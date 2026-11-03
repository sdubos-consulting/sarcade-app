/// Right column of the map (« Fond et affichage », north, position, Écrans,
/// SOS), card « Carte : aligner verticalement les boutons de la colonne de
/// droite » (lot 25, choices of 3 Nov 2026, 10 h 51):
/// 1. every button has its centre on the same vertical axis;
/// 2. the column keeps the right margin of its widest button (SOS, 56);
/// 3. SOS keeps its size and its round red shape;
/// 4. the same visible gap between all the buttons;
/// 5. the same on phone, tablet, web and Windows, north and Écrans included.
library;

import 'package:flutter/widgets.dart';

import 'map_bottom_line.dart' show sosDiscInset;

/// Width of the column: the box of SOS, the widest button.
const double mapColumnWidth=56;

/// Visible gap between two buttons of the column (edge to edge).
const double mapColumnGap=10;

/// Space above SOS: its red disc (46) is drawn 5 inside its 56 box, so the
/// visible gap above the disc is [mapColumnGap] like the others.
const double mapColumnSosGap=mapColumnGap-sosDiscInset;

/// One button of the column, centred in the width of SOS.
Widget mapColumnSlot(Widget child)=>SizedBox(width:mapColumnWidth,child:Center(child:child));
