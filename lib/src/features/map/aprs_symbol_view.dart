/// APRS symbol with an overlay (card « APRS : symbole avec surcharge
/// dessiné comme une simple lettre dans un carré », lot 25, decided on
/// 3 Nov 2026, 13 h 19):
/// 1. the icon of the symbol (car, person, house…) is drawn, with the
///    overlay letter in a small badge in a corner, on the map, in Équipes
///    and on the sheet;
/// 2. gateways keep their red (LoRa) or black diamond (aprs_gateway.dart);
/// 3. the sheet says the symbol received in plain words (« Symbole APRS :
///    voiture, surcharge L »);
/// 4. unknown symbol: antenna icon with the badge.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import 'stations.dart';

/// Side of the overlay badge for an icon of [size].
double aprsOverlayBadgeSize(double size)=>(size*0.42).clamp(11.0,18.0).toDouble();

/// Small badge with the overlay letter, in the colour of the station.
Widget aprsOverlayBadge(String letter,{required double size,required Color color,required Color background}){
  final b=aprsOverlayBadgeSize(size);
  return Container(key:const ValueKey('aprs-overlay-badge'),width:b,height:b,alignment:Alignment.center,
    decoration:BoxDecoration(color:color,borderRadius:BorderRadius.circular(b*0.3),border:Border.all(color:background,width:1)),
    child:Text(letter,style:TextStyle(fontSize:b*0.68,height:1,fontWeight:FontWeight.w800,color:background)));
}

/// Badge placed on the top right corner of an icon of [size] (the status
/// dot takes the bottom right, the heading arrow the top).
Widget aprsOverlayCorner(String letter,{required double size,required Color color,required Color background})=>
  Positioned(top:-3,right:-3,child:aprsOverlayBadge(letter,size:size,color:color,background:background));

/// Name of the kind of symbol (« voiture ») given by [aprsSymbol]; an
/// unknown symbol is shown as received (« inconnu (\\x) »).
String aprsSymbolName(String kind,String symbol)=>kind=='station'
  ?S.t('aprs.symbol.unknown',{'code':symbol}):S.t('aprs.symbol.kind.$kind');

/// Line of the sheet: « Symbole APRS : voiture, surcharge L », or null when
/// the station sent no symbol.
String? aprsSymbolLine(String? symbol){
  if(symbol==null||symbol.length<2)return null;
  final sym=aprsSymbol(symbol);
  final name=aprsSymbolName(sym.kind,symbol.substring(0,2));
  return sym.overlay==null?S.t('aprs.symbol.line',{'name':name}):S.t('aprs.symbol.lineOverlay',{'name':name,'overlay':sym.overlay});
}
