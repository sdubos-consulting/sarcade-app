/// Points of interest in the selection of the map (lot 25, card
/// « Sélection : inclure les points d'intérêt (Maj+clic, rectangle) »):
/// Maj+clic and Ctrl+clic add or remove a point (choice 1), the selection
/// rectangle takes the points inside it (choice 2), the common action bar
/// applies to them: Supprimer, Exporter, Envoyer en message, Couleur,
/// Déplacer l'ensemble (choice 3); one's own points, all for the PCO
/// (choice 4); counter « 3 dessins · 2 points » (choice 5). A selected
/// point is also dragged directly on a computer (card « Point d'intérêt :
/// le déplacer facilement », choice 3).
library;

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../../models/poi.dart';
import '../../offline/local_store.dart';
import '../../offline/sync_service.dart';
import '../map/drawing/drawing_controller.dart';
import '../map/drawing/map_feature.dart';
import 'poi_sheet.dart';

/// Projection of a place on the screen.
typedef PoiProjector=Offset Function(LatLng);

/// Tolerance of a click on a point, in pixels (its pin is 44 px).
const poiHitPx=22.0;

/// Points whose place is inside the rectangle [r] (screen).
List<String> poisInRect(Iterable<SarcadePoi> pois,Rect r,PoiProjector project)=>
  [for(final p in pois)if(r.inflate(4).contains(project(LatLng(p.lat,p.lon))))p.id];

/// The nearest point within [poiHitPx] of [at] (screen), if any.
SarcadePoi? poiAtOffset(Iterable<SarcadePoi> pois,Offset at,PoiProjector project){
  SarcadePoi? best; var bestD=poiHitPx;
  for(final p in pois){
    final o=project(LatLng(p.lat,p.lon));
    final d=(o-at).distance;
    if(d<=bestD){best=p;bestD=d;}
  }
  return best;
}

/// A click on a point with Maj, Ctrl (Cmd) or in the « Sélection » mode
/// adds or removes it; true when the click was used so.
bool poiTapSelects(DrawingController c,SarcadePoi p,{HardwareKeyboard? keyboard}){
  final k=keyboard??HardwareKeyboard.instance;
  if(!c.selectMode&&!k.isShiftPressed&&!k.isControlPressed&&!k.isMetaPressed)return false;
  c.togglePoi(p.id);
  return true;
}

/// A point shown as a drawn point (export of the selection).
MapFeature poiAsFeature(SarcadePoi p)=>MapFeature(id:p.id,eventId:p.eventId,kind:FeatureKind.point,points:[LatLng(p.lat,p.lon)],
  color:poiColor(p),strokeWidth:4,label:poiName(p),createdBy:p.createdBy,updatedBy:p.updatedBy,updatedAt:p.createdAt.toUtc());

/// Text of « Envoyer en message »: one line per point, then per drawing.
String selectionMessageText(List<MapFeature> drawings,List<SarcadePoi> pois,String Function(LatLng) format)=>[
  for(final p in pois)S.t('poi.message',{'name':poiName(p),'pos':format(LatLng(p.lat,p.lon))}),
  for(final f in drawings)S.t('poi.drawingLine',{'kind':f.kind.label,'name':f.label.isEmpty?'':' « ${f.label} »','pos':format(f.anchor)}),
].join('\n');

/// What the drawing selection needs from the points of the page: [pois]
/// is the map of the page, [refresh] redraws it.
PoiSelectionHooks poiSelectionHooks({required Map<String,SarcadePoi> pois,required LocalStore store,required OfflineSyncService sync,
    required String actor,required String Function(LatLng) format,required void Function() refresh}){
  // Every point changes at once in [pois] (the start of each change is
  // synchronous), then the page redraws.
  Future<void> each(Iterable<String> ids,Future<void> Function(SarcadePoi p) run) async {
    await Future.wait([for(final id in ids.toList())if(pois[id]!=null)run(pois[id]!)]);
    refresh();
  }
  return PoiSelectionHooks(
    positionOf:(id){final p=pois[id];return p==null?null:LatLng(p.lat,p.lon);},
    canSelect:(id){final p=pois[id];return p!=null&&canEditPoi(p,actor);},
    onMoved:(to)=>each(to.keys,(p)=>updatePoi(pois,store,sync,p,actor,at:to[p.id])),
    onDelete:(ids)=>each(ids,(p)=>deletePoi(pois,store,sync,p,actor)),
    onColor:(ids,c)=>each(ids,(p)=>updatePoi(pois,store,sync,p,actor,color:c)),
    asFeature:(id){final p=pois[id];return p==null?null:poiAsFeature(p);},
    message:(drawings,ids)=>selectionMessageText(drawings,[for(final id in ids)?pois[id]],format),
  );
}
