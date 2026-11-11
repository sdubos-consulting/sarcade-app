/// SOS on the map (card « SOS : voir sur la carte où est l'opérateur en
/// détresse », choices validated by the porteur on 1 Nov 2026, 12 h 04;
/// lot 17): a red pulsing halo and a « SOS · nom » label on each operator in
/// distress, above every other object and whatever the filters and layers;
/// last known position with its age, dashed halo when older than 10 min,
/// « position inconnue » without any; the halo stays until « Fin de
/// détresse ».
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../../models/message.dart';
import '../../models/position.dart';
import 'sos_alert.dart';
import 'stations.dart' show ageLabel;

/// A position older than this: dashed halo, « position ancienne ».
const sosStaleAfter=Duration(minutes:10);

/// « Zoom de quartier » of a touch on the SOS banner.
const double sosZoom=16;

const sosRed=Color(0xFFD50000);

/// One operator in distress: his SOS message and his last known position.
class SosTarget {
  final String deviceId, label;
  final SarcadeMessage message;
  final LatLng? point;
  final DateTime? time;
  const SosTarget({required this.deviceId,required this.label,required this.message,this.point,this.time});
  bool get known=>point!=null;
  bool stale(DateTime now)=>time!=null&&now.difference(time!)>sosStaleAfter;
}

final _bodyPosition=RegExp(r'position\s+(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)');

/// Position written by the application in the SOS message
/// (« 🆘 DÉTRESSE — TEL-01 — position 48.80000, 2.10000 »).
LatLng? sosBodyPosition(String body){
  final m=_bodyPosition.firstMatch(body);
  if(m==null)return null;
  final lat=double.parse(m.group(1)!), lon=double.parse(m.group(2)!);
  if(lat.abs()>90||lon.abs()>180)return null;
  return LatLng(lat,lon);
}

/// Operators in distress, oldest SOS first. [positions] holds every last
/// position (not only those the filters show). The position is the last
/// report of the operator, or the one written in his SOS message when it
/// is more recent.
List<SosTarget> sosTargets(Map<String,SarcadeMessage> open,Map<String,SarcadePosition> positions){
  final list=open.values.toList()..sort((a,b)=>a.createdAt.compareTo(b.createdAt));
  return [for(final m in list)_target(m,positions[m.senderId])];
}

SosTarget _target(SarcadeMessage m,SarcadePosition? p){
  LatLng? point=p==null?null:LatLng(p.lat,p.lon);
  DateTime? time=p?.time.toUtc();
  final written=sosBodyPosition(m.body);
  if(written!=null&&(time==null||m.createdAt.toUtc().isAfter(time))){point=written;time=m.createdAt.toUtc();}
  return SosTarget(deviceId:m.senderId,label:p?.label??m.senderId,message:m,point:point,time:time);
}

/// Operators in distress seen by this device (its own distress apart).
List<SosTarget> sosTargetsFor(Iterable<SarcadeMessage> messages,String deviceId,Map<String,SarcadePosition> positions)=>
  sosTargets(openDistress(messages,deviceId),positions);

/// The target of [deviceId], if he is in distress.
SosTarget? sosTargetOf(List<SosTarget> targets,String deviceId){
  for(final t in targets){if(t.deviceId==deviceId)return t;}
  return null;
}

/// « il y a 2 min », « position ancienne · il y a 25 min », « position inconnue ».
String sosAge(SosTarget t,DateTime now){
  if(!t.known)return S.t('sos.unknown');
  final age=ageLabel(t.time!,now);
  return t.stale(now)?S.t('sos.stale',{'age':age}):S.t('sos.ago',{'age':age});
}

/// Halo and label of every operator in distress with a position: last
/// layer of the map, touches go through to the operator below.
Widget sosHaloLayer(List<SosTarget> targets,DateTime now)=>IgnorePointer(child:MarkerLayer(markers:[
  for(final t in targets)
    if(t.known)Marker(point:t.point!,width:240,height:180,alignment:Alignment.center,
      child:SosHalo(key:ValueKey('sos-halo-${t.deviceId}'),label:S.t('sos.label',{'who':t.label}),age:sosAge(t,now),stale:t.stale(now))),
]));

class SosHalo extends StatefulWidget {
  final String label, age;
  final bool stale;
  const SosHalo({super.key,required this.label,required this.age,required this.stale});
  @override State<SosHalo> createState()=>_SosHaloState();
}

class _SosHaloState extends State<SosHalo> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse=AnimationController(vsync:this,duration:const Duration(milliseconds:1400));

  @override
  void didChangeDependencies(){
    super.didChangeDependencies();
    // Reduced motion asked by the system: a still halo.
    if(MediaQuery.maybeDisableAnimationsOf(context)??false){_pulse.stop();_pulse.value=0.5;}
    else if(!_pulse.isAnimating){_pulse.repeat();}
  }

  @override void dispose(){_pulse.dispose();super.dispose();}

  @override
  Widget build(BuildContext context){
    return Stack(alignment:Alignment.center,clipBehavior:Clip.none,children:[
      AnimatedBuilder(animation:_pulse,builder:(context,_)=>CustomPaint(size:const Size(100,100),
        painter:SosHaloPainter(progress:_pulse.value,dashed:widget.stale))),
      Container(width:16,height:16,decoration:BoxDecoration(color:sosRed,shape:BoxShape.circle,border:Border.all(color:Colors.white,width:2))),
      Positioned(top:0,child:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),
        decoration:BoxDecoration(color:sosRed,borderRadius:BorderRadius.circular(6),boxShadow:const [BoxShadow(blurRadius:6,color:Color(0x66000000))]),
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          Text(widget.label,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800,fontSize:14)),
          Text(widget.age,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w600,fontSize:11)),
        ]))),
    ]);
  }
}

/// Red ring growing and fading; dashed when the position is old.
class SosHaloPainter extends CustomPainter {
  final double progress;
  final bool dashed;
  const SosHaloPainter({required this.progress,required this.dashed});

  @override
  void paint(Canvas canvas,Size size){
    final c=size.center(Offset.zero);
    final max=size.shortestSide/2-3;
    final r=max*(0.55+0.45*progress);
    final alpha=1.0-0.7*progress;
    canvas.drawCircle(c,r,Paint()..color=sosRed.withValues(alpha:(dashed?0.08:0.18)*alpha));
    final stroke=Paint()..color=sosRed.withValues(alpha:alpha)..style=PaintingStyle.stroke..strokeWidth=4;
    if(!dashed){canvas.drawCircle(c,r,stroke);return;}
    const dashes=16;
    const sweep=math.pi*2/dashes;
    final rect=Rect.fromCircle(center:c,radius:r);
    for(var i=0;i<dashes;i++){canvas.drawArc(rect,i*sweep,sweep*0.55,false,stroke);}
  }

  @override
  bool shouldRepaint(SosHaloPainter old)=>old.progress!=progress||old.dashed!=dashed;
}

/// « Y aller » in the sheet of an operator in distress.
class SosGoButton extends StatelessWidget {
  final VoidCallback onPressed;
  const SosGoButton({super.key,required this.onPressed});
  @override
  Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(top:8),
    child:FilledButton.icon(key:const Key('sos-go'),onPressed:onPressed,
      style:FilledButton.styleFrom(backgroundColor:sosRed,foregroundColor:Colors.white),
      icon:const Icon(Icons.directions),label:Text(S.t('sos.go'))));
}
