/// Double click or double touch on a drawn object (card « Point d'intérêt :
/// double-clic pour le renommer », lot 19, choice 4): the window to change
/// its name, and the map does not zoom. A simple click still selects.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../l10n/strings.dart';
import '../rename_dialog.dart';
import 'drawing_controller.dart';
import 'hit_test.dart';
import 'map_feature.dart';

/// Title of the window: the text of a Texte object, else its name.
String renameTitle(MapFeature f)=>f.kind==FeatureKind.text?S.t('draw.editText'):S.t('draw.rename');

/// Selects [f] and asks its new name. Same right as « Nom de l'objet » in
/// the selection bar: any drawn object of the event. Synchronised like
/// every change of a label ([DrawingController.setLabel], one undo step).
Future<void> renameDrawing(BuildContext context,DrawingController c,MapFeature f) async {
  c.select(f.id);
  final name=await askNewName(context,title:renameTitle(f),initial:f.label,label:S.t('map.objectName'),
    fieldKey:const ValueKey('draw-name'),maxLength:80);
  if(name==null||c.selected?.id!=f.id)return;
  c.setLabel(name);
}

/// Layer of the map, just above the drawn objects, that joins the pointers
/// falling on one of them ([hitTest] of the map page, same tolerance) and
/// only listens to double taps: everything else (tap, drag, pinch, long
/// press, right click) still reaches the map. A double tap on an object is
/// won by this layer, so the map does not zoom; elsewhere it still does. Off while drawing, picking
/// or selecting several objects ([enabled]).
class DrawingDoubleTapLayer extends StatefulWidget {
  final DrawingController controller; final bool enabled;
  final double Function(MapFeature)? radiusPx;
  final void Function(MapFeature f) onDoubleTap;
  const DrawingDoubleTapLayer({super.key,required this.controller,required this.onDoubleTap,this.enabled=true,this.radiusPx});
  @override State<DrawingDoubleTapLayer> createState()=>_DrawingDoubleTapLayerState();
}

class _DrawingDoubleTapLayerState extends State<DrawingDoubleTapLayer> {
  Offset? _at;

  MapFeature? _hit(MapCamera cam,Offset local)=>hitTest(widget.controller.features,local,cam.latLngToScreenOffset,radiusPx:widget.radiusPx);

  @override Widget build(BuildContext context){
    if(!widget.enabled)return const SizedBox.shrink();
    final cam=MapCamera.of(context);
    return ObjectsHitArea(hits:(local)=>_hit(cam,local)!=null,child:GestureDetector(
      key:const ValueKey('draw-double-tap'),behavior:HitTestBehavior.opaque,
      onDoubleTapDown:(d)=>_at=d.localPosition,
      onDoubleTap:(){final at=_at;_at=null;if(at==null)return;final f=_hit(cam,at);if(f!=null)widget.onDoubleTap(f);},
      child:const SizedBox.expand(),
    ));
  }
}

/// Joins the pointers falling where [hits] is true, without stopping
/// them: the layers below (reference sites, chips of the Texte objects) and
/// the map still receive them; elsewhere it is not there at all.
class ObjectsHitArea extends SingleChildRenderObjectWidget {
  final bool Function(Offset local) hits;
  const ObjectsHitArea({super.key,required this.hits,super.child});
  @override RenderObjectsHitArea createRenderObject(BuildContext context)=>RenderObjectsHitArea(hits);
  @override void updateRenderObject(BuildContext context,RenderObjectsHitArea renderObject){renderObject.hits=hits;}
}

class RenderObjectsHitArea extends RenderProxyBox {
  RenderObjectsHitArea(this.hits);
  bool Function(Offset local) hits;
  @override bool hitTest(BoxHitTestResult result,{required Offset position}){
    if(size.contains(position)&&hits(position))super.hitTest(result,position:position);
    return false;
  }
}
