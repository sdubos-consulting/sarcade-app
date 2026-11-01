/// Points of interest (decision of the project owner, 29 Oct 2026, option A):
/// sheet on touch (name, author, time, coordinates), rename, delete with
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
import '../../ui/operator_color.dart';
import '../map/rename_dialog.dart';
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

/// Colour of the pin: stored colour, else derived from the author.
int poiColor(SarcadePoi p){
  final c=p.color??(p.createdBy==null?poiFallbackColor:operatorColor(p.createdBy!));
  return poiColorFor(c);
}

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

/// New point of the event, by [actor] in his drawing colour.
Map<String,dynamic> newPoiJson({required String id,required String eventId,required LatLng at,String? label,required String actor,required int drawColor,String? icon})=>{
  'id':id,'event_id':eventId,'kind':'designated','label':label,'lat':at.latitude,'lon':at.longitude,
  'created_at':DateTime.now().toUtc().toIso8601String(),'created_by':actor,'color':poiColorFor(drawColor),if(icon!=null&&icon!='pin')'icon':icon};

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

Future<void> renamePoi(Map<String,SarcadePoi> pois,LocalStore store,OfflineSyncService sync,SarcadePoi p,String label,String actor) async {
  final now=DateTime.now().toUtc().toIso8601String();
  final j=p.toJson()..['label']=label..['updated_by']=actor;
  pois[p.id]=SarcadePoi.fromJson(j);
  await store.cachePoi(j);
  await sync.queue(objectId:p.id,objectType:'poi',action:'update',payload:{'id':p.id,'event_id':p.eventId,'label':label,'updated_by':actor,'updated_at':now});
}

/// New shape of the icon (author or PCO), kept by the server (`icon`).
Future<void> changePoiIcon(Map<String,SarcadePoi> pois,LocalStore store,OfflineSyncService sync,SarcadePoi p,String icon,String actor) async {
  final now=DateTime.now().toUtc().toIso8601String();
  final j=p.toJson()..['icon']=icon..['updated_by']=actor;
  pois[p.id]=SarcadePoi.fromJson(j);
  await store.cachePoi(j);
  await sync.queue(objectId:p.id,objectType:'poi',action:'update',payload:{'id':p.id,'event_id':p.eventId,'icon':icon,'updated_by':actor,'updated_at':now});
}

Future<void> deletePoi(Map<String,SarcadePoi> pois,LocalStore store,OfflineSyncService sync,SarcadePoi p,String actor) async {
  pois.remove(p.id);
  await store.deletePoi(p.id);
  await sync.queue(objectId:p.id,objectType:'poi',action:'delete',payload:{'id':p.id,'event_id':p.eventId,'label':p.label,'updated_by':actor,
    'updated_at':DateTime.now().toUtc().toIso8601String()});
}

/// « Modifier le nom »: the current name selected, Entrée saves, Échap
/// cancels (lot 19).
Future<String?> askPoiName(BuildContext context,SarcadePoi p)=>
  askNewName(context,title:S.t('poi.rename'),initial:p.label??'',label:S.t('poi.name'),fieldKey:const ValueKey('poi-name'));

/// Double click or double touch on a point (card « Point d'intérêt :
/// double-clic pour le renommer », lot 19, choices 1 and 2): the rename
/// window for the PCO or the author of the point, else the usual sheet.
Future<void> doubleTapPoi(BuildContext context,SarcadePoi p,{required String actor,required Future<void> Function(String name) rename,required VoidCallback openSheet}) async {
  if(!canEditPoi(p,actor)){openSheet();return;}
  final name=await askPoiName(context,p);
  if(name!=null)await rename(name);
}

Future<bool> confirmPoiDelete(BuildContext context,SarcadePoi p) async =>await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
  title:Text(S.t('poi.deleteTitle')),content:Text(S.t('poi.deleteBody',{'name':poiName(p)})),
  actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
    FilledButton(style:FilledButton.styleFrom(backgroundColor:Theme.of(c).colorScheme.error),onPressed:()=>Navigator.pop(c,true),child:Text(S.t('common.delete')))]))==true;

/// The sheet of a point; returns the action chosen: rename, icon, delete, send, route.
Future<String?> showPoiSheet(BuildContext context,SarcadePoi p,{required CoordFormat format,int mgrsDigits=4,required bool canEdit}){
  final pos=formatCoordinates(LatLng(p.lat,p.lon),format,mgrsDigits:mgrsDigits);
  return showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
    ListTile(leading:SizedBox(width:40,child:Center(child:poiSymbol(p,size:34))),title:Text(poiName(p),style:Theme.of(c).textTheme.titleMedium),
      subtitle:Text([S.t('poi.by',{'who':p.createdBy??S.t('poi.unknownAuthor')}),poiTime(p.createdAt)].join(' · '))),
    ListTile(dense:true,leading:const Icon(Icons.my_location),title:SelectableText(pos)),
    const Divider(height:1),
    if(canEdit)ListTile(leading:const Icon(Icons.edit_outlined),title:Text(S.t('poi.rename')),onTap:()=>Navigator.pop(c,'rename')),
    if(canEdit)ListTile(key:const ValueKey('poi-change-icon'),leading:Icon(poiIconData(p.icon)),title:Text(S.t('poi.changeIcon')),
      subtitle:Text(poiIconLabel(p.icon)),onTap:()=>Navigator.pop(c,'icon')),
    ListTile(leading:const Icon(Icons.send_outlined),title:Text(S.t('measure.send')),onTap:()=>Navigator.pop(c,'send')),
    ListTile(leading:const Icon(Icons.add_road),title:Text(S.t('routes.toHere')),onTap:()=>Navigator.pop(c,'route')),
    if(canEdit)ListTile(leading:Icon(Icons.delete_outline,color:Theme.of(c).colorScheme.error),title:Text(S.t('common.delete')),onTap:()=>Navigator.pop(c,'delete')),
  ])));
}
