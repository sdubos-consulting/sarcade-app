/// Opacity of a map layer (« Fond et affichage », one slider per layer),
/// card « Opacité des couches : l'appliquer aussi aux étiquettes » (lot 19,
/// decided on 1 Nov 2026, 21 h 54). The whole layer is drawn through one
/// [Opacity]: symbols, dots and their labels (callsign, name, text of a
/// drawing, label of a zone) fade together, and a label is never more
/// opaque than its drawing.
///
/// Checked layer by layer in the application (lot 19): operators (`ops`),
/// APRS stations, mobile and fixed (`aprs`), points of interest (`poi`),
/// drawings (`draw`), bearings and zones (`brg`), high points (`high`),
/// relays (`relay`), traces (`traces`): their labels are inside the faded
/// layer. Aircraft, MeshCore nodes, routes and move orders have no opacity
/// slider: drawn at 100 %, labels included.
library;

import 'package:flutter/widgets.dart';

/// [layer] at [opacity] (10 to 100 %), labels included.
Widget fadedLayer(double opacity,Widget layer)=>opacity>=1?layer:Opacity(opacity:opacity,child:layer);

/// Every widget of a layer made of several (drawings, bearings) at [opacity].
List<Widget> fadedLayers(double opacity,List<Widget> layers)=>[for(final l in layers)fadedLayer(opacity,l)];
