/// One entry of a « … » menu (card « Messages : menu … plus soigné »,
/// lot 29.3): round coloured icon, a short label on one line, a detail in
/// small under it; greyed with [done] (« Déjà ajoutés »).
library;

import 'package:flutter/material.dart';

Widget menuEntry(BuildContext context,{required IconData icon,required Color color,required String title,String? detail,bool done=false}){
  final t=Theme.of(context); final s=t.colorScheme;
  final c=done?s.onSurface.withValues(alpha:0.38):color;
  return Row(children:[
    CircleAvatar(radius:16,backgroundColor:c.withValues(alpha:0.14),child:Icon(icon,size:18,color:c)),
    const SizedBox(width:12),
    Flexible(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
      Text(title,maxLines:1,overflow:TextOverflow.ellipsis,style:t.textTheme.bodyLarge?.copyWith(color:done?c:null)),
      if(detail!=null)Text(detail,maxLines:1,overflow:TextOverflow.ellipsis,style:t.textTheme.bodySmall?.copyWith(color:s.onSurfaceVariant)),
    ])),
  ]);
}
