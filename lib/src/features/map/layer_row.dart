/// One line of the « Affichage » tab (card « Panneau des couches, opacité
/// incohérente », validated on 30 Oct 2026, 1 h 20): name, then the
/// opacity of this layer only while it is shown, then the switch; same
/// layout for every layer. A filter (« Sans Internet seulement ») has no
/// slider.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

/// Opacity keys, one per layer; the first value of a new key is taken from
/// the former group (PR #92: ops, draw, brg, ref).
const layerOpacityLegacy={'ops':'ops','aprs':'ops','poi':'ops','draw':'draw','brg':'brg','high':'ref','relay':'ref'};

/// Opacity of [key] from the stored preferences (`opacity:<key>`), 10 to 100 %.
double layerOpacityFrom(String? Function(String key) read,String key){
  final v=read('opacity:$key')??read('opacity:${layerOpacityLegacy[key]??key}');
  return double.tryParse(v??'')?.clamp(0.1,1.0)??1.0;
}

/// Row of the layer whose transparency is open (one at a time, lot 29.2).
final layerOpen=ValueNotifier<String?>(null);

/// Compact row (card « panneau Affichage plus compact », lot 29.2): icon,
/// name, switch. Touching the name opens the transparency slider (and the
/// [detail] of the layer) under it, one row at a time. Names never cut.
class LayerRow extends StatelessWidget {
  final String label; final bool on; final ValueChanged<bool> onShown;
  final double? opacity; final ValueChanged<double>? onOpacity;
  /// Optional action after the name (« Liste › » of the points).
  final Widget? trailing;
  final IconData? icon;
  /// Shown under the slider when the row is open (APRS: radio only).
  final Widget? detail;
  const LayerRow({super.key,required this.label,required this.on,required this.onShown,this.opacity,this.onOpacity,this.trailing,this.icon,this.detail});
  @override Widget build(BuildContext context)=>ValueListenableBuilder<String?>(valueListenable:layerOpen,builder:(context,open,_){
    final t=Theme.of(context); final o=opacity;
    final slider=on&&o!=null&&onOpacity!=null;
    final opens=slider||detail!=null;
    final isOpen=opens&&open==label;
    // Narrow (revue d'ergonomie n° 28): the action goes on a second line
    // under the name, so the name is never squeezed out.
    final narrow=trailing!=null&&layerRowStacksAction(MediaQuery.sizeOf(context).width);
    final name=Text(label,softWrap:true,style:t.textTheme.bodyLarge);
    final main=Padding(padding:const EdgeInsets.only(left:16,right:8),child:ConstrainedBox(constraints:const BoxConstraints(minHeight:48),child:Row(children:[
      if(icon!=null)...[Icon(icon,size:20,color:on?t.colorScheme.primary:t.colorScheme.onSurfaceVariant),const SizedBox(width:12)],
      Expanded(child:opens?InkWell(key:ValueKey('layer-name-$label'),onTap:()=>layerOpen.value=isOpen?null:label,
        child:Padding(padding:const EdgeInsets.symmetric(vertical:12),child:name)):name),
      if(!narrow)?trailing,
      Switch(value:on,onChanged:onShown),
    ])));
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,mainAxisSize:MainAxisSize.min,children:[
      main,
      if(narrow)Padding(padding:EdgeInsets.only(left:icon!=null?48:16,bottom:4),child:Align(alignment:Alignment.centerLeft,child:trailing)),
      if(isOpen&&slider)Padding(padding:EdgeInsets.only(left:icon!=null?40:8,right:16),child:Row(children:[
        Tooltip(message:S.t('layers.opacity'),child:Icon(Icons.opacity,size:16,color:t.colorScheme.onSurfaceVariant)),
        Expanded(child:Slider(key:ValueKey('layer-slider-$label'),value:o,min:0.1,max:1,divisions:9,label:'${(o*100).round()} %',onChanged:onOpacity)),
        SizedBox(width:44,child:Text('${(o*100).round()} %',textAlign:TextAlign.end,style:t.textTheme.bodySmall)),
      ])),
      if(isOpen&&detail!=null)Padding(padding:EdgeInsets.only(left:icon!=null?32:0),child:detail!),
    ]);
  });
}

/// « 6 h › », « 4 terminés › », « Liste › »: a short link after a name.
Widget layerLink(String text,VoidCallback onTap,{Key? key})=>TextButton(key:key,onPressed:onTap,
  style:TextButton.styleFrom(visualDensity:VisualDensity.compact,padding:const EdgeInsets.symmetric(horizontal:8)),
  child:Text('$text ›'));

/// Hint at the bottom of the panel.
Widget layerOpacityHint(BuildContext c)=>Padding(padding:const EdgeInsets.fromLTRB(16,8,16,0),
  child:Text(S.t('layers.opacityHint'),style:Theme.of(c).textTheme.bodySmall?.copyWith(color:Theme.of(c).colorScheme.onSurfaceVariant)));

/// Phone width: the action of a layer row goes under its name.
bool layerRowStacksAction(double screenWidth)=>screenWidth<600;

/// Title of a section, same style as the tab titles (card « Panneau Fond de
/// carte, titres de sections », 1 h 34), with a clear separator above.
Widget layerSectionTitle(BuildContext c,String text,{bool first=false})=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
  if(!first)const Divider(height:16),
  Padding(padding:EdgeInsets.fromLTRB(16,first?8:0,16,0),child:Text(text,style:Theme.of(c).textTheme.titleSmall?.copyWith(color:Theme.of(c).colorScheme.primary))),
]);
