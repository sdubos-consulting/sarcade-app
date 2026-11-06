/// « Glisser une bulle pour y répondre » (lot 29, group 7): on a phone or a
/// tablet, sliding a bubble to the right opens the quoted reply, like
/// « Répondre », with a small vibration and the reply arrow while sliding;
/// on a computer, a « Répondre » arrow when the pointer is over the bubble.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';

const swipeReplyAt=56.0;
const swipeReplyMax=80.0;

/// Offset of the bubble for a slide of [dx] (never to the left, slowed past
/// the threshold).
double swipeOffset(double dx){
  if(dx<=0)return 0;
  if(dx<=swipeReplyAt)return dx;
  return (swipeReplyAt+(dx-swipeReplyAt)*0.3).clamp(0,swipeReplyMax).toDouble();
}

class SwipeReply extends StatefulWidget{
  final Widget child; final VoidCallback? onReply; final bool hoverArrow;
  const SwipeReply({super.key,required this.child,required this.onReply,this.hoverArrow=false});
  @override
  State<SwipeReply> createState()=>_SwipeReplyState();
}

class _SwipeReplyState extends State<SwipeReply>{
  double _dx=0; bool _armed=false; bool _hover=false;

  void _update(DragUpdateDetails d){
    final next=_dx+d.delta.dx;
    final armed=next>=swipeReplyAt;
    if(armed&&!_armed)HapticFeedback.lightImpact();
    setState((){_dx=next<0?0:next;_armed=armed;});
  }
  void _end(DragEndDetails d){
    final reply=_armed;
    setState((){_dx=0;_armed=false;});
    if(reply)widget.onReply?.call();
  }

  @override
  Widget build(BuildContext context){
    if(widget.onReply==null)return widget.child;
    final s=Theme.of(context).colorScheme;
    final off=swipeOffset(_dx);
    final arrow=Opacity(opacity:(off/swipeReplyAt).clamp(0,1).toDouble(),
      child:CircleAvatar(radius:14,backgroundColor:s.surfaceContainerHighest,child:Icon(Icons.reply,size:18,color:s.onSurfaceVariant)));
    final body=GestureDetector(onHorizontalDragUpdate:_update,onHorizontalDragEnd:_end,onHorizontalDragCancel:()=>setState((){_dx=0;_armed=false;}),
      child:Stack(clipBehavior:Clip.none,alignment:Alignment.centerLeft,children:[
        if(off>0)Positioned(left:-4,child:arrow),
        Transform.translate(offset:Offset(off,0),child:widget.child),
      ]));
    if(!widget.hoverArrow)return body;
    return MouseRegion(onEnter:(_)=>setState(()=>_hover=true),onExit:(_)=>setState(()=>_hover=false),
      child:Row(mainAxisSize:MainAxisSize.min,children:[
        Flexible(child:body),
        AnimatedOpacity(opacity:_hover?1:0,duration:const Duration(milliseconds:120),child:IconButton(key:const ValueKey('hover-reply'),
          tooltip:S.t('messages.replyQuote'),visualDensity:VisualDensity.compact,iconSize:18,onPressed:_hover?widget.onReply:null,icon:const Icon(Icons.reply))),
      ]));
  }
}
