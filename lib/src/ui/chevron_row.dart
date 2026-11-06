/// One entry of a settings screen (card « Paramètres › Administration :
/// lignes avec chevron au lieu des boutons Ouvrir », lot 29.4, extended to
/// every screen): the whole line touchable, icon on the left, title and a
/// small explanation under it, the value on the right if useful, « › ».
library;

import 'package:flutter/material.dart';

class ChevronRow extends StatelessWidget {
  final IconData? icon; final String title; final String? subtitle, value; final VoidCallback? onTap;
  const ChevronRow({super.key,required this.title,this.icon,this.subtitle,this.value,this.onTap});
  @override Widget build(BuildContext context){
    final t=Theme.of(context); final s=t.colorScheme;
    return InkWell(onTap:onTap,child:ConstrainedBox(constraints:const BoxConstraints(minHeight:52),child:Padding(
      padding:const EdgeInsets.fromLTRB(4,8,0,8),child:Row(children:[
        if(icon!=null)...[Icon(icon,size:22,color:onTap==null?s.onSurface.withValues(alpha:0.38):s.onSurfaceVariant),const SizedBox(width:16)],
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
          Text(title,style:t.textTheme.bodyLarge),
          if(subtitle!=null&&subtitle!.isNotEmpty)Text(subtitle!,style:t.textTheme.bodySmall?.copyWith(color:s.onSurfaceVariant)),
        ])),
        if(value!=null)...[const SizedBox(width:8),ConstrainedBox(constraints:const BoxConstraints(maxWidth:160),
          child:Text(value!,textAlign:TextAlign.end,style:t.textTheme.bodyMedium?.copyWith(color:s.onSurfaceVariant)))],
        Icon(Icons.chevron_right,color:s.onSurfaceVariant),
      ]))));
  }
}
