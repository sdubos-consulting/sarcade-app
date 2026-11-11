/// Labels of the drawn objects that overlap each other or the operators
/// (card « Carte : étiquettes des objets dessinés qui se chevauchent », lot
/// 20, 2 Nov 2026). Choices applied:
/// 1. priority: operators first, then the drawn objects;
/// 2. a label that would overlap a label of higher priority is hidden (the
///    object stays on the map, its label comes back when zooming in);
/// 3. the label of a selected object is always shown;
/// 4. light computation: boxes in screen pixels, computed again when the
///    map moves, no new dependency.
library;

import 'dart:ui' show Offset, Rect;

/// A label to place: its box on the screen, and [forced] for the label of a
/// selected object (always shown).
class LabelCandidate {
  final Rect box;
  final bool forced;
  const LabelCandidate(this.box,{this.forced=false});
}

/// Indexes of the [labels] shown. [blockers] (operators, texts of the
/// map) are always shown and come first. The forced labels come next, even
/// over a blocker; then the others in the order of [labels] (the first one
/// wins): a label overlapping a box already shown is hidden.
Set<int> visibleLabels(List<LabelCandidate> labels,{Iterable<Rect> blockers=const []}){
  final taken=<Rect>[...blockers];
  final shown=<int>{};
  bool free(Rect r){for(final t in taken){if(t.overlaps(r))return false;}return true;}
  for(var i=0;i<labels.length;i++){
    if(!labels[i].forced)continue;
    shown.add(i); taken.add(labels[i].box);
  }
  for(var i=0;i<labels.length;i++){
    final l=labels[i];
    if(l.forced||!free(l.box))continue;
    shown.add(i); taken.add(l.box);
  }
  return shown;
}

/// Marker of a drawn label (drawing_layers.dart): 180 × 30 px, the chip
/// centred inside.
const labelMarkerWidth=180.0, labelMarkerHeight=30.0;

/// Width of the chip of a label (12 px, semi-bold, 6 px of padding each
/// side): about 7 px per character, at most the marker.
double labelChipWidth(String text)=>(text.length*7.0+14).clamp(20.0,labelMarkerWidth);
const labelChipHeight=20.0;

/// Screen box of a drawn label at [at]: centred on the point, or under it
/// for a point of the map ([below]).
Rect labelBox(Offset at,String text,{bool below=false})=>Rect.fromCenter(
  center:below?at.translate(0,labelMarkerHeight/2):at,width:labelChipWidth(text),height:labelChipHeight);

/// Screen box of a Texte object (centred chip, up to 2 lines) in a marker of
/// [markerWidth] × [markerHeight].
Rect textObjectBox(Offset at,String text,double fontSize,{required double markerWidth,required double markerHeight})=>Rect.fromCenter(
  center:at,width:(text.length*fontSize*0.62+20).clamp(0.0,markerWidth),height:(fontSize*1.4+10).clamp(0.0,markerHeight));

/// Station marker of an operator (operational_map_page.dart): 170 × 64 px
/// above its position, icon over a one-line label « name  age ».
const operatorMarkerWidth=170.0, operatorMarkerHeight=64.0, operatorIconPx=34.0;

/// Screen box of an operator at [at] with its [label]; the age added after
/// the name (« 12 min ») is counted as 8 characters of 11 px.
Rect operatorBox(Offset at,String label)=>Rect.fromLTWH(
  at.dx-_operatorWidth(label)/2,at.dy-operatorMarkerHeight,_operatorWidth(label),operatorMarkerHeight);

double _operatorWidth(String label)=>((label.length+8)*6.5+14).clamp(operatorIconPx,operatorMarkerWidth);
