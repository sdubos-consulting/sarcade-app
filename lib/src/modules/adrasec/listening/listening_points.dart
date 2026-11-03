/// Listening points SATER (card « Android Auto : « Signal entendu ici »
/// (SATER) », lot 24, 3 Nov 2026, choice 3): « signal de balise entendu »
/// sent from the car with the position, the heading of the vehicle and the
/// time, shown on the map of the PCO as a bearing without azimuth, in the
/// « Relevés » layer, as on the TV: orange ring (dashed in exercise), short
/// line in the heading of the vehicle, « Écoute HH:MM ». A touch opens its
/// sheet (author, time, heading); the PCO deletes it at any time.
///
/// Server object: `map_feature` of kind `listening`, one point, block
/// `listening` {heard_at, heading_deg?, speed_mps?, accuracy_m?, exercise?,
/// search?, frequency_mhz?, comment?}.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../features/map/drawing/geometry.dart' show destination;
import '../../../l10n/strings.dart';
import '../../../offline/local_store.dart';
import '../../../offline/sync_service.dart';

/// Orange of the listening points (server default 0xFFFF9F1C, TV #FF9F1C).
const listeningColor=Color(0xFFFF9F1C);
/// Length of the heading line, metres (as the TV).
const listeningHeadingM=120.0;

bool isListening(Map<String,dynamic> j)=>j['kind']=='listening';

class ListeningPoint {
  final Map<String,dynamic> json;
  const ListeningPoint(this.json);
  String get id=>'${json['id']}';
  Map<String,dynamic> get _l=>json['listening'] is Map?Map<String,dynamic>.from(json['listening'] as Map):const {};
  LatLng get point{
    final p=(json['points'] as List).first as List;
    return LatLng((p[0] as num).toDouble(),(p[1] as num).toDouble());
  }
  DateTime? get updatedAt=>DateTime.tryParse('${json['updated_at']??''}');
  DateTime? get heardAt=>DateTime.tryParse('${_l['heard_at']??''}')??updatedAt;
  double? get headingDeg=>(_l['heading_deg'] as num?)?.toDouble();
  double? get frequencyMhz=>(_l['frequency_mhz'] as num?)?.toDouble();
  bool get exercise=>_l['exercise']==true;
  String get search=>'${_l['search']??''}';
  String get comment=>'${_l['comment']??''}';
  String get createdBy=>'${json['created_by']??json['updated_by']??''}';

  /// A usable point: one position.
  static ListeningPoint? tryParse(Map<String,dynamic> j){
    if(!isListening(j)||j['deleted']==true)return null;
    final pts=j['points'];
    if(pts is! List||pts.isEmpty)return null;
    final p=pts.first;
    return p is List&&p.length>=2&&p[0] is num&&p[1] is num?ListeningPoint(j):null;
  }
}

/// « 08:00 » as on the TV (local time).
String listeningClock(DateTime t){final l=t.toLocal();String two(int v)=>v.toString().padLeft(2,'0');return '${two(l.hour)}:${two(l.minute)}';}

/// « Écoute 08:00 », « EX · Écoute 08:00 » in exercise.
String listeningLabel(ListeningPoint l){
  final t=l.heardAt;
  final text=t==null?S.t('listening.short'):S.t('listening.label',{'time':listeningClock(t)});
  return l.exercise?'${S.t('listening.ex')} · $text':text;
}

/// Listening points of the event, the most recent version of each winning.
class ListeningPoints extends ChangeNotifier {
  final Map<String,ListeningPoint> _byId={};
  ListeningPoints({Iterable<Map<String,dynamic>> initial=const []}){
    for(final j in initial){final l=ListeningPoint.tryParse(j);if(l!=null)_byId[l.id]=l;}
  }
  List<ListeningPoint> get all=>_byId.values.toList()..sort((a,b)=>(a.heardAt??DateTime(0)).compareTo(b.heardAt??DateTime(0)));
  ListeningPoint? operator [](String id)=>_byId[id];

  /// A version from the server; an older one than the known is ignored.
  bool apply(Map<String,dynamic> j){
    final l=ListeningPoint.tryParse(j); if(l==null)return false;
    final old=_byId[l.id];
    if(old!=null&&old.updatedAt!=null&&l.updatedAt!=null&&l.updatedAt!.isBefore(old.updatedAt!))return false;
    _byId[l.id]=l; notifyListeners(); return true;
  }
  bool remove(String id){if(_byId.remove(id)==null)return false;notifyListeners();return true;}
}

/// The PCO deletes a listening point (at any time): removed here, then the
/// deletion leaves through the Outbox.
Future<void> deleteListeningPoint(ListeningPoint l,{required ListeningPoints points,required LocalStore store,
    required OfflineSyncService sync,required String eventId,required String actorId}) async {
  points.remove(l.id);
  await store.deleteMapFeature(l.id);
  await sync.queue(objectId:l.id,objectType:'map_feature',action:'delete',payload:{
    'id':l.id,'event_id':eventId,'updated_by':actorId,'updated_at':DateTime.now().toUtc().toIso8601String()});
}

/// Layers of the listening points: heading lines, then rings and labels.
List<Widget> buildListeningLayers(List<ListeningPoint> points,{required void Function(ListeningPoint) onTap}){
  if(points.isEmpty)return const [];
  final lines=[for(final l in points)
    if(l.headingDeg!=null)Polyline(points:[l.point,destination(l.point,listeningHeadingM,l.headingDeg!)],color:listeningColor,strokeWidth:3,
      pattern:l.exercise?StrokePattern.dashed(segments:const [8,6]):const StrokePattern.solid())];
  return [
    if(lines.isNotEmpty)PolylineLayer(polylines:lines),
    MarkerLayer(markers:[for(final l in points)Marker(point:l.point,width:120,height:64,
      child:GestureDetector(key:ValueKey('listening-${l.id}'),behavior:HitTestBehavior.translucent,onTap:()=>onTap(l),child:ListeningMark(point:l)))]),
  ];
}

/// Ring and label of one point, centred on its position.
class ListeningMark extends StatelessWidget {
  final ListeningPoint point;
  const ListeningMark({super.key,required this.point});
  @override Widget build(BuildContext context)=>Stack(alignment:Alignment.center,clipBehavior:Clip.none,children:[
    SizedBox(width:24,height:24,child:CustomPaint(painter:_RingPainter(dashed:point.exercise))),
    Positioned(top:0,child:Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:1),
      decoration:BoxDecoration(color:Colors.white.withValues(alpha:0.9),borderRadius:BorderRadius.circular(6),border:Border.all(color:listeningColor,width:1.5)),
      child:Text(listeningLabel(point),style:const TextStyle(fontSize:11,fontWeight:FontWeight.w700,color:Colors.black87)))),
  ]);
}

class _RingPainter extends CustomPainter {
  final bool dashed;
  const _RingPainter({required this.dashed});
  @override void paint(Canvas canvas,Size size){
    final c=size.center(Offset.zero); final r=size.shortestSide/2-2;
    canvas.drawCircle(c,r,Paint()..color=listeningColor.withValues(alpha:0.25));
    final stroke=Paint()..color=listeningColor..style=PaintingStyle.stroke..strokeWidth=3;
    if(!dashed){canvas.drawCircle(c,r,stroke);return;}
    const n=8; const sweep=math.pi/n;
    for(var i=0;i<n;i++){canvas.drawArc(Rect.fromCircle(center:c,radius:r),i*2*sweep,sweep,false,stroke);}
  }
  @override bool shouldRepaint(_RingPainter old)=>old.dashed!=dashed;
}

/// Sheet of a listening point: author, time, heading; « Supprimer » for
/// the PCO.
Future<void> showListeningSheet(BuildContext context,ListeningPoint l,{required bool canDelete,required VoidCallback onDelete}){
  final t=l.heardAt;
  final lines=[
    S.t('listening.by',{'who':l.createdBy,'time':t==null?'—':listeningClock(t)}),
    if(l.headingDeg!=null)S.t('listening.heading',{'deg':l.headingDeg!.round().toString().padLeft(3,'0')}),
    if(l.search.isNotEmpty||l.frequencyMhz!=null)[if(l.search.isNotEmpty)l.search,if(l.frequencyMhz!=null)'${l.frequencyMhz!.toStringAsFixed(3).replaceAll(RegExp(r'0+$'),'').replaceAll(RegExp(r'\.$'),'')} MHz'].join(' · '),
    if(l.comment.isNotEmpty)l.comment,
  ];
  return showModalBottomSheet<void>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
    ListTile(key:const ValueKey('listening-sheet'),leading:const Icon(Icons.hearing,color:listeningColor),
      title:Text(l.exercise?'${S.t('listening.ex')} · ${S.t('listening.title')}':S.t('listening.title')),
      subtitle:Text(lines.join('\n'))),
    if(canDelete)ListTile(key:const ValueKey('listening-delete'),leading:const Icon(Icons.delete_outline),title:Text(S.t('listening.delete')),
      onTap:(){Navigator.pop(c);onDelete();}),
  ])));
}
