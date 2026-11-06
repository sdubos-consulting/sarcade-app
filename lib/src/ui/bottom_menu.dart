/// Menus that rise from the bottom of the screen (card « menu d'un message
/// trop haut », lot 29.3): the safe area of the system plus 16 px under the
/// last row, so that it never falls in the gesture bar of the iPhone.
library;

import 'package:flutter/widgets.dart';

const bottomMenuExtra=16.0;

/// Margin under the last row of a menu from the bottom.
double bottomMenuMargin(BuildContext context)=>MediaQuery.viewPaddingOf(context).bottom+bottomMenuExtra;
