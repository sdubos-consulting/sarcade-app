/// « Modifier » a message sent (lot 29, group 7): by its author, within
/// 15 minutes, never a distress message nor an order (same rule as the
/// server); everyone then sees « modifié » and the PCO keeps the versions.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/message.dart';
import 'message_deletion.dart';

const editDelay=Duration(minutes:15);
const editMaxLength=2048;

bool canEditMessage(SarcadeMessage m,String actorId,{required DateTime now})=>
  !m.deleted&&m.senderId==actorId&&!keptForEveryone(m)&&now.toUtc().difference(m.createdAt.toUtc())<=editDelay;

/// The text to send, or null when nothing changed or the text is empty.
String? editedText(SarcadeMessage m,String typed){
  final t=typed.trim();
  if(t.isEmpty||t==m.body.trim()||t.length>editMaxLength)return null;
  return t;
}

/// Payload of the sync « message / update ».
Map<String,dynamic> editPayload(SarcadeMessage m,String body,String actorId)=>
  {'id':m.id,'event_id':m.eventId,'body':body,'edited_by':actorId};

/// Shown at once on this device, before the server answers.
Map<String,dynamic> editedLocally(SarcadeMessage m,String body)=>{...m.toJson(),'body':body,'edited':true};

/// The text in a dialog; the controller lives as long as the dialog.
class EditMessageDialog extends StatefulWidget {
  final String initial;
  const EditMessageDialog({super.key,required this.initial});
  @override
  State<EditMessageDialog> createState()=>_EditMessageDialogState();
}

class _EditMessageDialogState extends State<EditMessageDialog>{
  late final _ctrl=TextEditingController(text:widget.initial);
  @override
  void dispose(){_ctrl.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>AlertDialog(
    title:Text(S.t('messages.editTitle')),
    content:TextField(key:const ValueKey('msg-edit-field'),controller:_ctrl,autofocus:true,minLines:1,maxLines:6,maxLength:editMaxLength),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(context),child:Text(S.t('common.cancel'))),
      FilledButton(key:const ValueKey('msg-edit-save'),onPressed:()=>Navigator.pop(context,_ctrl.text),child:Text(S.t('common.save'))),
    ]);
}
