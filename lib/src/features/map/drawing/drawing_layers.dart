import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'drawing_controller.dart';
import 'geometry.dart';
import 'map_feature.dart';

Color _c(int argb)=>Color(argb);

/// Map layers for the drawn objects and the shape in progress.
/// Placed above the tiles and traces, below the operator markers.
List<Widget> buildDrawingLayers(DrawingController c){
  final features=c.features;
  final closed=features.where((f)=>f.kind==FeatureKind.zone||f.kind==FeatureKind.rectangle).toList();
  final circles=features.where((f)=>f.kind==FeatureKind.circle).toList();
  final lines=features.where((f)=>f.kind.isLinear).toList();

  final labels=<Marker>[];
  final symbols=<Marker>[];
  for(final f in features){
    final selected=c.isSelected(f.id);
    switch(f.kind){
      case FeatureKind.point:
        symbols.add(Marker(point:f.points[0],width:40,height:40,alignment:Alignment.topCenter,child:Icon(Icons.place,size:38,color:_c(f.color).withValues(alpha:f.opacity),shadows:selected?const [Shadow(color:Colors.white,blurRadius:6)]:null)));
        if(f.label.isNotEmpty)labels.add(_label(f.points[0],f.label,f.color,below:true,opacity:f.opacity));
      case FeatureKind.text:
        symbols.add(Marker(point:f.points[0],width:textMarkerWidth(f.fontSize),height:textMarkerHeight(f.fontSize),child:Center(child:_faded(f.opacity,_TextChip(text:f.label.isEmpty?'Texte':f.label,color:f.color,selected:selected,fontSize:f.fontSize)))));
      case FeatureKind.arrow:
        if(f.points.length>=2){
          final a=f.points[f.points.length-2], b=f.points.last;
          final angle=bearingDeg(a,b)*math.pi/180;
          final size=18+f.strokeWidth*3;
          symbols.add(Marker(point:b,width:size,height:size,child:Transform.rotate(angle:angle,child:Icon(Icons.navigation,size:size,color:_c(f.color).withValues(alpha:f.opacity)))));
        }
        if(f.label.isNotEmpty)labels.add(_label(f.anchor,f.label,f.color,opacity:f.opacity));
      case FeatureKind.measure:
        labels.add(_label(f.points.last,formatDistance(f.lengthM),f.color,opacity:f.opacity));
        if(f.label.isNotEmpty)labels.add(_label(f.anchor,f.label,f.color,opacity:f.opacity));
      default:
        if(f.label.isNotEmpty)labels.add(_label(f.anchor,f.label,f.color,opacity:f.opacity));
    }
  }

  return [
    if(closed.isNotEmpty)PolygonLayer(polygons:closed.map((f)=>Polygon(
      points:f.ring,color:_c(f.color).withAlpha(((c.isSelected(f.id)?80:50)*f.opacity).round()),
      borderColor:_c(f.color).withValues(alpha:f.opacity),borderStrokeWidth:f.strokeWidth,
    )).toList()),
    if(circles.isNotEmpty)CircleLayer(circles:circles.map((f)=>CircleMarker(
      point:f.points[0],radius:f.radiusM??1,useRadiusInMeter:true,
      color:_c(f.color).withAlpha(((c.isSelected(f.id)?80:50)*f.opacity).round()),borderColor:_c(f.color).withValues(alpha:f.opacity),borderStrokeWidth:f.strokeWidth,
    )).toList()),
    if(lines.isNotEmpty)PolylineLayer(polylines:lines.map((f)=>Polyline(
      points:f.points,color:_c(f.color).withValues(alpha:f.opacity),strokeWidth:f.strokeWidth,
      pattern:f.kind==FeatureKind.measure?StrokePattern.dashed(segments:const [12,8]):const StrokePattern.solid(),
      borderColor:Colors.white.withValues(alpha:f.opacity),borderStrokeWidth:c.isSelected(f.id)?3:1,
      strokeCap:StrokeCap.round,strokeJoin:StrokeJoin.round,
    )).toList()),
    ..._draftLayers(c),
    if(symbols.isNotEmpty||labels.isNotEmpty)MarkerLayer(markers:[...symbols,...labels]),
  ];
}

List<Widget> _draftLayers(DrawingController c){
  final t=c.tool, d=c.draft;
  if(t==null||d.isEmpty)return const [];
  final color=_c(c.color);
  final vertices=MarkerLayer(markers:d.map((p)=>Marker(point:p,width:vertexHandlePx,height:vertexHandlePx,child:_vertexDot(color))).toList());
  if(t==FeatureKind.zone&&d.length>=3){
    return [PolygonLayer(polygons:[Polygon(points:d,color:color.withAlpha(40),borderColor:color,borderStrokeWidth:c.strokeWidth,pattern:StrokePattern.dashed(segments:const [10,6]))]),vertices];
  }
  if(d.length>=2){
    return [PolylineLayer(polylines:[Polyline(points:d,color:color,strokeWidth:c.strokeWidth,pattern:StrokePattern.dashed(segments:const [10,6]))]),vertices];
  }
  return [vertices];
}

/// Child drawn with the transparency of its object (no extra layer at 100 %).
Widget _faded(double opacity,Widget child)=>opacity>=1?child:Opacity(opacity:opacity,child:child);

Marker _label(LatLng p,String text,int color,{bool below=false,double opacity=1})=>Marker(
  point:p,width:180,height:30,alignment:below?Alignment.bottomCenter:Alignment.center,
  child:IgnorePointer(child:Center(child:_faded(opacity,Container(
    padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
    decoration:BoxDecoration(color:Colors.white.withAlpha(230),borderRadius:BorderRadius.circular(4),border:Border.all(color:_c(color))),
    child:Text(text,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w600,color:Colors.black87)),
  )))),
);

class _TextChip extends StatelessWidget {
  final String text; final int color; final bool selected; final double fontSize;
  const _TextChip({required this.text,required this.color,required this.selected,required this.fontSize});
  @override Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
    decoration:BoxDecoration(color:Colors.white.withAlpha(235),borderRadius:BorderRadius.circular(6),border:Border.all(color:_c(color),width:selected?3:1.5)),
    child:Text(text,maxLines:2,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:TextStyle(fontSize:fontSize,fontWeight:FontWeight.bold,color:_c(color))),
  );
}

/// Size of the marker of a Texte object, growing with its font size.
double textMarkerWidth(double fontSize)=>(fontSize*13).clamp(200.0,640.0);
double textMarkerHeight(double fontSize)=>(fontSize*2.6+10).clamp(48.0,220.0);

/// Editing handles (card « Dessin, poignées d'édition », reminder of
/// 30 Oct 2026, 10 h 39, validated 10 h 40): vertex dot of 8 px, white with
/// the colour of the object as border; move handle = arrowed cross of 12 px
/// without a circle; every handle inside an invisible touch area of 44 px;
/// discreet dots in the middle of the sides to add a vertex. These sizes
/// stay for the mouse (card « Dessin au doigt : poignées trop petites »,
/// lot 19, choice 2).
const vertexHandlePx=8.0, moveHandlePx=12.0, handleTouchPx=44.0, midHandlePx=6.0;

/// Touch screen (lot 19, choice 1): corners and vertices of 18 px, middle
/// of the sides of 12 px, move cross of 28 px in a semi-transparent circle,
/// touch area of 56 px.
const fingerVertexHandlePx=18.0, fingerMoveHandlePx=28.0, fingerHandleTouchPx=56.0, fingerMidHandlePx=12.0;

/// Sizes of the handles for the mouse or for the finger.
typedef HandleSizes=({double vertex,double mid,double move,double touch});
const mouseHandleSizes=(vertex:vertexHandlePx,mid:midHandlePx,move:moveHandlePx,touch:handleTouchPx);
const fingerHandleSizes=(vertex:fingerVertexHandlePx,mid:fingerMidHandlePx,move:fingerMoveHandlePx,touch:fingerHandleTouchPx);

/// True when the handles are drawn for the finger. Rule (lot 19): the kind
/// of the last pointer pressed (or hovering, for a mouse) decides; before
/// any, a phone or a tablet (Android, iOS, web included) means finger.
final ValueNotifier<bool> fingerHandles=ValueNotifier<bool>(isTouchPlatform(defaultTargetPlatform));

bool isTouchPlatform(TargetPlatform p)=>p==TargetPlatform.android||p==TargetPlatform.iOS;

/// Finger for a touch or a stylus, mouse for a mouse or a trackpad, null
/// for an unknown kind (no change).
bool? isFingerPointer(PointerDeviceKind kind)=>switch(kind){
  PointerDeviceKind.touch||PointerDeviceKind.stylus||PointerDeviceKind.invertedStylus=>true,
  PointerDeviceKind.mouse||PointerDeviceKind.trackpad=>false,
  _=>null,
};

bool _watchingPointers=false;
void _watchPointers(){
  if(_watchingPointers)return;
  _watchingPointers=true;
  GestureBinding.instance.pointerRouter.addGlobalRoute(notePointerForHandles);
}

/// Follows the last pointer used (global route of the pointer router).
void notePointerForHandles(PointerEvent e){
  if(e is! PointerDownEvent&&e is! PointerHoverEvent)return;
  final finger=isFingerPointer(e.kind);
  if(finger!=null&&fingerHandles.value!=finger)fingerHandles.value=finger;
}

Widget _vertexDot(Color color,[double size=vertexHandlePx])=>Center(child:Container(width:size,height:size,
  decoration:BoxDecoration(color:Colors.white,shape:BoxShape.circle,border:Border.all(color:color,width:size>vertexHandlePx?2.5:1.5),
    boxShadow:const [BoxShadow(blurRadius:2,color:Colors.black38)])));

/// Middle of each side of [f] where a vertex can be added: (index of the
/// new vertex, point). Lines and zones only (card « Dessin, curseurs et
/// flèches », validated 30 Oct 2026, 12 h 35): an arrow and a measure keep
/// their 2 points.
List<(int,LatLng)> sideMiddles(MapFeature f){
  final kinds={FeatureKind.line,FeatureKind.zone};
  if(!kinds.contains(f.kind)||f.points.length<2||f.points.length>60)return const [];
  final p=f.points, n=f.kind==FeatureKind.zone?p.length:p.length-1;
  return [for(var i=0;i<n;i++)(i+1,LatLng((p[i].latitude+p[(i+1)%p.length].latitude)/2,(p[i].longitude+p[(i+1)%p.length].longitude)/2))];
}

/// Draggable handles of the selection: vertex, corner, radius and side
/// handles for one object, then the move handle (the centre of all the
/// selected objects when several are selected). [toLatLng] converts a
/// global pointer position to map coordinates. Sizes follow the last
/// pointer used ([fingerHandles]).
Widget buildHandleLayer(DrawingController c,LatLng Function(Offset global) toLatLng){
  if(c.selection.isEmpty)return const SizedBox.shrink();
  _watchPointers();
  return ValueListenableBuilder<bool>(valueListenable:fingerHandles,
    builder:(_,finger,_)=>_handleLayer(c,toLatLng,finger?fingerHandleSizes:mouseHandleSizes));
}

Widget _handleLayer(DrawingController c,LatLng Function(Offset global) toLatLng,HandleSizes size){
  final all=c.selection;
  if(all.isEmpty)return const SizedBox.shrink();
  final f=all.first;
  final markers=<Marker>[];
  Marker handle(LatLng p,Widget look,{required void Function(LatLng from,LatLng to) onDrag,VoidCallback? onStart,String? key,MouseCursor cursor=SystemMouseCursors.move})=>Marker(
    point:p,width:size.touch,height:size.touch,
    child:_Handle(key:key==null?null:ValueKey(key),look:look,size:size.touch,cursor:cursor,toLatLng:toLatLng,onStart:onStart??c.beginEdit,onDrag:onDrag,onEnd:c.endEdit,onHold:c.holdHandle),
  );
  final anchor=f.anchor;
  final colour=_c(f.color);
  final dot=_vertexDot(colour,size.vertex);
  if(all.length==1){
    switch(f.kind){
      case FeatureKind.circle:
        final center=f.points[0];
        markers.add(handle(destination(center,f.radiusM??1,90),dot,key:'radius-handle',cursor:SystemMouseCursors.resizeLeftRight,onDrag:(_,to)=>c.setRadius(distanceM(center,to))));
      case FeatureKind.rectangle:
        // Four corners (lot 19, choice 3); the object keeps its 2 opposite
        // corners, the 2 others move the matching sides.
        final corners=rectangleCorners(f.points[0],f.points[1]);
        for(var i=0;i<4;i++){markers.add(handle(corners[i],dot,key:'corner-$i',cursor:cornerCursor(corners[i],anchor),onDrag:(_,to)=>c.moveRectangleCorner(i,to)));}
      case FeatureKind.line:
      case FeatureKind.arrow:
      case FeatureKind.zone:
      case FeatureKind.measure:
        if(f.points.length<=60){
          for(final (i,m) in sideMiddles(f)){
            markers.add(handle(m,Center(child:Container(width:size.mid,height:size.mid,
                decoration:BoxDecoration(color:Colors.white.withValues(alpha:0.85),shape:BoxShape.circle,border:Border.all(color:colour.withValues(alpha:0.7))))),
              cursor:addVertexCursor,onStart:(){c.beginEdit();c.insertVertex(i,m);},onDrag:(_,to)=>c.moveVertex(i,to)));
          }
          for(var i=0;i<f.points.length;i++){markers.add(handle(f.points[i],dot,cursor:cornerCursor(f.points[i],anchor),onDrag:(_,to)=>c.moveVertex(i,to)));}
        }
      default:
        break;
    }
  }
  // Move handle last so it stays on top of the others.
  final anchors=[for(final x in all)x.anchor];
  final centre=LatLng(anchors.map((a)=>a.latitude).reduce((a,b)=>a+b)/anchors.length,anchors.map((a)=>a.longitude).reduce((a,b)=>a+b)/anchors.length);
  final cross=Icon(Icons.open_with,size:size.move,color:colour,shadows:const [Shadow(blurRadius:3,color:Colors.white),Shadow(blurRadius:2,color:Colors.black54)]);
  // Finger: the cross sits in a semi-transparent circle (lot 19, choice 1).
  final finger=size.move>moveHandlePx;
  markers.add(handle(centre,Center(child:finger?Container(width:size.move+12,height:size.move+12,alignment:Alignment.center,
      decoration:BoxDecoration(color:Colors.white.withValues(alpha:0.6),shape:BoxShape.circle,border:Border.all(color:colour.withValues(alpha:0.6),width:1.5)),child:cross):cross),
    key:'move-handle',onDrag:(from,to)=>c.moveSelected(to.latitude-from.latitude,to.longitude-from.longitude)));
  return MarkerLayer(markers:markers);
}

/// Mouse cursors of the handles (card « Dessin, curseurs et flèches »,
/// 12 h 34): a corner resizes (diagonal double arrow), the middle of a side
/// adds a point, the central cross moves.
const addVertexCursor=SystemMouseCursors.copy;
MouseCursor cornerCursor(LatLng corner,LatLng centre)=>
  (corner.latitude>=centre.latitude)==(corner.longitude>=centre.longitude)?SystemMouseCursors.resizeUpRightDownLeft:SystemMouseCursors.resizeUpLeftDownRight;

class _Handle extends StatefulWidget {
  final Widget look; final MouseCursor cursor; final double size;
  final LatLng Function(Offset) toLatLng;
  final VoidCallback onStart, onEnd;
  final void Function(LatLng from,LatLng to) onDrag;
  final void Function(bool held) onHold;
  const _Handle({super.key,required this.look,required this.size,required this.cursor,required this.toLatLng,required this.onStart,required this.onDrag,required this.onEnd,required this.onHold});
  @override State<_Handle> createState()=>_HandleState();
}

class _HandleState extends State<_Handle> {
  LatLng? _last;
  bool _held=false;

  void _start(DragStartDetails d){_last=widget.toLatLng(d.globalPosition);_held=true;widget.onHold(true);widget.onStart();}
  void _update(DragUpdateDetails d){final to=widget.toLatLng(d.globalPosition);final from=_last??to;_last=to;widget.onDrag(from,to);}
  void _end(){_last=null;widget.onEnd();_release();}
  void _release(){if(_held){_held=false;widget.onHold(false);}}

  @override void dispose(){
    // Handle removed while held (selection changed): free the map after
    // this frame, not while the tree is being finalised.
    if(_held){final hold=widget.onHold;WidgetsBinding.instance.addPostFrameCallback((_)=>hold(false));}
    super.dispose();
  }

  @override Widget build(BuildContext context)=>MouseRegion(cursor:widget.cursor,child:RawGestureDetector(
    behavior:HitTestBehavior.opaque,
    gestures:{HandleDragRecognizer:GestureRecognizerFactoryWithHandlers<HandleDragRecognizer>(
      ()=>HandleDragRecognizer(debugOwner:this),
      (r){r..onStart=_start..onUpdate=_update..onEnd=((_)=>_end())..onCancel=_end;},
    )},
    child:SizedBox(width:widget.size,height:widget.size,child:widget.look),
  ));
}

/// Drag of a handle. With a finger or a stylus, the handle wins the gesture
/// arena as soon as it is touched (lot 19, choice 4): the map neither pans
/// nor zooms while a finger holds a handle. With a mouse, the usual drag.
class HandleDragRecognizer extends PanGestureRecognizer {
  HandleDragRecognizer({super.debugOwner});
  @override void addAllowedPointer(PointerDownEvent event){
    super.addAllowedPointer(event);
    if(isFingerPointer(event.kind)==true)resolvePointer(event.pointer,GestureDisposition.accepted);
  }
}
