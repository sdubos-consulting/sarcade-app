/// Move of a point of interest (lot 25, card « Point d'intérêt : le
/// déplacer facilement »): « Déplacer » in the sheet of the point (choice
/// 1); the point follows the finger or the mouse, a touch on the map puts
/// it there, banner « Glissez le point, puis Valider » with Valider and
/// Annuler (choice 2); the move is written in the logbook by the server and
/// undone by the « Annuler » arrow, Ctrl+Z or the message (choice 4); same
/// right as to modify, the author or the PCO (choice 5).
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../../models/poi.dart';
import '../../offline/local_store.dart';
import '../../offline/sync_service.dart';
import '../map/drawing/drawing_controller.dart';
import '../map/drawing/drawing_layers.dart' show HandleDragRecognizer;
import '../map/drawing/geometry.dart' show distanceM, formatDistance;
import 'poi_sheet.dart';

/// The point being moved and where it is now.
class PoiMove extends ChangeNotifier {
  SarcadePoi? _poi; LatLng? _at;
  SarcadePoi? get poi=>_poi;
  LatLng? get at=>_at;
  bool get active=>_poi!=null;
  LatLng? get from{final p=_poi;return p==null?null:LatLng(p.lat,p.lon);}
  /// Distance from the place of the point to where it is now.
  double get movedM{final f=from, a=_at;return f==null||a==null?0.0:distanceM(f,a);}

  void start(SarcadePoi p){_poi=p;_at=LatLng(p.lat,p.lon);notifyListeners();}
  void moveTo(LatLng p){if(_poi==null)return;_at=p;notifyListeners();}
  void cancel(){if(_poi==null)return;_poi=null;_at=null;notifyListeners();}
  /// Ends the mode; the point and its new place, null if nothing moved.
  ({SarcadePoi poi,LatLng to})? finish(){
    final p=_poi, a=_at;
    _poi=null;_at=null;notifyListeners();
    if(p==null||a==null||(a.latitude==p.lat&&a.longitude==p.lon))return null;
    return (poi:p,to:a);
  }
}

/// Layers of the map while a point moves: a line from its old place, and
/// the point at its new place, dragged with the finger or the mouse.
/// [toLatLng] converts a global position; [onHold] keeps the map still
/// while the point is held.
List<Widget> poiMoveLayers(PoiMove move,LatLng Function(Offset global) toLatLng,void Function(bool held) onHold){
  if(!move.active)return const [];
  Widget follow(Widget Function(SarcadePoi p,LatLng from,LatLng at) build)=>ListenableBuilder(listenable:move,builder:(_,_){
    final p=move.poi, at=move.at, from=move.from;
    return p==null||at==null||from==null?const SizedBox.shrink():build(p,from,at);
  });
  return [
    follow((p,from,at)=>PolylineLayer(polylines:[Polyline(points:[from,at],strokeWidth:2,color:Color(poiColor(p)).withValues(alpha:0.8),
      pattern:StrokePattern.dashed(segments:const [6,4]))])),
    follow((p,from,at)=>MarkerLayer(markers:[Marker(point:at,width:56,height:56,child:_MoveHandle(poi:p,move:move,toLatLng:toLatLng,onHold:onHold))])),
  ];
}

class _MoveHandle extends StatelessWidget {
  final SarcadePoi poi; final PoiMove move; final LatLng Function(Offset global) toLatLng; final void Function(bool held) onHold;
  const _MoveHandle({required this.poi,required this.move,required this.toLatLng,required this.onHold});
  @override Widget build(BuildContext context){
    final colour=Color(poiColor(poi));
    return MouseRegion(cursor:SystemMouseCursors.move,child:RawGestureDetector(
      key:const ValueKey('poi-move-handle'),behavior:HitTestBehavior.opaque,
      gestures:{HandleDragRecognizer:GestureRecognizerFactoryWithHandlers<HandleDragRecognizer>(()=>HandleDragRecognizer(debugOwner:this),(r){
        r..onStart=((_)=>onHold(true))
          ..onUpdate=((d)=>move.moveTo(toLatLng(d.globalPosition)))
          ..onEnd=((_)=>onHold(false))
          ..onCancel=(()=>onHold(false));
      })},
      child:Center(child:Container(width:52,height:52,alignment:Alignment.center,decoration:BoxDecoration(shape:BoxShape.circle,
        color:Colors.white.withValues(alpha:0.55),border:Border.all(color:colour,width:2)),child:poiSymbol(poi,size:38)))));
  }
}

/// « Glissez le point, puis Valider », the distance, Annuler and Valider.
class PoiMoveBanner extends StatelessWidget {
  final PoiMove move; final VoidCallback onValidate, onCancel;
  const PoiMoveBanner({super.key,required this.move,required this.onValidate,required this.onCancel});
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:move,builder:(context,_){
    final s=Theme.of(context).colorScheme; final d=move.movedM;
    return Material(key:const ValueKey('poi-move-banner'),elevation:4,borderRadius:BorderRadius.circular(14),color:s.surface,
      child:Padding(padding:const EdgeInsets.fromLTRB(14,4,6,4),child:Row(children:[
        Icon(Icons.open_with,color:s.primary),const SizedBox(width:10),
        Expanded(child:Text([S.t('poi.moveHint'),if(d>=1)formatDistance(d)].join(' · '),maxLines:2,overflow:TextOverflow.ellipsis,
          style:const TextStyle(fontWeight:FontWeight.w600))),
        TextButton(key:const ValueKey('poi-move-cancel'),onPressed:onCancel,child:Text(S.t('common.cancel'))),
        FilledButton(key:const ValueKey('poi-move-ok'),onPressed:onValidate,child:Text(S.t('poi.moveOk'))),
      ])));
  });
}

/// Sends the move, adds it to the history of [history] (« Annuler » arrow,
/// Ctrl+Z) and shows « Point déplacé de 120 m » with « Annuler ».
Future<void> commitPoiMove(BuildContext context,{required ({SarcadePoi poi,LatLng to}) move,required Map<String,SarcadePoi> pois,
    required LocalStore store,required OfflineSyncService sync,required String actor,required DrawingController history,required VoidCallback refresh}) async {
  final p=move.poi, from=LatLng(p.lat,p.lon), to=move.to;
  final messenger=ScaffoldMessenger.maybeOf(context);
  Future<void> place(LatLng at) async {final now=pois[p.id];if(now==null)return;await updatePoi(pois,store,sync,now,actor,at:at);refresh();}
  await place(to);
  final tag=Object();
  history.recordExternal(tag:tag,undo:()=>place(from),redo:()=>place(to));
  messenger?.showSnackBar(SnackBar(content:Text(S.t('poi.moved',{'d':formatDistance(distanceM(from,to))})),
    action:SnackBarAction(key:const ValueKey('poi-move-undo'),label:S.t('draw.undo'),onPressed:()=>history.undoTagged(tag))));
}
