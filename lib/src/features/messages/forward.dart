/// « Transférer » a message (lot 29, group 7): to one or several
/// conversations; the copy carries « Transféré · author, time » of the
/// original (written by the server from the original), photos and positions
/// follow; the forward is written in the Main courante by the server. Never
/// a distress message nor an order, never a deleted message.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/message.dart';
import 'message_deletion.dart';

bool canForward(SarcadeMessage m)=>!m.deleted&&!keptForEveryone(m);

/// The copy for one conversation; the priority of the original is kept.
SarcadeMessage forwardedCopy(SarcadeMessage original,{required String id,required String me,required List<String> recipients,required DateTime now})=>
  SarcadeMessage(id:id,eventId:original.eventId,senderId:me,recipientIds:recipients,priority:original.priority,body:original.body,
    createdAt:now.toUtc(),attachments:original.attachments,
    forwardedId:original.forwardedId??original.id,forwardedSender:original.forwardedSender??original.senderId,
    forwardedAt:original.forwardedAt??original.createdAt);

/// « Transféré · TEL-01, 21:30 ».
String forwardedLabel(SarcadeMessage m,String Function(DateTime) hm)=>
  S.t('messages.forwardedFrom',{'who':m.forwardedSender??'','at':m.forwardedAt==null?'':hm(m.forwardedAt!)});

/// One or several conversations, ticked.
class ForwardDialog extends StatefulWidget{
  final List<({String key,String title,Widget icon})> targets;
  const ForwardDialog({super.key,required this.targets});
  @override
  State<ForwardDialog> createState()=>_ForwardDialogState();
}

class _ForwardDialogState extends State<ForwardDialog>{
  final _picked=<String>{};
  @override
  Widget build(BuildContext context)=>AlertDialog(
    title:Text(S.t('messages.forwardTitle')),
    contentPadding:const EdgeInsets.symmetric(vertical:8),
    content:SizedBox(width:360,child:ListView(shrinkWrap:true,children:[
      for(final t in widget.targets)CheckboxListTile(key:ValueKey('forward-${t.key}'),secondary:t.icon,title:Text(t.title,overflow:TextOverflow.ellipsis),
        value:_picked.contains(t.key),onChanged:(v)=>setState(()=>v==true?_picked.add(t.key):_picked.remove(t.key))),
    ])),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(context),child:Text(S.t('common.cancel'))),
      FilledButton(key:const ValueKey('forward-send'),onPressed:_picked.isEmpty?null:()=>Navigator.pop(context,_picked.toList()),
        child:Text(S.t('messages.forwardSend',{'n':_picked.length}))),
    ]);
}
