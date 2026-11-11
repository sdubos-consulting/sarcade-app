import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform,kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import '../../l10n/strings.dart';
import '../settings/theme_choice.dart';
import 'basemap_models.dart';
import 'keep_on_phone.dart';
import '../../ui/app_sheet.dart';

/// Panel « Carte » (card « Panneau Carte : seulement le fond en cours, les
/// autres dans une page, vraies vignettes », validated on 9 Nov 2026): the
/// base map in use on one line (thumbnail, name, use, « › »), then the theme
/// and the layers. A touch on the line shows, in the same panel, the page
/// « Fond de carte »: one line per base map with a real thumbnail of the
/// same place, the chosen one highlighted with ✓, and « Préférer les cartes
/// téléchargées ». [tileUrlOf] and [around] give the real thumbnails;
/// without them, or while they load or fail, a drawing in the style of the
/// base map (never an error page).
Future<void> showBasemapSheet(BuildContext context,{required List<Basemap> catalog,required Basemap current,
    required String eventDefault,required bool preferOffline,
    required void Function(String id) onChoose,required ValueChanged<bool> onPreferOffline,
    List<Widget> Function(BuildContext context,StateSetter refresh)? layers,
    String? Function(Basemap b)? tileUrlOf,({double lat,double lon})? around,String? serverUrl}) {
  var offline=preferOffline;
  var selected=current.id;
  var choosing=false;
  List<String>? tilesOf(Basemap b,{int columns=2})=>around==null?null:thumbTileUrls(tileUrlOf?.call(b),around.lat,around.lon,columns:columns);
  // Handle at the top and swipe down to close (card « Carte : fermer le
  // panneau « Carte » en le glissant vers le bas », 10 Nov 2026, choice 1).
  return showAppSheet<void>(context:context,isScrollControlled:true,builder:(c)=>StatefulBuilder(builder:(c,set){
    final scheme=Theme.of(c).colorScheme;
    final chosen=catalog.firstWhere((b)=>b.id==selected,orElse:()=>current);
    final cross=basemapSheetHasCross(c);
    final header=Padding(padding:const EdgeInsets.fromLTRB(4,0,4,4),child:Row(children:[
      if(choosing)IconButton(key:const ValueKey('basemap-back'),tooltip:S.t('basemap.back'),onPressed:()=>set(()=>choosing=false),icon:const Icon(Icons.arrow_back))
      else const SizedBox(width:12),
      // Without the cross (phones, choice 2), VoiceOver and TalkBack keep
      // « Fermer » among the actions of the title.
      Expanded(child:Semantics(customSemanticsActions:cross?null:{CustomSemanticsAction(label:S.t('common.close')):()=>Navigator.pop(c)},
        child:Text(choosing?S.t('basemap.title'):S.t('map.panelTitle'),style:Theme.of(c).textTheme.titleLarge))),
      if(cross)IconButton(key:const ValueKey('basemap-close'),tooltip:S.t('common.close'),onPressed:()=>Navigator.pop(c),icon:const Icon(Icons.close))
      else const SizedBox(height:kMinInteractiveDimension),
    ]));
    final children=choosing?[
      header,
      for(final b in catalog)BasemapRow(key:ValueKey('basemap-${b.id}'),basemap:b,selected:b.id==selected,tiles:tilesOf(b),
        // A base map touched: applied and the panel closed, back to the map
        // (card « Fond de carte : choisir un fond ferme le panneau », 9 Nov 2026).
        onTap:(){if(b.id!=selected)onChoose(b.id);Navigator.pop(c);}),
      if(catalog.any((b)=>b.hasOfflinePackage))SwitchListTile(key:const ValueKey('basemap-offline'),
        value:offline,onChanged:(v){onPreferOffline(v);set(()=>offline=v);},
        title:Text(S.t('basemap.preferOffline')),subtitle:Text(S.t('basemap.preferOfflineHelp'))),
      const SizedBox(height:12),
    ]:[
      header,
      Padding(padding:const EdgeInsets.fromLTRB(16,0,16,4),child:Text(S.t('basemap.title'),style:Theme.of(c).textTheme.titleMedium?.copyWith(color:scheme.primary))),
      BasemapRow(key:const ValueKey('basemap-current'),basemap:chosen,selected:true,tiles:tilesOf(chosen,columns:4),compact:true,
        onTap:()=>set(()=>choosing=true)),
      // Offline package of the server: kept on this phone (9 Nov 2026).
      if(serverUrl!=null&&canKeepOnPhone(chosen))KeepOnPhoneTile(basemap:chosen,serverUrl:serverUrl),
      const SizedBox(height:4),
      const ThemeChoice(),
      ...?layers?.call(c,set),
      const SizedBox(height:12),
    ];
    return SafeArea(child:ConstrainedBox(constraints:BoxConstraints(maxHeight:MediaQuery.sizeOf(c).height*0.85),
      child:ListView(shrinkWrap:true,children:children)));
  }));
}

/// The cross of the panel « Carte »: only where there is no swipe — Windows,
/// the web, Linux, macOS and the TV (moved by its remote); the iPhone and
/// Android close the panel by a swipe down (10 Nov 2026, choice 2).
bool basemapSheetHasCross(BuildContext context){
  if(kIsWeb)return true;
  if(MediaQuery.maybeNavigationModeOf(context)==NavigationMode.directional)return true;
  return defaultTargetPlatform!=TargetPlatform.iOS&&defaultTargetPlatform!=TargetPlatform.android;
}

/// Short name of the known base maps (« Photos aériennes »).
String basemapShortName(Basemap b)=>switch(b.id){'ign-photos'=>S.t('basemap.short.photos'),_=>b.name};

/// One line under the name of the known base maps.
String? basemapDescription(Basemap b)=>switch(b.id){
  'osm'=>S.t('basemap.desc.osm'),'topo'=>S.t('basemap.desc.topo'),
  'ign-plan'=>S.t('basemap.desc.ignPlan'),'ign-photos'=>S.t('basemap.desc.photos'),_=>null};

/// Zoom of the thumbnail: a small town and its surroundings, where each base
/// map is recognisable (9 Nov 2026: one tile at 14 showed a field).
const thumbZoom=13;

/// The tiles (2 rows of [columns], left to right then top to bottom) around
/// a point at [thumbZoom], the point near their middle: 2 × 2 for the square
/// thumbnail of the page « Fond de carte », 4 × 2 for the thumbnail of the
/// panel, twice as wide, the same place over a wider band at the same scale
/// (10 Nov 2026, choice 3).
List<String>? thumbTileUrls(String? template,double lat,double lon,{int columns=2}){
  if(template==null||!template.contains('{z}'))return null;
  final n=math.pow(2,thumbZoom).toDouble();
  final fx=(lon+180)/360*n;
  final r=lat*math.pi/180;
  final fy=(1-math.log(math.tan(r)+1/math.cos(r))/math.pi)/2*n;
  final x0=(fx-columns/2+0.5).floor(), y0=(fy-0.5).floor();
  String url(int x,int y)=>template.replaceAll('{z}','$thumbZoom').replaceAll('{x}','$x').replaceAll('{y}','$y').replaceAll('{s}','a');
  return [for(var y=y0;y<y0+2;y++)for(var x=x0;x<x0+columns;x++)url(x,y)];
}

/// Same identification as the map (`userAgentPackageName`): the servers of
/// OpenStreetMap refuse anonymous requests (« Access blocked », 9 Nov 2026).
/// A browser sends its own and may not change it.
const thumbHeaders=kIsWeb?<String,String>{}:{'User-Agent':'flutter_map (org.sarcade.app)'};

/// One base map on one line: real thumbnail (tiles of the same place, in two
/// rows), name, what it is for, ✓ when chosen. [compact]: the line of the
/// panel, with « › » to open the page of the base maps, and a thumbnail
/// twice as wide as high ([compactThumbWidth] × [compactThumbHeight], card
/// « … vignette du fond deux fois plus large », 10 Nov 2026, choice 3); the
/// page keeps its squares of [thumbSize] (choice 4).
/// Thumbnail of the page « Fond de carte » (square).
const thumbSize=96.0;
/// Thumbnail of the panel « Carte »: twice as wide as high.
const compactThumbWidth=144.0, compactThumbHeight=72.0;

class BasemapRow extends StatelessWidget {
  final Basemap basemap; final bool selected; final List<String>? tiles; final VoidCallback onTap; final bool compact;
  const BasemapRow({super.key,required this.basemap,required this.selected,required this.onTap,this.tiles,this.compact=false});
  @override Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    final desc=basemapDescription(basemap);
    final width=compact?compactThumbWidth:thumbSize, height=compact?compactThumbHeight:thumbSize;
    final drawing=CustomPaint(painter:ThumbPainter(thumbStyle(basemap)),child:const SizedBox.expand());
    Widget tile(String u)=>Image.network(u,headers:thumbHeaders,fit:BoxFit.cover,
      loadingBuilder:(c,child,p)=>p==null?child:const SizedBox.expand(),errorBuilder:(c,e,s)=>const SizedBox.expand());
    final t=tiles;
    final picture=t==null?drawing:Stack(fit:StackFit.expand,children:[drawing,
      // Square tiles, never stretched: 2 rows of t.length/2 (2 × 2 in a
      // square, 4 × 2 in the thumbnail twice as wide).
      Column(children:[for(var r=0;r<2;r++)
        Expanded(child:Row(children:[for(var i=0;i<t.length~/2;i++)Expanded(child:tile(t[r*(t.length~/2)+i]))])),
      ])]);
    return Semantics(button:true,selected:selected,label:basemapShortName(basemap),child:InkWell(onTap:onTap,
      child:Container(margin:const EdgeInsets.symmetric(horizontal:8,vertical:2),padding:const EdgeInsets.all(8),
        decoration:BoxDecoration(color:selected&&!compact?scheme.primaryContainer.withValues(alpha:0.5):null,borderRadius:BorderRadius.circular(14)),
        child:Row(children:[
          Container(key:const ValueKey('basemap-thumb'),width:width,height:height,clipBehavior:Clip.antiAlias,
            decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),
              border:Border.all(color:selected?scheme.primary:scheme.outlineVariant,width:selected?3:1)),
            child:Stack(fit:StackFit.expand,children:[
              picture,
              if(basemap.hasOfflinePackage)Positioned(right:4,top:4,child:Tooltip(message:S.t('basemap.offlineAvailable'),
                child:Container(padding:const EdgeInsets.all(2),decoration:BoxDecoration(color:scheme.surface,shape:BoxShape.circle),
                  child:Icon(Icons.offline_pin,size:16,color:scheme.primary)))),
            ])),
          const SizedBox(width:14),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[
              Flexible(child:Text(basemapShortName(basemap),style:Theme.of(context).textTheme.titleMedium)),
              if(selected&&!compact)...[const SizedBox(width:6),Icon(Icons.check,size:18,color:scheme.primary)],
            ]),
            if(desc!=null)Text(desc,style:TextStyle(fontSize:13,color:scheme.onSurfaceVariant)),
            if(compact)Text(S.t('basemap.change'),style:TextStyle(fontSize:13,color:scheme.primary)),
          ])),
          if(compact)Icon(Icons.chevron_right,color:scheme.onSurfaceVariant),
        ]))));
  }
}

/// Style of the drawing shown instead of a real thumbnail.
enum ThumbStyle {streets,relief,ign,photo,other}
ThumbStyle thumbStyle(Basemap b)=>switch(b.id){'osm'=>ThumbStyle.streets,'topo'=>ThumbStyle.relief,'ign-plan'=>ThumbStyle.ign,'ign-photos'=>ThumbStyle.photo,_=>ThumbStyle.other};

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
