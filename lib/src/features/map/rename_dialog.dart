/// Window to change a name (card « Point d'intérêt : double-clic pour le
/// renommer », lot 19, choice 1): the current name already selected, Entrée
/// to save, Échap to cancel.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

/// Shows the window; the new name (trimmed), or null when cancelled.
Future<String?> askNewName(BuildContext context,{required String title,required String initial,String? label,Key? fieldKey,int maxLength=160})=>
  showDialog<String>(context:context,builder:(_)=>RenameDialog(title:title,initial:initial,label:label,fieldKey:fieldKey,maxLength:maxLength));

/// The dialog owns its text controller (disposing it when the Future
/// completed freed it while the closing animation still used it).
class RenameDialog extends StatefulWidget {
  final String title, initial; final String? label; final Key? fieldKey; final int maxLength;
  const RenameDialog({super.key,required this.title,required this.initial,this.label,this.fieldKey,this.maxLength=160});
  @override State<RenameDialog> createState()=>_RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late final TextEditingController _controller=TextEditingController.fromValue(TextEditingValue(text:widget.initial,
    selection:TextSelection(baseOffset:0,extentOffset:widget.initial.length)));
  @override void dispose(){_controller.dispose();super.dispose();}
  void _save()=>Navigator.pop(context,_controller.text.trim());
  @override Widget build(BuildContext context)=>AlertDialog(
    title:Text(widget.title),
    content:TextField(key:widget.fieldKey,controller:_controller,autofocus:true,maxLength:widget.maxLength,
      textCapitalization:TextCapitalization.sentences,
      decoration:InputDecoration(labelText:widget.label),onSubmitted:(_)=>_save()),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(context),child:Text(S.t('common.cancel'))),
      FilledButton(onPressed:_save,child:Text(S.t('common.save'))),
    ],
  );
}
