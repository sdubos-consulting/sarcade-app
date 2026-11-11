/// « Choix multiples sans bordures noires » (validated on 30 Oct 2026,
/// 2 h 14): every segmented choice of the application is a row of rounded
/// pills without border, in the style of « Tester le réveil »: the chosen one
/// light blue with a check mark, the others light grey.
library;

import 'package:flutter/material.dart';

typedef PillChoice<T>=({T value,String label,IconData? icon});

class ChoicePills<T> extends StatelessWidget {
  final List<PillChoice<T>> choices;
  final T selected;
  final ValueChanged<T> onSelected;
  final bool compact;
  /// One line, the width shared equally (Thème, 9 Nov 2026); the icon above
  /// the word when a pill is too narrow (large text).
  final bool equalWidth;
  const ChoicePills({super.key,required this.choices,required this.selected,required this.onSelected,this.compact=false,this.equalWidth=false});

  @override
  Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    Widget pill(PillChoice<T> c,{bool stacked=false}){
      final on=c.value==selected;
      final fg=on?s.onPrimaryContainer:s.onSurface;
      final icon=on?Icon(Icons.check,size:18,color:fg):c.icon!=null?Icon(c.icon,size:18,color:fg):null;
      final label=Text(c.label,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:fg,fontWeight:on?FontWeight.w600:FontWeight.w500));
      return Semantics(button:true,selected:on,inMutuallyExclusiveGroup:true,child:Material(
        color:on?s.primaryContainer:s.surfaceContainerHighest,shape:stacked?RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)):const StadiumBorder(),
        clipBehavior:Clip.antiAlias,
        child:InkWell(onTap:on?null:()=>onSelected(c.value),child:Padding(
          padding:EdgeInsets.symmetric(horizontal:compact||equalWidth?8:16,vertical:compact||equalWidth?7:9),
          child:stacked
            ?Column(mainAxisSize:MainAxisSize.min,children:[?icon,const SizedBox(height:2),label])
            :Row(mainAxisSize:equalWidth?MainAxisSize.max:MainAxisSize.min,mainAxisAlignment:MainAxisAlignment.center,children:[
              ?icon,
              if(icon!=null)const SizedBox(width:4),
              if(equalWidth)Flexible(child:label) else label,
            ])))));
    }
    if(equalWidth){
      return Row(children:[for(final (i,c) in choices.indexed)...[
        if(i>0)const SizedBox(width:6),
        Expanded(child:LayoutBuilder(builder:(context,box){
          // Icon above the word when the word would not fit beside it.
          final tp=TextPainter(text:TextSpan(text:c.label,style:DefaultTextStyle.of(context).style.copyWith(fontWeight:FontWeight.w600)),
            textDirection:TextDirection.ltr,textScaler:MediaQuery.textScalerOf(context),maxLines:1)..layout();
          return pill(c,stacked:tp.width+18+4+16>box.maxWidth);
        })),
      ]]);
    }
    return Wrap(spacing:8,runSpacing:8,children:[for(final c in choices)pill(c)]);
  }
}
