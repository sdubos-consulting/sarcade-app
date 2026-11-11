/// APRS gateways drawn as a diamond (card « APRS : vrais symboles des
/// stations sur la carte », decision of 1 Nov 2026, 22 h 13): the stations
/// keep the SARCADE icons, except the gateways (symbol code `&`, any table
/// or overlay): **red** diamond for LoRa (`L&`), **black** for the others
/// (`I&` Internet, `R&`, `/&`, `\&`…), overlay letter in **white** in the
/// middle. Drawn here, no image taken from elsewhere. Same drawing on the
/// map, in Équipes and on the sheet of the station; an icon chosen in
/// SARCADE wins.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Diamond of a LoRa gateway (`L&`).
const gatewayLoraRed=Color(0xFFD32F2F);

/// Diamond of the other gateways.
const gatewayBlack=Color(0xFF1B1B1B);

/// Smallest gateway drawn on the map: readable and easy to touch (fixed
/// stations are drawn at 20 px otherwise).
const double gatewayMinSize=30;

/// Colour and overlay letter of a gateway, or null when [symbol] (table
/// then code, « L& ») is not a gateway.
({Color color,String? letter})? aprsGateway(String? symbol){
  if(symbol==null||symbol.length<2||symbol[1]!='&')return null;
  final table=symbol[0];
  final letter=table=='/'||table=='\\'?null:table;
  return (color:table=='L'?gatewayLoraRed:gatewayBlack,letter:letter);
}

/// Size of the icon of a station: gateways never under [gatewayMinSize].
double stationIconSize(String? symbol,double size)=>aprsGateway(symbol)==null?size:math.max(size,gatewayMinSize);

/// Diamond of an APRS station that is a gateway, or null: the SARCADE icon
/// is drawn instead (not APRS, not a gateway, or an icon chosen by the
/// operator in SARCADE, which wins).
Widget? gatewayStationIcon({required String? symbol,required bool isAprs,required bool hasChosenIcon,required double size}){
  if(!isAprs||hasChosenIcon)return null;
  final g=aprsGateway(symbol);
  return g==null?null:AprsGatewayDiamond(color:g.color,letter:g.letter,size:size);
}

class AprsGatewayDiamond extends StatelessWidget {
  final Color color; final String? letter; final double size;
  const AprsGatewayDiamond({super.key,required this.color,required this.letter,required this.size});
  @override Widget build(BuildContext context){
    final l=letter;
    return SizedBox(width:size,height:size,child:CustomPaint(painter:AprsDiamondPainter(color),
      child:l==null?null:Center(child:Text(l,textScaler:TextScaler.noScaling,
        style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900,fontSize:size*0.42,height:1)))));
  }
}

/// Diamond filling its box, with a thin white edge so that a black one
/// stays visible on a dark base map.
class AprsDiamondPainter extends CustomPainter {
  final Color color;
  const AprsDiamondPainter(this.color);
  @override void paint(Canvas canvas,Size size){
    const edge=1.5;
    final w=size.width, h=size.height;
    final path=Path()..moveTo(w/2,edge)..lineTo(w-edge,h/2)..lineTo(w/2,h-edge)..lineTo(edge,h/2)..close();
    canvas.drawPath(path,Paint()..color=color..isAntiAlias=true);
    canvas.drawPath(path,Paint()..color=Colors.white..style=PaintingStyle.stroke..strokeWidth=edge..strokeJoin=StrokeJoin.round);
  }
  @override bool shouldRepaint(AprsDiamondPainter oldDelegate)=>oldDelegate.color!=color;
}
