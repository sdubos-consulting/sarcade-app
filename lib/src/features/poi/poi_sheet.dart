/// Points of interest (decision of the project owner, 29 Oct 2026, option A):
/// sheet on touch (name, author, time, coordinates), modify, move, delete with
/// confirmation, send in a message, route to here; everyone changes his own
/// points, the PCO all of them. Pin in the author's drawing colour, never
/// the red kept for the 121.5 MHz beacons.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../l10n/strings.dart';
import '../../models/comm_group.dart' show isPco;
import '../../models/poi.dart';
import '../../offline/local_store.dart';
import '../../offline/sync_service.dart';
import '../../ui/map_sheet.dart';
import '../../ui/operator_color.dart';
import '../map/drawing/import_formats.dart' show ImportedShape;
import '../map/drawing/map_feature.dart' show FeatureKind;
import '../measure/coordinates.dart';
import 'poi_icons.dart';

/// Colour used instead of a red one (reserved for the beacons).
const poiFallbackColor=0xFF1E88E5;

/// True for a red: hue within 20° of 0 and saturated enough to be read as red.
bool isReservedRed(int argb){
  final hsv=HSVColor.fromColor(Color(argb));
  return hsv.saturation>0.45&&hsv.value>0.35&&(hsv.hue<=20||hsv.hue>=340);
}

/// Colour stored on a new point: the author's drawing colour, red excluded.
int poiColorFor(int drawColor)=>isReservedRed(drawColor)?poiFallbackColor:drawColor;

/// Colour of the pin: the stored colour (chosen in the window of the
/// point since lot 25, red Danger included), else derived from the author,
/// red excluded.
int poiColor(SarcadePoi p)=>p.color??poiColorFor(p.createdBy==null?poiFallbackColor:operatorColor(p.createdBy!));

bool canEditPoi(SarcadePoi p,String actor)=>isPco(actor)||(p.createdBy!=null&&p.createdBy==actor);

String poiName(SarcadePoi p)=>(p.label??'').trim().isEmpty?S.t('poi.unnamed'):p.label!.trim();

String poiTime(DateTime t,[DateTime? now]){
  final l=t.toLocal(); final n=(now??DateTime.now()).toLocal();
  String two(int v)=>v.toString().padLeft(2,'0');
  final hm='${two(l.hour)}:${two(l.minute)}';
  return l.year==n.year&&l.month==n.month&&l.day==n.day?hm:'${two(l.day)}/${two(l.month)} $hm';
}

/// Text of « Envoyer en message ».
String poiMessage(SarcadePoi p,CoordFormat format,{int mgrsDigits=4})=>
  S.t('poi.message',{'name':poiName(p),'pos':formatCoordinates(LatLng(p.lat,p.lon),format,mgrsDigits:mgrsDigits)});

/// Pin of a point: the default pin, or a round badge with its symbol.
Widget poiSymbol(SarcadePoi p,{double size=38}){
  final c=Color(poiColor(p));
  if(p.icon==null||p.icon=='pin')return Icon(Icons.location_on,size:size,color:c,shadows:const [Shadow(blurRadius:3,color:Colors.black54)]);
  return Container(width:size*0.8,height:size*0.8,decoration:BoxDecoration(color:c,shape:BoxShape.circle,border:Border.all(color:Colors.white,width:2),
    boxShadow:const [BoxShadow(blurRadius:3,color:Colors.black45)]),child:Icon(poiIconData(p.icon),size:size*0.46,color:Colors.white));
}

/// Pin of a point; [onDoubleTap] (lot 19) also keeps the map from zooming.
Marker poiMarker(SarcadePoi p,VoidCallback onTap,{VoidCallback? onDoubleTap})=>Marker(point:LatLng(p.lat,p.lon),width:44,height:44,
  child:Tooltip(message:poiName(p),child:GestureDetector(key:ValueKey('poi-${p.id}'),behavior:HitTestBehavior.opaque,onTap:onTap,onDoubleTap:onDoubleTap,
    child:Center(child:poiSymbol(p)))));

/// New point of the event, by [actor]: [color] chosen in its window, else
/// his drawing colour.
Map<String,dynamic> newPoiJson({required String id,required String eventId,required LatLng at,String? label,required String actor,required int drawColor,String? icon,int? color})=>{
  'id':id,'event_id':eventId,'kind':'designated','label':label,'lat':at.latitude,'lon':at.longitude,
  'created_at':DateTime.now().toUtc().toIso8601String(),'created_by':actor,'color':color??poiColorFor(drawColor),if(icon!=null&&icon!='pin')'icon':icon};

/// Applies a point from the server (realtime or change feed): a deleted one
/// leaves the map and the cache. Returns true when [pois] changed.
Future<bool> applyRemotePoi(Map<String,SarcadePoi> pois,LocalStore store,Map<String,dynamic> json,String eventId) async {
  if(json['event_id']!=eventId||json['id']==null)return false;
  if(json['deleted']==true){await store.deletePoi('${json['id']}');return pois.remove(json['id'])!=null;}
  final p=SarcadePoi.fromJson(json);
  await store.cachePoi(p.toJson());
  pois[p.id]=p;
  return true;
}

/// Change of a point (author or PCO), synchronised (`update`): only the
/// fields given change; [at] moves it (lot 25, the server writes the move
/// in the logbook).
Future<void> updatePoi(Map<String,SarcadePoi> pois,LocalStore store,OfflineSyncService sync,SarcadePoi p,String actor,
    {String? label,String? icon,int? color,LatLng? at}) async {
  final now=DateTime.now().toUtc().toIso8601String();
  final change=<String,dynamic>{'label':?label,'icon':?icon,'color':?color,if(at!=null)...{'lat':at.latitude,'lon':at.longitude}};
  final j=p.toJson()..addAll(change)..['updated_by']=actor;
  pois[p.id]=SarcadePoi.fromJson(j);
  await store.cachePoi(j);
  await sync.queue(objectId:p.id,objectType:'poi',action:'update',payload:{'id':p.id,'event_id':p.eventId,...change,'updated_by':actor,'updated_at':now});
}

/// Name, icon and colour from the window of the point.
Future<void> savePoiDraft(Map<String,SarcadePoi> pois,LocalStore store,OfflineSyncService sync,SarcadePoi p,PoiDraft d,String actor)=>
  updatePoi(pois,store,sync,p,actor,label:d.name,icon:d.icon,color:d.color);

Future<void> deletePoi(Map<String,SarcadePoi> pois,LocalStore store,OfflineSyncService sync,SarcadePoi p,String actor) async {
  pois.remove(p.id);
  await store.deletePoi(p.id);
  await sync.queue(objectId:p.id,objectType:'poi',action:'delete',payload:{'id':p.id,'event_id':p.eventId,'label':p.label,'updated_by':actor,
    'updated_at':DateTime.now().toUtc().toIso8601String()});
}

/// « Modifier » of the sheet and double click (lot 25): the window of
/// creation, titled « Modifier le point d'intérêt », already filled.
Future<PoiDraft?> editPoiDialog(BuildContext context,SarcadePoi p)=>showPoiDialog(context,edit:true,
  pinColor:poiColorFor(p.createdBy==null?poiFallbackColor:operatorColor(p.createdBy!)),name:p.label??'',icon:p.icon,color:poiColor(p));

/// Double click or double touch on a point (lot 19, window of lot 25): the
/// window « Modifier le point d'intérêt » for the PCO or the author of the
/// point, else the usual sheet.
Future<void> doubleTapPoi(BuildContext context,SarcadePoi p,{required String actor,required Future<void> Function(PoiDraft d) save,required VoidCallback openSheet}) async {
  if(!canEditPoi(p,actor)){openSheet();return;}
  final d=await editPoiDialog(context,p);
  if(d!=null)await save(d);
}

Future<bool> confirmPoiDelete(BuildContext context,SarcadePoi p) async =>await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
  title:Text(S.t('poi.deleteTitle')),content:Text(S.t('poi.deleteBody',{'name':poiName(p)})),
  actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
    FilledButton(style:FilledButton.styleFrom(backgroundColor:Theme.of(c).colorScheme.error),onPressed:()=>Navigator.pop(c,true),child:Text(S.t('common.delete')))]))==true;

/// The sheet of a point; returns the action chosen: edit, move, send,
/// route, delete. Lot 25: one « Modifier » (name, icon, colour),
/// « Déplacer », then « Supprimer » last, in red; a side panel on a wide
/// screen, a bottom sheet that scrolls on a phone (map_sheet.dart).
Future<String?> showPoiSheet(BuildContext context,SarcadePoi p,{required CoordFormat format,int mgrsDigits=4,required bool canEdit}){
  final pos=formatCoordinates(LatLng(p.lat,p.lon),format,mgrsDigits:mgrsDigits);
  return showMapSheet<String>(context,builder:(c){
    final red=Theme.of(c).colorScheme.error;
    return Column(key:const ValueKey('poi-sheet'),mainAxisSize:MainAxisSize.min,children:[
      ListTile(leading:SizedBox(width:40,child:Center(child:poiSymbol(p,size:34))),title:Text(poiName(p),style:Theme.of(c).textTheme.titleMedium),
        subtitle:Text([S.t('poi.by',{'who':p.createdBy??S.t('poi.unknownAuthor')}),poiIconLabel(p.icon),poiTime(p.createdAt)].join(' · '))),
      ListTile(dense:true,leading:const Icon(Icons.my_location),title:SelectableText(pos)),
      const Divider(height:1),
      if(canEdit)ListTile(key:const ValueKey('poi-edit'),leading:const Icon(Icons.edit_outlined),title:Text(S.t('poi.edit')),onTap:()=>Navigator.pop(c,'edit')),
      if(canEdit)ListTile(key:const ValueKey('poi-move'),leading:const Icon(Icons.open_with),title:Text(S.t('poi.move')),onTap:()=>Navigator.pop(c,'move')),
      ListTile(leading:const Icon(Icons.send_outlined),title:Text(S.t('measure.send')),onTap:()=>Navigator.pop(c,'send')),
      ListTile(leading:const Icon(Icons.add_road),title:Text(S.t('routes.toHere')),onTap:()=>Navigator.pop(c,'route')),
      if(canEdit)ListTile(key:const ValueKey('poi-delete'),leading:Icon(Icons.delete_outline,color:red),
        title:Text(S.t('common.delete'),style:TextStyle(color:red)),onTap:()=>Navigator.pop(c,'delete')),
    ]);
  });
}

/// Import of a file (lot 25, choice 3 of « un seul moyen de créer un
/// point »): the isolated points become points of interest instead of
/// drawn points; the other shapes stay drawings.
({List<ImportedShape> shapes,List<ImportedShape> points}) splitImportedPoints(List<ImportedShape> all)=>
  (shapes:[for(final s in all)if(s.kind!=FeatureKind.point)s],points:[for(final s in all)if(s.kind==FeatureKind.point)s]);

/// New points of interest from imported points: their name (else « Point
/// HH:MM »), their colour (else the author's), the pin.
List<Map<String,dynamic>> importedPoiJson(List<ImportedShape> points,{required String Function() newId,required String eventId,required String actor,required int drawColor})=>[
  for(final s in points)if(s.points.isNotEmpty)newPoiJson(id:newId(),eventId:eventId,at:s.points.first,label:s.label.trim().isEmpty?defaultPoiName():s.label.trim(),
    actor:actor,drawColor:drawColor,color:s.color)];

/// Stores and sends the points of [json]; returns them.
Future<List<SarcadePoi>> addPois(Map<String,SarcadePoi> pois,LocalStore store,OfflineSyncService sync,List<Map<String,dynamic>> json) async {
  final out=<SarcadePoi>[];
  for(final j in json){
    final p=SarcadePoi.fromJson(j);
    pois[p.id]=p;out.add(p);
    await store.cachePoi(j);
    await sync.queue(objectId:p.id,objectType:'poi',payload:j);
  }
  return out;
}
