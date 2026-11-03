/// Sheets of the map (lot 25, card « PC : fiche d'un point d'intérêt
/// coupée, « Supprimer » invisible »): the sheet takes the height of its
/// content, up to 90 % of the window, and scrolls beyond (choice 1); on a
/// wide screen (computer, tablet in landscape) it opens as a side panel on
/// the right instead of the bottom (choice 2).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';

/// From this width the sheet is a side panel (same limit as the map page).
const mapSheetSideWidth=600.0;
/// Width of the side panel.
const mapSheetPanelWidth=380.0;
/// Highest share of the window a sheet takes.
const mapSheetMaxShare=0.9;

bool mapSheetIsSide(Size window)=>window.width>=mapSheetSideWidth;

/// Opens [builder] as a bottom sheet (phone) or a side panel on the right
/// (wide screen); the content scrolls when it is taller than the room.
/// The builder pops its own context with its result.
Future<T?> showMapSheet<T>(BuildContext context,{required WidgetBuilder builder}){
  final window=MediaQuery.sizeOf(context);
  if(!mapSheetIsSide(window)){
    return showModalBottomSheet<T>(context:context,showDragHandle:true,isScrollControlled:true,useSafeArea:true,
      constraints:BoxConstraints(maxHeight:window.height*mapSheetMaxShare),
      builder:(c)=>SafeArea(child:SingleChildScrollView(key:const ValueKey('map-sheet'),child:builder(c))));
  }
  return showGeneralDialog<T>(context:context,barrierDismissible:true,barrierLabel:S.t('common.close'),
    barrierColor:Colors.black12,transitionDuration:const Duration(milliseconds:150),
    transitionBuilder:(_,a,_,child)=>SlideTransition(position:Tween(begin:const Offset(0.15,0),end:Offset.zero).animate(a),
      child:FadeTransition(opacity:a,child:child)),
    pageBuilder:(c,_,_)=>SafeArea(child:LayoutBuilder(builder:(c,box)=>Align(alignment:Alignment.topRight,child:Padding(padding:const EdgeInsets.all(8),
      child:ConstrainedBox(constraints:BoxConstraints(maxWidth:math.min(mapSheetPanelWidth,box.maxWidth-16),maxHeight:math.max(0.0,box.maxHeight-16)),
        child:Material(key:const ValueKey('map-sheet-side'),elevation:8,borderRadius:BorderRadius.circular(16),clipBehavior:Clip.antiAlias,
          color:Theme.of(c).colorScheme.surface,
          child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            Align(alignment:Alignment.centerRight,child:IconButton(key:const ValueKey('map-sheet-close'),tooltip:S.t('common.close'),
              visualDensity:VisualDensity.compact,onPressed:()=>Navigator.pop(c),icon:const Icon(Icons.close))),
            Flexible(child:SingleChildScrollView(key:const ValueKey('map-sheet'),child:Builder(builder:builder))),
          ]))))))));
}
