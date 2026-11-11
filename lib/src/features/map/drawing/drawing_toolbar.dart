import 'dart:math' as math;

import '../../../l10n/strings.dart';

import 'package:flutter/material.dart';

import 'drawing_controller.dart';
import 'geometry.dart';
import 'map_feature.dart';
import 'multi_select.dart';
import '../../../ui/color_palette.dart';
import '../../../ui/test_ids.dart';

IconData toolIcon(FeatureKind k)=>switch(k){
  FeatureKind.point=>Icons.place_outlined,
  FeatureKind.line=>Icons.timeline,
  FeatureKind.arrow=>Icons.north_east,
  FeatureKind.circle=>Icons.circle_outlined,
  FeatureKind.rectangle=>Icons.crop_square,
  FeatureKind.zone=>Icons.pentagon_outlined,
  FeatureKind.text=>Icons.text_fields,
  FeatureKind.freehand=>Icons.gesture,
  FeatureKind.measure=>Icons.straighten,
};

String toolHint(FeatureKind k)=>switch(k){
  FeatureKind.point=>S.t('draw.hint.point'),
  FeatureKind.text=>S.t('draw.hint.text'),
  FeatureKind.circle=>S.t('draw.hint.circle'),
  FeatureKind.rectangle=>S.t('draw.hint.rectangle'),
  FeatureKind.freehand=>S.t('draw.hint.freehand'),
  FeatureKind.zone=>S.t('draw.hint.zone'),
  FeatureKind.arrow=>S.t('draw.hint.arrow'),
  _=>S.t('draw.hint.line'),
};

/// Tools of the drawing toolbar: no « Mesure » (card « Barre de dessin,
/// retirer Mesure », 30 Oct 2026, 13 h 28: « Mesurer jusqu'ici » of the
/// point menu does it; the measures already saved stay editable). No
/// « Point » either (lot 25, card « un seul moyen de créer un point »): a
/// point is created by a long press, « Point d'intérêt »; the points
/// already drawn stay shown, selectable and deletable.
final drawingToolbarKinds=[for(final k in FeatureKind.values)if(k!=FeatureKind.measure&&k!=FeatureKind.point)k];

/// Same width for every tool button, fitted to the longest label on one line
/// (card « Barre de dessin iPhone, libellé Rectangle coupé », 13 h 21).
double toolButtonWidth(BuildContext context,Iterable<String> labels){
  final scaler=MediaQuery.textScalerOf(context);
  var w=0.0;
  for(final l in labels){
    final tp=TextPainter(text:TextSpan(text:l,style:const TextStyle(fontSize:11,fontWeight:FontWeight.bold)),textDirection:TextDirection.ltr,maxLines:1,textScaler:scaler)..layout();
    if(tp.width>w)w=tp.width;
  }
  return (w+12).clamp(54.0,84.0).ceilToDouble();
}

/// Compact drawing toolbar: drawing tools only, undo/redo (no close any
/// more, lot 29.2) (import and export moved to Plus › Fichiers, card of 13 h 27).
class DrawingToolbar extends StatelessWidget {
  final DrawingController controller;
  /// Touching the chosen tool again closes the palette (lot 29.2).
  final VoidCallback onClose;
  /// Times the help of a tool was already shown (full help the first 3).
  final int Function(FeatureKind)? hintSeen;
  final void Function(FeatureKind)? onHintShown;
  const DrawingToolbar({super.key,required this.controller,required this.onClose,this.hintSeen,this.onHintShown});

  @override
  Widget build(BuildContext context)=>LayoutBuilder(builder:(context,box)=>_build(context,box.maxWidth));

  Widget _build(BuildContext context,double room){
    final c=controller;
    final scheme=Theme.of(context).colorScheme;
    // Five columns that fit the screen (iPhone in portrait: labels scaled
    // down) and the room actually given to the bar (inner padding 8).
    var fit=(MediaQuery.sizeOf(context).width-24-8)/5-4;
    if(room.isFinite)fit=math.min(fit,((room-8)/5-4).floorToDouble());
    final width=toolButtonWidth(context,[for(final k in drawingToolbarKinds)k.label,S.t('draw.undo'),S.t('draw.redo')]).clamp(44.0,fit<44?44.0:fit).toDouble();
    final tools=<Widget>[
      for(final k in drawingPaletteOrder)Padding(
        padding:const EdgeInsets.symmetric(horizontal:2),
        // Stable identifier for the CI journeys (card L1, lot 17).
        child:withId('map.draw-${k.name}',_ToolButton(key:ValueKey('draw-tool-${k.name}'),kind:k,active:c.tool==k,width:width,onTap:(){if(c.tool==k){onClose();}else{c.selectTool(k);}})),
      ),
    ];
    // Two rows everywhere, five columns (card « palette d'outils
    // incohérente », lot 29.2): Ligne, Flèche, Cercle, Rectangle, Zone /
    // Libre, Texte, (vide), Annuler, Rétablir. No « Fermer »: a touch on the
    // map without a tool, the pencil again or Échap closes the palette.
    final undo=_ActionCell(key:const ValueKey('draw-undo'),icon:Icons.undo,label:S.t('draw.undo'),width:width,onTap:c.canUndo?c.undo:null);
    final redo=_ActionCell(key:const ValueKey('draw-redo'),icon:Icons.redo,label:S.t('draw.redo'),width:width,onTap:c.canRedo?c.redo:null);
    final rows=drawingPaletteRows(tools,undo,redo,SizedBox(width:width+4));
    // Help of the active tool: one thin line at the bottom of the bar, no
    // separate bubble nor ✕ (card « Dessin : bandeau d'aide trop
    // encombrant », 1 Nov 2026).
    final line=c.tool==null?null:DraftLine(key:ValueKey('draft-line-${c.tool!.name}'),controller:c,
      seen:hintSeen?.call(c.tool!)??0,onShown:onHintShown);
    return Material(elevation:4,borderRadius:BorderRadius.circular(14),color:scheme.surface,
      child:Padding(padding:const EdgeInsets.all(4),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        for(final r in rows)Padding(padding:const EdgeInsets.symmetric(vertical:2),child:Row(mainAxisSize:MainAxisSize.min,children:r)),
        ?line,
      ])));
  }
}

/// Order of the palette: five tools on the first row, then Libre, Texte,
/// an empty cell, Annuler and Rétablir.
const drawingPaletteOrder=[FeatureKind.line,FeatureKind.arrow,FeatureKind.circle,FeatureKind.rectangle,FeatureKind.zone,FeatureKind.freehand,FeatureKind.text];

/// The two rows of five cells.
List<List<Widget>> drawingPaletteRows(List<Widget> tools,Widget undo,Widget redo,Widget empty){
  final cells=[...tools,empty,Padding(padding:const EdgeInsets.symmetric(horizontal:2),child:undo),Padding(padding:const EdgeInsets.symmetric(horizontal:2),child:redo)];
  return [cells.sublist(0,5),cells.sublist(5)];
}

/// Annuler / Rétablir with icon and label like the tools, greyed when
/// unavailable.
class _ActionCell extends StatelessWidget {
  final IconData icon; final String label; final double width; final VoidCallback? onTap;
  const _ActionCell({super.key,required this.icon,required this.label,required this.width,this.onTap});
  @override Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme; final on=onTap!=null;
    final fg=on?scheme.onSurface:scheme.onSurface.withValues(alpha:0.38);
    return Tooltip(message:label,child:InkWell(borderRadius:BorderRadius.circular(10),onTap:onTap,child:Container(width:width,padding:const EdgeInsets.symmetric(vertical:4),
      child:Column(mainAxisSize:MainAxisSize.min,children:[
        Icon(icon,color:fg),const SizedBox(height:2),
        SizedBox(height:15,child:FittedBox(fit:BoxFit.scaleDown,child:Text(label,maxLines:1,softWrap:false,style:TextStyle(fontSize:11,color:fg)))),
      ]))));
  }
}

/// Phone width: the drawing toolbar wraps on two rows.
bool drawingToolbarWraps(double screenWidth)=>screenWidth<600;

/// Icon and label of a tool button: label on one line, never cut (scaled
/// down if needed), icons on the same line for every button.
Widget _toolFace(IconData icon,String label,bool active,ColorScheme scheme)=>Column(mainAxisSize:MainAxisSize.min,children:[
  Icon(icon,color:active?scheme.onPrimaryContainer:scheme.onSurface),
  const SizedBox(height:2),
  SizedBox(height:15,child:FittedBox(fit:BoxFit.scaleDown,child:Text(label,maxLines:1,softWrap:false,
    style:TextStyle(fontSize:11,fontWeight:active?FontWeight.bold:FontWeight.normal,color:active?scheme.onPrimaryContainer:scheme.onSurfaceVariant)))),
]);

class _ToolButton extends StatelessWidget {
  final FeatureKind kind; final bool active; final double width; final VoidCallback onTap;
  const _ToolButton({super.key,required this.kind,required this.active,required this.width,required this.onTap});
  @override Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    return Tooltip(message:kind.label,child:InkWell(
      // The tooltip goes away with the click (revue n° 23).
      borderRadius:BorderRadius.circular(10),onTap:(){Tooltip.dismissAllToolTips();onTap();},
      child:Container(
        width:width,padding:const EdgeInsets.symmetric(vertical:4),
        decoration:BoxDecoration(color:active?scheme.primaryContainer:null,borderRadius:BorderRadius.circular(10)),
        child:_toolFace(toolIcon(kind),kind.label,active,scheme),
      ),
    ));
  }
}

/// Tools whose gesture needs no help (a single touch).
const hintlessTools={FeatureKind.point,FeatureKind.text};

/// How many times a tool's help is shown in full before folding into ⓘ.
const fullHintTimes=3;

/// Thin line of the drawing bar while a tool is active: count of points and
/// live measure, ⌫ and ✓ for lines and zones; the help in full the first 3
/// times of each tool, then behind ⓘ; none for Point and Texte.
class DraftLine extends StatefulWidget {
  final DrawingController controller; final int seen; final void Function(FeatureKind)? onShown;
  const DraftLine({super.key,required this.controller,this.seen=0,this.onShown});
  @override State<DraftLine> createState()=>_DraftLineState();
}

class _DraftLineState extends State<DraftLine> {
  bool _open=false;
  @override void initState(){
    super.initState();
    final t=widget.controller.tool;
    if(t!=null&&!hintlessTools.contains(t))WidgetsBinding.instance.addPostFrameCallback((_)=>widget.onShown?.call(t));
  }
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:widget.controller,builder:(context,_){
    final c=widget.controller, t=c.tool;
    if(t==null)return const SizedBox.shrink();
    final scheme=Theme.of(context).colorScheme;
    final count=c.draft.length, measure=c.draftMeasure;
    final full=widget.seen<fullHintTimes||_open;
    final hint=hintlessTools.contains(t)?null:toolHint(t);
    final text=[if(t.isMultiVertex&&count>0)S.t('draw.points',{'n':count}) else if(hint!=null&&full)hint,?measure].join(' · ');
    final style=TextStyle(fontSize:12,color:scheme.onSurfaceVariant);
    if(text.isEmpty&&hint==null&&!t.isMultiVertex)return const SizedBox.shrink();
    return Padding(padding:const EdgeInsets.fromLTRB(12,0,4,2),child:Row(mainAxisSize:MainAxisSize.min,children:[
      Flexible(child:Text(text,key:const ValueKey('draft-line'),maxLines:1,overflow:TextOverflow.ellipsis,style:style)),
      if(hint!=null&&!full&&!(t.isMultiVertex&&count>0))IconButton(key:const ValueKey('draft-help'),visualDensity:VisualDensity.compact,
        tooltip:hint,onPressed:()=>setState(()=>_open=true),icon:Icon(Icons.info_outline,size:18,color:scheme.onSurfaceVariant)),
      if(t.isMultiVertex&&count>0)IconButton(visualDensity:VisualDensity.compact,tooltip:S.t('draw.removeLast'),onPressed:c.undoLastVertex,icon:const Icon(Icons.backspace_outlined,size:18)),
      if(t.isMultiVertex)IconButton(visualDensity:VisualDensity.compact,tooltip:S.t('closures.finish'),onPressed:c.canFinish?c.finish:null,
        icon:Icon(Icons.check_circle,size:22,color:c.canFinish?scheme.primary:null)),
    ]));
  });
}

/// Status line while a tool is active: hint, live measure, and the actions
/// to remove the last vertex, finish or cancel.
class DraftBar extends StatelessWidget {
  final DrawingController controller;
  const DraftBar({super.key,required this.controller});
  @override Widget build(BuildContext context){
    final c=controller, t=c.tool;
    if(t==null)return const SizedBox.shrink();
    final measure=c.draftMeasure;
    final count=c.draft.length;
    return Material(
      elevation:3,borderRadius:BorderRadius.circular(12),color:Theme.of(context).colorScheme.inverseSurface,
      child:Padding(
        padding:const EdgeInsets.fromLTRB(14,4,4,4),
        child:Row(mainAxisSize:MainAxisSize.min,children:[
          Icon(toolIcon(t),size:18,color:Theme.of(context).colorScheme.onInverseSurface),
          const SizedBox(width:8),
          Flexible(child:Text(
            [t.isMultiVertex&&count>0?S.t('draw.points',{'n':count}):toolHint(t),?measure].join(' · '),
            maxLines:2,overflow:TextOverflow.ellipsis,
            style:TextStyle(color:Theme.of(context).colorScheme.onInverseSurface),
          )),
          if(t.isMultiVertex&&count>0)IconButton(tooltip:S.t('draw.removeLast'),onPressed:c.undoLastVertex,icon:const Icon(Icons.backspace_outlined),color:Theme.of(context).colorScheme.onInverseSurface),
          if(t.isMultiVertex)IconButton(tooltip:S.t('closures.finish'),onPressed:c.canFinish?c.finish:null,icon:const Icon(Icons.check_circle),color:Colors.white,disabledColor:Colors.white60),
          IconButton(tooltip:S.t('draw.cancel'),onPressed:()=>c.selectTool(null),icon:const Icon(Icons.close),color:Theme.of(context).colorScheme.onInverseSurface),
        ]),
      ),
    );
  }
}

/// PowerPoint-style mini toolbar for the selected object.
class SelectionBar extends StatelessWidget {
  final DrawingController controller;
  final Future<void> Function() onEditLabel;
  /// PCO: a closed shape can become a géorepérage.
  final bool canFence;
  const SelectionBar({super.key,required this.controller,required this.onEditLabel,this.canFence=false});

  String? _info(MapFeature f){
    if(f.kind==FeatureKind.circle)return '${S.t('draw.radius')} ${formatDistance(f.radiusM??0)} · ${formatArea(f.areaM2)}';
    if(f.isClosed)return formatArea(f.areaM2);
    if(f.kind.isLinear)return formatDistance(f.lengthM);
    return null;
  }

  @override Widget build(BuildContext context){
    final c=controller, f=c.selected;
    if(f==null)return const SizedBox.shrink();
    final info=_info(f);
    return Material(
      elevation:4,borderRadius:BorderRadius.circular(14),color:Theme.of(context).colorScheme.surface,
      child:Padding(
        padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
        child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Padding(padding:const EdgeInsets.fromLTRB(8,6,8,0),child:Text(
            [f.kind.label,if(f.label.isNotEmpty&&f.kind!=FeatureKind.text)f.label,?info,if(f.geofence)S.t('draw.geofence')].join(' · '),
            maxLines:1,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.labelLarge,
          )),
          SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(mainAxisSize:MainAxisSize.min,children:[
            ColorPaletteButton(color:f.color,colors:paletteWith(f.color),onSelected:c.setColor),
            if(f.kind!=FeatureKind.point&&f.kind!=FeatureKind.text)PopupMenuButton<double>(
              tooltip:S.t('draw.width'),onSelected:c.setStrokeWidth,
              itemBuilder:(_)=>[for(final w in drawingWidths)PopupMenuItem(value:w,child:Row(children:[SizedBox(width:48,child:Divider(thickness:w,color:Colors.black87)),const SizedBox(width:10),Text(w==drawingWidths.first?'Fin':w==drawingWidths.last?'Épais':'Moyen')]))],
              child:const Padding(padding:EdgeInsets.all(10),child:Icon(Icons.line_weight)),
            ),
            PopupMenuButton<double>(
              tooltip:S.t('draw.opacity'),onSelected:c.setOpacity,
              itemBuilder:(_)=>[for(final o in drawingOpacities)CheckedPopupMenuItem(value:o,checked:(f.opacity-o).abs()<0.01,child:Text('${(o*100).round()} %'))],
              child:Padding(padding:const EdgeInsets.all(10),child:Icon(Icons.opacity,color:Color(f.color).withValues(alpha:f.opacity))),
            ),
            if(f.kind==FeatureKind.text)fontSizeButton(c,f),
            IconButton(tooltip:f.kind==FeatureKind.text?S.t('draw.editText'):S.t('groups.name'),onPressed:onEditLabel,icon:const Icon(Icons.edit_outlined)),
            // Géorepérage (PCO): alert when a team enters or leaves the zone.
            if(f.isClosed&&canFence)IconButton(tooltip:S.t(f.geofence?'draw.geofenceOff':'draw.geofenceOn'),onPressed:c.toggleGeofence,
              isSelected:f.geofence,icon:Icon(f.geofence?Icons.notifications_active:Icons.notifications_none_outlined)),
            IconButton(tooltip:S.t('draw.duplicate'),onPressed:c.duplicateSelected,icon:const Icon(Icons.copy_all_outlined)),
            IconButton(tooltip:S.t('routes.delete'),onPressed:c.deleteSelected,icon:const Icon(Icons.delete_outline),color:Colors.red.shade700),
            IconButton(tooltip:S.t('draw.deselect'),onPressed:c.endSelection,icon:const Icon(Icons.close)),
          ])),
        ]),
      ),
    );
  }
}

/// Selection mode with nothing selected yet: what to do, and ✕.
class SelectionHint extends StatelessWidget {
  final DrawingController controller;
  const SelectionHint({super.key,required this.controller});
  @override Widget build(BuildContext context)=>Material(key:const ValueKey('selection-hint'),elevation:4,borderRadius:BorderRadius.circular(14),
    color:Theme.of(context).colorScheme.surface,child:Padding(padding:const EdgeInsets.fromLTRB(14,4,4,4),child:Row(mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.highlight_alt),const SizedBox(width:8),
      Flexible(child:Text(S.t('draw.selectHint'))),
      IconButton(tooltip:S.t('common.cancel'),onPressed:controller.endSelection,icon:const Icon(Icons.close)),
    ])));
}
