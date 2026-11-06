import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../settings/theme_choice.dart';
import 'basemap_models.dart';

/// One panel « Carte » (card « fond de carte en vignettes, un seul
/// panneau », lot 29.2): no tabs any more. Header « Carte » with ✕, the base
/// maps as thumbnails in two columns (the chosen one framed in blue), then
/// the theme and the layers. The panel takes the height of its content.
/// [tileUrlOf] and [around] give the real thumbnail (a tile of the base map
/// around my position); without them, or while it loads or fails, a drawing
/// in the style of the base map.
Future<void> showBasemapSheet(BuildContext context,{required List<Basemap> catalog,required Basemap current,
    required String eventDefault,required bool preferOffline,
    required void Function(String id) onChoose,required ValueChanged<bool> onPreferOffline,
    List<Widget> Function(BuildContext context,StateSetter refresh)? layers,
    String? Function(Basemap b)? tileUrlOf,({double lat,double lon})? around}) {
  var offline=preferOffline;
  // The frame follows the choice while the panel stays open (29 Oct 2026).
  var selected=current.id;
  return showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(c)=>StatefulBuilder(builder:(c,set){
    final scheme=Theme.of(c).colorScheme;
    final grid=GridView.count(crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),
      padding:const EdgeInsets.symmetric(horizontal:16),mainAxisSpacing:12,crossAxisSpacing:12,childAspectRatio:1.05,
      children:[for(final b in catalog)BasemapThumb(key:ValueKey('basemap-${b.id}'),basemap:b,selected:b.id==selected,
        tileUrl:around==null?null:thumbTileUrl(tileUrlOf?.call(b),around.lat,around.lon),
        onTap:(){onChoose(b.id);set(()=>selected=b.id);})]);
    return SafeArea(child:ConstrainedBox(constraints:BoxConstraints(maxHeight:MediaQuery.sizeOf(c).height*0.85),
      child:ListView(shrinkWrap:true,children:[
        Padding(padding:const EdgeInsets.fromLTRB(16,8,4,4),child:Row(children:[
          Expanded(child:Text(S.t('map.panelTitle'),style:Theme.of(c).textTheme.titleLarge)),
          IconButton(key:const ValueKey('basemap-close'),tooltip:S.t('common.close'),onPressed:()=>Navigator.pop(c),icon:const Icon(Icons.close)),
        ])),
        Padding(padding:const EdgeInsets.fromLTRB(16,0,16,8),child:Text(S.t('basemap.title'),style:Theme.of(c).textTheme.titleMedium?.copyWith(color:scheme.primary))),
        grid,
        if(catalog.any((b)=>b.hasOfflinePackage))SwitchListTile(
          value:offline,
          onChanged:(v){onPreferOffline(v);set(()=>offline=v);},
          title:Text(S.t('basemap.preferOffline')),
        ),
        const SizedBox(height:4),
        const ThemeChoice(),
        ...?layers?.call(c,set),
        const SizedBox(height:12),
      ])));
  }));
}

/// Short name of the known base maps (« Photos aériennes »).
String basemapShortName(Basemap b)=>switch(b.id){'ign-photos'=>S.t('basemap.short.photos'),_=>b.name};

/// One line under the name of the known base maps.
String? basemapDescription(Basemap b)=>switch(b.id){
  'osm'=>S.t('basemap.desc.osm'),'topo'=>S.t('basemap.desc.topo'),
  'ign-plan'=>S.t('basemap.desc.ignPlan'),'ign-photos'=>S.t('basemap.desc.photos'),_=>null};

/// Zoom of the thumbnail tile: a neighbourhood.
const thumbZoom=14;

/// URL of the tile around a point at [thumbZoom] ({z}, {x}, {y} filled).
String? thumbTileUrl(String? template,double lat,double lon){
  if(template==null||!template.contains('{z}'))return null;
  final n=math.pow(2,thumbZoom).toDouble();
  final x=((lon+180)/360*n).floor();
  final r=lat*math.pi/180;
  final y=((1-math.log(math.tan(r)+1/math.cos(r))/math.pi)/2*n).floor();
  return template.replaceAll('{z}','$thumbZoom').replaceAll('{x}','$x').replaceAll('{y}','$y').replaceAll('{s}','a');
}

/// Style of the drawing shown instead of a real thumbnail.
enum ThumbStyle {streets,relief,ign,photo,other}
ThumbStyle thumbStyle(Basemap b)=>switch(b.id){'osm'=>ThumbStyle.streets,'topo'=>ThumbStyle.relief,'ign-plan'=>ThumbStyle.ign,'ign-photos'=>ThumbStyle.photo,_=>ThumbStyle.other};

class BasemapThumb extends StatelessWidget {
  final Basemap basemap; final bool selected; final String? tileUrl; final VoidCallback onTap;
  const BasemapThumb({super.key,required this.basemap,required this.selected,required this.onTap,this.tileUrl});
  @override Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    final desc=basemapDescription(basemap);
    final drawing=CustomPaint(painter:ThumbPainter(thumbStyle(basemap)),child:const SizedBox.expand());
    final picture=tileUrl==null?drawing:Image.network(tileUrl!,fit:BoxFit.cover,
      loadingBuilder:(c,child,p)=>p==null?child:drawing,errorBuilder:(c,e,s)=>drawing);
    return Semantics(button:true,selected:selected,label:basemapShortName(basemap),child:InkWell(borderRadius:BorderRadius.circular(12),onTap:onTap,
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Expanded(child:Container(
          decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),border:Border.all(color:selected?scheme.primary:scheme.outlineVariant,width:selected?3:1)),
          clipBehavior:Clip.antiAlias,
          child:Stack(fit:StackFit.expand,children:[
            picture,
            if(basemap.hasOfflinePackage)Positioned(right:4,top:4,child:Tooltip(message:S.t('basemap.offlineAvailable'),
              child:Container(padding:const EdgeInsets.all(2),decoration:BoxDecoration(color:scheme.surface,shape:BoxShape.circle),
                child:Icon(Icons.offline_pin,size:16,color:scheme.primary)))),
          ]))),
        const SizedBox(height:4),
        Text(basemapShortName(basemap),maxLines:1,overflow:TextOverflow.ellipsis,
          style:TextStyle(fontWeight:selected?FontWeight.w700:FontWeight.w500,color:selected?scheme.primary:null)),
        if(desc!=null)Text(desc,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:12,color:scheme.onSurfaceVariant)),
      ])));
  }
}

/// Drawing in the style of each base map (simulation of 5 Nov 2026, 19 h 36):
/// streets and buildings, contour lines and a path, the yellow road and pink
/// built-up area of IGN, fields seen from the sky.
class ThumbPainter extends CustomPainter {
  final ThumbStyle style;
  ThumbPainter(this.style);
  @override void paint(Canvas canvas,Size size){
    final w=size.width,h=size.height;
    Paint fill(int c)=>Paint()..color=Color(c);
    Paint line(int c,double width)=>Paint()..color=Color(c)..style=PaintingStyle.stroke..strokeWidth=width..strokeCap=StrokeCap.round;
    switch(style){
      case ThumbStyle.streets:
        canvas.drawRect(Offset.zero&size,fill(0xFFF2EFE9));
        canvas.drawRect(Rect.fromLTWH(w*.08,h*.1,w*.3,h*.25),fill(0xFFD9D0C9));
        canvas.drawRect(Rect.fromLTWH(w*.6,h*.55,w*.3,h*.3),fill(0xFFD9D0C9));
        canvas.drawRect(Rect.fromLTWH(w*.1,h*.6,w*.35,h*.3),fill(0xFFCDEBB0));
        canvas.drawLine(Offset(0,h*.45),Offset(w,h*.45),line(0xFFFFFFFF,6));
        canvas.drawLine(Offset(w*.5,0),Offset(w*.5,h),line(0xFFFCD6A4,7));
      case ThumbStyle.relief:
        canvas.drawRect(Offset.zero&size,fill(0xFFE8EED8));
        for(var i=1;i<=4;i++){canvas.drawOval(Rect.fromCenter(center:Offset(w*.55,h*.45),width:w*.22*i,height:h*.16*i),line(0xFFB89C6E,1.2));}
        final path=Path()..moveTo(0,h*.85)..quadraticBezierTo(w*.3,h*.6,w*.5,h*.75)..quadraticBezierTo(w*.75,h*.9,w,h*.55);
        canvas.drawPath(path,line(0xFFC0392B,2)..strokeCap=StrokeCap.butt);
      case ThumbStyle.ign:
        canvas.drawRect(Offset.zero&size,fill(0xFFFFFFFF));
        canvas.drawRect(Rect.fromLTWH(w*.15,h*.15,w*.45,h*.35),fill(0xFFF6C9C4));
        canvas.drawRect(Rect.fromLTWH(w*.65,h*.6,w*.3,h*.35),fill(0xFFD7EBC4));
        canvas.drawLine(Offset(0,h*.7),Offset(w,h*.35),line(0xFFF7D34A,6));
        canvas.drawLine(Offset(w*.2,h),Offset(w*.35,0),line(0xFFBDBDBD,3));
      case ThumbStyle.photo:
        canvas.drawRect(Offset.zero&size,fill(0xFF5B6B3A));
        canvas.drawRect(Rect.fromLTWH(0,0,w*.5,h*.45),fill(0xFF8A8F4E));
        canvas.drawRect(Rect.fromLTWH(w*.5,h*.45,w*.5,h*.55),fill(0xFF7C6A45));
        canvas.drawRect(Rect.fromLTWH(w*.55,h*.05,w*.4,h*.35),fill(0xFF3F5130));
        canvas.drawLine(Offset(0,h*.45),Offset(w,h*.48),line(0xFFC8C2B0,3));
      case ThumbStyle.other:
        canvas.drawRect(Offset.zero&size,fill(0xFFE3E7EC));
        canvas.drawLine(Offset(0,h*.6),Offset(w,h*.4),line(0xFFFFFFFF,5));
        canvas.drawLine(Offset(w*.4,0),Offset(w*.6,h),line(0xFFFFFFFF,3));
    }
  }
  @override bool shouldRepaint(ThumbPainter old)=>old.style!=style;
}

/// Licence notices of the base maps (OpenStreetMap, OpenTopoMap, IGN), each
/// once, for the ⓘ of the map and Paramètres › À propos.
List<String> basemapNotices(Iterable<Basemap> catalog)=>{
  for(final b in catalog)if(b.attribution.trim().isNotEmpty)b.attribution.trim()}.toList();
