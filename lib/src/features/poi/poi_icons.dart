/// Shape of the icon of a point of interest (card « Points d'intérêt,
/// création claire et icônes », validated on 30 Oct 2026, 1 h 13): a
/// simple set of symbols, chosen when the point is created and changed in
/// its sheet; stored on the point (`icon`, server migration 0024). The
/// SDIS / NATO (APP-6) / SATER symbols come later. Lot 25: one window for
/// creation and modification, with the colour.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../ui/color_palette.dart';
import '../../ui/text_fields_dialog.dart';

/// Keys stored on the server, in the order of the panel; `pin` = default.
const poiIcons=['pin','gathering','command_post','danger','parking','water','helipad','vehicle','viewpoint','medical','radio','shelter','flag'];

IconData poiIconData(String? key)=>switch(key){
  'gathering'=>Icons.groups,'command_post'=>Icons.home_work,'danger'=>Icons.warning_amber,'parking'=>Icons.local_parking,
  'water'=>Icons.water_drop,'helipad'=>Icons.flight,'vehicle'=>Icons.directions_car,'viewpoint'=>Icons.visibility,
  'medical'=>Icons.local_hospital,'radio'=>Icons.cell_tower,'shelter'=>Icons.cottage,'flag'=>Icons.flag,_=>Icons.location_on};

String poiIconLabel(String? key)=>S.t('poi.icon.${poiIcons.contains(key)?key:'pin'}');

/// Default name of a new point: « Point HH:MM » (never « Point désigné »).
String defaultPoiName([DateTime? now]){
  final t=(now??DateTime.now()).toLocal(); String two(int v)=>v.toString().padLeft(2,'0');
  return S.t('poi.defaultName',{'hm':'${two(t.hour)}:${two(t.minute)}'});
}

/// Panel of symbols: a grid of round icons with their names.
class PoiIconPanel extends StatelessWidget {
  final String selected; final ValueChanged<String> onPick; final Color color;
  const PoiIconPanel({super.key,required this.selected,required this.onPick,required this.color});
  @override Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    return Wrap(spacing:4,runSpacing:4,children:[for(final k in poiIcons)SizedBox(width:72,child:InkWell(
      key:ValueKey('poi-icon-$k'),borderRadius:BorderRadius.circular(12),onTap:()=>onPick(k),
      child:Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Container(width:40,height:40,decoration:BoxDecoration(shape:BoxShape.circle,
          color:k==selected?s.primaryContainer:s.surfaceContainerHigh,border:Border.all(color:k==selected?s.primary:Colors.transparent,width:2)),
          child:Icon(poiIconData(k),size:22,color:color)),
        const SizedBox(height:2),
        Text(poiIconLabel(k),textAlign:TextAlign.center,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11)),
      ]))))]);
  }
}

/// Colour of a new point by its icon (lot 25, card « un seul moyen de
/// créer un point… couleur », choice 2): red Danger, blue Eau… from the
/// drawing palette; the pin takes the author's colour.
const poiIconColors=<String,int>{
  'gathering':0xFF43A047,'command_post':0xFF3949AB,'danger':0xFFE53935,'parking':0xFF039BE5,'water':0xFF1E88E5,
  'helipad':0xFF00897B,'vehicle':0xFF757575,'viewpoint':0xFF8E24AA,'medical':0xFFD81B60,'radio':0xFFFB8C00,
  'shelter':0xFF6D4C41,'flag':0xFFC0CA33};

/// Default colour of a point with [icon]; [pinColor] for the pin.
int poiDefaultColor(String? icon,int pinColor)=>poiIconColors[icon]??pinColor;

/// What the window of a point gives back: name, icon and colour.
typedef PoiDraft=({String name,String icon,int color});

/// One window to create and to modify a point (lot 25): name, icon and
/// colour. Creation: « Créer un point d'intérêt ici », name « Point HH:MM »,
/// colour of the icon. Modification ([edit]): « Modifier le point
/// d'intérêt », already filled, « Enregistrer ». The colour follows the
/// icon until another one is chosen. [pinColor]: colour of the pin (the
/// author's). Returns null when cancelled.
Future<PoiDraft?> showPoiDialog(BuildContext context,{required int pinColor,String? name,String? icon,int? color,bool edit=false}){
  var k=poiIcons.contains(icon)?icon!:'pin';
  var c=color??poiDefaultColor(k,pinColor);
  return showTextFieldsDialog<PoiDraft>(context,initial:[name??defaultPoiName()],builder:(ctx,f,set){
    void ok(){final n=f[0].text.trim();Navigator.pop(ctx,(name:n.isEmpty?defaultPoiName():n,icon:k,color:c));}
    void pickIcon(String v)=>set((){if(c==poiDefaultColor(k,pinColor))c=poiDefaultColor(v,pinColor);k=v;});
    final title=Theme.of(ctx).textTheme.titleSmall;
    return AlertDialog(title:Text(S.t(edit?'poi.editTitle':'poi.createHere')),
      content:SizedBox(width:400,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        TextField(key:const ValueKey('poi-create-name'),controller:f[0],autofocus:true,maxLength:160,
          decoration:InputDecoration(labelText:S.t('poi.name')),onSubmitted:(_)=>ok()),
        Padding(padding:const EdgeInsets.only(top:4,bottom:6),child:Text(S.t('poi.iconTitle'),style:title)),
        PoiIconPanel(selected:k,color:Color(c),onPick:pickIcon),
        Padding(padding:const EdgeInsets.only(top:12,bottom:6),child:Text(S.t('poi.colorTitle'),style:title)),
        Align(alignment:Alignment.centerLeft,child:ColorGrid(key:const ValueKey('poi-color'),colors:paletteWith(c),selected:c,onPick:(v)=>set(()=>c=v))),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(S.t('common.cancel'))),
        FilledButton(key:const ValueKey('poi-create-ok'),onPressed:ok,child:Text(S.t(edit?'common.save':'poi.create')))]);
  });
}
