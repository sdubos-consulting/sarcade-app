/// Icons of the aircraft by OpenSky category (card « ADS-B : icône selon le
/// type d'aéronef », validated 1 Nov 2026, 12 h 04): original SARCADE
/// drawings (no icon taken from a flight tracking site), 24 × 24, nose up,
/// turned to the track except the helicopter; the same shapes (same
/// coordinates) are drawn by the TV page of the server.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'adsb_models.dart';

class AircraftCircle {
  final double x, y, r;
  const AircraftCircle(this.x,this.y,this.r);
}

class AircraftShape {
  final List<List<Offset>> polygons;
  final List<AircraftCircle> circles;
  const AircraftShape({required this.polygons,required this.circles});
}

const aircraftShapes=<AircraftKind,AircraftShape>{
  AircraftKind.plane:AircraftShape(polygons:[[Offset(12,2),Offset(14,9),Offset(22,13),Offset(22,15),Offset(14,13),Offset(13,19),Offset(16,21),Offset(16,22),Offset(12,21),Offset(8,22),Offset(8,21),Offset(11,19),Offset(10,13),Offset(2,15),Offset(2,13),Offset(10,9)]],circles:[]),
  AircraftKind.light:AircraftShape(polygons:[[Offset(11,3),Offset(13,3),Offset(13,8),Offset(22,8),Offset(22,11),Offset(13,11),Offset(12.5,18),Offset(16,18.5),Offset(16,20.5),Offset(8,20.5),Offset(8,18.5),Offset(11.5,18),Offset(11,11),Offset(2,11),Offset(2,8),Offset(11,8)]],circles:[]),
  AircraftKind.airliner:AircraftShape(polygons:[[Offset(12,1),Offset(13.3,3),Offset(13.5,9),Offset(22,14),Offset(22,16),Offset(13.5,13.5),Offset(13,19),Offset(16,21),Offset(16,22.5),Offset(12,21.5),Offset(8,22.5),Offset(8,21),Offset(11,19),Offset(10.5,13.5),Offset(2,16),Offset(2,14),Offset(10.5,9),Offset(10.7,3)],[Offset(16.2,11.5),Offset(17.6,12.2),Offset(17.6,14.6),Offset(16.2,14.6)],[Offset(7.8,11.5),Offset(6.4,12.2),Offset(6.4,14.6),Offset(7.8,14.6)]],circles:[]),
  AircraftKind.glider:AircraftShape(polygons:[[Offset(11.4,4),Offset(12.6,4),Offset(12.6,9),Offset(23,9.6),Offset(23,10.8),Offset(12.6,11),Offset(12.3,19),Offset(15.5,19.3),Offset(15.5,20.5),Offset(8.5,20.5),Offset(8.5,19.3),Offset(11.7,19),Offset(11.4,11),Offset(1,10.8),Offset(1,9.6),Offset(11.4,9)]],circles:[]),
  AircraftKind.ulm:AircraftShape(polygons:[[Offset(12,3),Offset(22,15),Offset(12,12.5),Offset(2,15)]],circles:[AircraftCircle(12,16,2.5)]),
  AircraftKind.heli:AircraftShape(polygons:[[Offset(3.5,4.9),Offset(4.9,3.5),Offset(20.5,19.1),Offset(19.1,20.5)],[Offset(19.1,3.5),Offset(20.5,4.9),Offset(4.9,20.5),Offset(3.5,19.1)],[Offset(11.3,15),Offset(12.7,15),Offset(12.6,21),Offset(11.4,21)],[Offset(9.5,20.5),Offset(14.5,20.5),Offset(14.5,22),Offset(9.5,22)]],circles:[AircraftCircle(12,12,4.2)]),
  AircraftKind.balloon:AircraftShape(polygons:[[Offset(7,14),Offset(8.2,13.6),Offset(10.8,19),Offset(10.2,19)],[Offset(17,14),Offset(15.8,13.6),Offset(13.2,19),Offset(13.8,19)],[Offset(10,19),Offset(14,19),Offset(14,22.5),Offset(10,22.5)]],circles:[AircraftCircle(12,9,7)]),
  AircraftKind.drone:AircraftShape(polygons:[[Offset(5.3,6.7),Offset(6.7,5.3),Offset(18.7,17.3),Offset(17.3,18.7)],[Offset(17.3,5.3),Offset(18.7,6.7),Offset(6.7,18.7),Offset(5.3,17.3)],[Offset(9.5,9.5),Offset(14.5,9.5),Offset(14.5,14.5),Offset(9.5,14.5)],[Offset(12,4.5),Offset(14,8.5),Offset(10,8.5)]],circles:[AircraftCircle(6,6,3),AircraftCircle(18,6,3),AircraftCircle(6,18,3),AircraftCircle(18,18,3)]),
  AircraftKind.parachute:AircraftShape(polygons:[[Offset(3,10),Offset(4,6.5),Offset(7,4),Offset(12,3),Offset(17,4),Offset(20,6.5),Offset(21,10),Offset(17,8.8),Offset(12,8.3),Offset(7,8.8)],[Offset(3.2,10),Offset(4.2,10),Offset(11.6,17),Offset(11,17.6)],[Offset(20.8,10),Offset(19.8,10),Offset(12.4,17),Offset(13,17.6)],[Offset(11,19.5),Offset(13,19.5),Offset(13,23),Offset(11,23)]],circles:[AircraftCircle(12,17.8,1.9)]),
};

/// Airliners are drawn larger.
double aircraftIconSize(AircraftKind k,{bool selected=false})=>(k==AircraftKind.airliner?34:28)+(selected?4:0);
bool aircraftTurned(AircraftKind k)=>k!=AircraftKind.heli;

/// One aircraft: its shape filled with [color], white outline; a round of
/// [ring] behind it (emergency, aircraft followed or chosen).
class AircraftIconPainter extends CustomPainter {
  final AircraftKind kind; final Color color; final double turnDeg; final Color? ring;
  const AircraftIconPainter({required this.kind,required this.color,this.turnDeg=0,this.ring});

  @override void paint(Canvas canvas,Size size){
    final k=math.min(size.width,size.height)/24;
    canvas.save();
    canvas.translate(size.width/2,size.height/2);
    canvas.rotate(turnDeg*math.pi/180);
    canvas.scale(k);
    canvas.translate(-12,-12);
    final r=ring;
    if(r!=null){
      canvas.drawCircle(const Offset(12,12),11.4,Paint()..color=r.withValues(alpha:0.25));
      canvas.drawCircle(const Offset(12,12),11.4,Paint()..color=r..style=PaintingStyle.stroke..strokeWidth=1.2);
    }
    final fill=Paint()..color=color;
    final line=Paint()..color=Colors.white..style=PaintingStyle.stroke..strokeWidth=0.8..strokeJoin=StrokeJoin.round;
    final shape=aircraftShapes[kind]!;
    for(final poly in shape.polygons){
      final path=Path()..addPolygon(poly,true);
      canvas.drawPath(path,fill);
      canvas.drawPath(path,line);
    }
    for(final c in shape.circles){
      canvas.drawCircle(Offset(c.x,c.y),c.r,fill);
      canvas.drawCircle(Offset(c.x,c.y),c.r,line);
    }
    canvas.restore();
  }

  @override bool shouldRepaint(AircraftIconPainter old)=>old.kind!=kind||old.color!=color||old.turnDeg!=turnDeg||old.ring!=ring;
}

/// Icon widget of an aircraft kind (map, list, sheet, legend).
class AircraftIcon extends StatelessWidget {
  final AircraftKind kind; final Color color; final double size, turnDeg; final Color? ring;
  const AircraftIcon({super.key,required this.kind,required this.color,this.size=24,this.turnDeg=0,this.ring});
  @override Widget build(BuildContext context)=>SizedBox(width:size,height:size,
    child:CustomPaint(painter:AircraftIconPainter(kind:kind,color:color,turnDeg:aircraftTurned(kind)?turnDeg:0,ring:ring)));
}
