import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../l10n/strings.dart';
import '../../../features/map/drawing/geometry.dart' as geo;
import 'bearing_models.dart';
import 'zone_window.dart';

/// Bearings on the map: cone, line, point where taken; crossings and the
/// probable zone of each search; the bearing being taken, in bold.
/// Line and cone take the colour of the signal (crossings readable), or of
/// the operator when [byOperator]; the dot where it was taken always the
/// operator's, with initials. [zoneModes]: mode of each signal (settings
/// `zone_modes`); touching the label or the circle of a zone calls
/// [onTapZone] (card « Plusieurs zones », point 9).
List<Widget> buildBearingLayers({required Iterable<Bearing> bearings,Bearing? draft,bool byOperator=false,LayerHitNotifier<Bearing>? hits,
    Map<String,String> zoneModes=const {},required void Function(Bearing) onTapBearing,required void Function(ZoneTap tap) onTapZone}){
  final groups=bySearch(bearings);
  final names=searchNames(bearings);
  String shown(Bearing b)=>names[searchKey(b.search)]??b.search;
  final zones={for(final e in groups.entries)e.key:probableZones(e.value,mode:zoneModeOf(zoneModes,e.key))};
  final excluded={for(final zs in zones.values)for(final z in zs)...z.excluded};
  final cones=<Polygon>[], lines=<Polyline<Bearing>>[], markers=<Marker>[], circles=<CircleMarker>[], outlines=<Polyline>[];
  // Zone circles under the bearing lines: a touch on a line still selects
  // the bearing, elsewhere in the circle it opens the zone window.
  final zoneCircles=<CircleMarker<ZoneTap Function(Offset)>>[];
  final LayerHitNotifier<ZoneTap Function(Offset)> zoneHits=ValueNotifier(null);
  void add(Bearing b,{bool live=false}){
    // A bearing set aside from the zone: grey dashed line, no cone.
    if(!live&&excluded.contains(b.id)){
      lines.add(Polyline<Bearing>(points:[b.origin,b.end],color:const Color(0xFF8A8F98),strokeWidth:2,pattern:StrokePattern.dashed(segments:const [10,8]),hitValue:b));
      return;
    }
    final c=Color(byOperator?(b.operatorColor??operatorColor(b.createdBy)):searchColor(shown(b))); final (l,r)=b.cone;
    cones.add(Polygon(points:[b.origin,l,r],color:c.withValues(alpha:live?0.16:0.10),borderColor:c.withValues(alpha:0.35),borderStrokeWidth:1));
    lines.add(Polyline<Bearing>(points:[b.origin,b.end],color:c,strokeWidth:live?3.5:2.2,hitValue:live?null:b));
  }
  for(final b in bearings){add(b);}
  if(draft!=null)add(draft,live:true);
  for(final b in bearings){
    final op=Color(b.operatorColor??operatorColor(b.createdBy)), line=byOperator?op:Color(searchColor(shown(b)));
    markers.add(Marker(point:b.origin,width:30,height:30,child:Tooltip(message:['${b.azimuthDeg.toStringAsFixed(0).padLeft(3,'0')}°',b.createdBy,if(b.search.isNotEmpty)b.search,if(b.exercise)'EXERCICE'].join(' · '),
      child:GestureDetector(onTap:()=>onTapBearing(b),child:Container(alignment:Alignment.center,
        decoration:BoxDecoration(color:op,shape:BoxShape.circle,border:Border.all(color:line,width:2.5)),
        child:Text(operatorInitials(b.createdBy),style:const TextStyle(fontSize:10,fontWeight:FontWeight.w700,color:Colors.white,height:1)))))));
  }
  for(final e in groups.entries){for(final z in zones[e.key]!){
    final c=Color(searchColor(e.key));
    for(final p in z.crossings){circles.add(CircleMarker(point:p,radius:4,color:c));}
    if(z.centre==null)continue;
    // Signage of the validated mockup (1 Nov 2026): exercise = orange dashed
    // contour, real search = red solid; label outside the circle, linked to
    // its edge by a short line, white text, « EX » pill.
    final ex=e.value.any((b)=>b.exercise);
    final zc=ex?const Color(0xFFFF9F1C):const Color(0xFFFF4D5E);
    ZoneTap tap(Offset at)=>ZoneTap(search:e.key,zone:z,bearings:e.value,position:at);
    zoneCircles.add(CircleMarker<ZoneTap Function(Offset)>(point:z.centre!,radius:z.radiusM,useRadiusInMeter:true,color:zc.withValues(alpha:0.13),
      borderColor:ex?Colors.transparent:zc,borderStrokeWidth:ex?0:2,hitValue:tap));
    if(ex){
      outlines.add(Polyline(points:[for(var a=0;a<=360;a+=5)geo.destination(z.centre!,z.radiusM,a.toDouble())],color:zc,strokeWidth:3,
        pattern:StrokePattern.dashed(segments:const [14,9])));
    }
    final edge=geo.destination(z.centre!,z.radiusM,60), tip=geo.destination(z.centre!,z.radiusM*1.35+150,60);
    outlines.add(Polyline(points:[edge,tip],color:zc,strokeWidth:2));
    final freq=e.value.map((b)=>b.frequencyMhz).whereType<double>().toSet();
    final parts=zonesLabel(z).split(' · ');
    markers.add(Marker(point:tip,width:240,height:28,alignment:Alignment.centerRight,child:GestureDetector(onTapUp:(d)=>onTapZone(tap(d.globalPosition)),
      child:Tooltip(message:[S.t('bearings.zoneTitle'),if(e.key.isNotEmpty)e.key,for(final f in freq)'${f.toStringAsFixed(3)} MHz',if(ex)'EXERCICE'].join(' · '),
        child:Align(alignment:Alignment.centerLeft,child:Container(key:const ValueKey('bearing-zone-label'),padding:const EdgeInsets.symmetric(horizontal:7,vertical:3),
          decoration:BoxDecoration(color:const Color(0xF208111C),borderRadius:BorderRadius.circular(7),border:Border.all(color:zc,width:1.5)),
          child:Row(mainAxisSize:MainAxisSize.min,children:[
            if(ex)Container(margin:const EdgeInsets.only(right:5),padding:const EdgeInsets.symmetric(horizontal:4),decoration:BoxDecoration(color:zc,borderRadius:BorderRadius.circular(3)),
              child:const Text('EX',style:TextStyle(fontSize:10,fontWeight:FontWeight.w900,color:Color(0xFF14201A),height:1.3))),
            Text(parts.take(2).join(' · '),maxLines:1,softWrap:false,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w600,color:Colors.white,height:1.2)),
            if(parts.length>2)Text(' · ${parts.skip(2).join(' · ')}',maxLines:1,softWrap:false,style:const TextStyle(fontSize:11,color:Color(0xFFB8C6D6),height:1.2)),
          ])))))));
  }}
  return [
    if(cones.isNotEmpty)PolygonLayer(polygons:cones),
    if(zoneCircles.isNotEmpty)MouseRegion(hitTestBehavior:HitTestBehavior.deferToChild,cursor:SystemMouseCursors.click,child:GestureDetector(
      onTapUp:(d){final h=zoneHits.value;if(h!=null&&h.hitValues.isNotEmpty)onTapZone(h.hitValues.first(d.globalPosition));},
      child:CircleLayer<ZoneTap Function(Offset)>(hitNotifier:zoneHits,circles:zoneCircles))),
    // The whole line selects the bearing (« Relevés, sélection »), not only
    // the dot often hidden under an operator; wide touch area around it.
    if(lines.isNotEmpty)hits==null?PolylineLayer<Bearing>(polylines:lines):MouseRegion(hitTestBehavior:HitTestBehavior.deferToChild,
      cursor:SystemMouseCursors.click,child:GestureDetector(
        onTap:(){final h=hits.value;if(h!=null&&h.hitValues.isNotEmpty)onTapBearing(h.hitValues.first);},
        child:PolylineLayer<Bearing>(hitNotifier:hits,minimumHitbox:24,polylines:lines))),
    if(circles.isNotEmpty)CircleLayer(circles:circles),
    if(outlines.isNotEmpty)PolylineLayer(polylines:outlines),
    if(markers.isNotEmpty)MarkerLayer(markers:markers),
  ];
}
