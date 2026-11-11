/// Selection of several messages (lot 21, 2 Nov 2026), like WhatsApp:
/// « Sélectionner » in the menu of a message (long press, right click), the
/// message touched already checked; then a simple touch checks or unchecks;
/// bar « N sélectionnés » with ✕, Copier and Supprimer. Back (Android) and
/// Échap (computer) leave the selection.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/message.dart';
import 'message_deletion.dart';

/// Messages checked in the conversation open; empty = no selection.
class MessageSelection extends ChangeNotifier {
  final _ids=<String>{};
  /// Selections in progress on any screen: the screens around (tabs of the
  /// map, panels) leave Back to them.
  static final _active=<MessageSelection>{};
  static bool get anyActive=>_active.isNotEmpty;

  bool get active=>_ids.isNotEmpty;
  int get count=>_ids.length;
  bool contains(String id)=>_ids.contains(id);

  /// « Sélectionner »: the message touched, alone.
  void start(String id){_ids..clear()..add(id);_changed();}
  /// A touch checks or unchecks; the last one unchecked leaves the selection.
  void toggle(String id){if(!_ids.remove(id))_ids.add(id);_changed();}
  /// Leaves the selection; false when there was none.
  bool clear({bool notify=true}){
    if(_ids.isEmpty)return false;
    _ids.clear();_changed(notify:notify);
    return true;
  }
  void _changed({bool notify=true}){
    if(_ids.isEmpty){_active.remove(this);}else{_active.add(this);}
    if(notify)notifyListeners();
  }
  @override void dispose(){_active.remove(this);super.dispose();}
}

String _two(int v)=>v.toString().padLeft(2,'0');

/// Text copied (as WhatsApp): the messages in chronological order, one per
/// line, « [14:32] TEL-01 : texte ». A deleted message has no text: skipped.
String selectionCopyText(Iterable<SarcadeMessage> selected){
  final list=selected.where((m)=>!m.deleted).toList()..sort((a,b)=>a.createdAt.compareTo(b.createdAt));
  return [for(final m in list)'[${_two(m.createdAt.toLocal().hour)}:${_two(m.createdAt.toLocal().minute)}] ${m.senderId} : ${m.body.trim().replaceAll(RegExp(r'\s*\n\s*'),' ')}'].join('\n');
}

/// « Supprimer pour tous » only when it is allowed on each message.
bool canDeleteAllForEveryone(Iterable<SarcadeMessage> selected,String actorId,{required bool pco,required DateTime now})=>
  selected.isNotEmpty&&selected.every((m)=>canDeleteForEveryone(m,actorId,pco:pco,now:now));

/// The selected messages of the conversation, in its order.
List<SarcadeMessage> selectedIn(Iterable<SarcadeMessage> shown,MessageSelection selection)=>
  [for(final m in shown)if(selection.contains(m.id))m];

/// A message in selection mode: the whole row checks or unchecks it; the
/// bubble itself (photos, quote, buttons) does not react meanwhile.
class SelectableMessage extends StatelessWidget {
  final String id; final bool selecting, selected; final VoidCallback onToggle; final Widget child;
  const SelectableMessage({super.key,required this.id,required this.selecting,required this.selected,required this.onToggle,required this.child});
  @override Widget build(BuildContext context){
    if(!selecting)return child;
    final s=Theme.of(context).colorScheme;
    return Semantics(selected:selected,button:true,child:GestureDetector(key:ValueKey('msg-selectable-$id'),behavior:HitTestBehavior.opaque,
      onTap:onToggle,onLongPress:onToggle,onSecondaryTap:onToggle,
      child:ColoredBox(color:selected?s.primary.withValues(alpha:0.16):Colors.transparent,child:Row(children:[
        Padding(padding:const EdgeInsets.only(left:10),child:Icon(selected?Icons.check_circle:Icons.radio_button_unchecked,
          key:ValueKey(selected?'msg-checked-$id':'msg-unchecked-$id'),size:22,color:selected?s.primary:s.outline)),
        Expanded(child:IgnorePointer(child:child)),
      ]))));
  }
}

/// Bar « N sélectionnés »: ✕ to leave, Copier, Supprimer.
class MessageSelectionBar extends StatelessWidget {
  final int count; final VoidCallback onExit, onDelete; final VoidCallback? onCopy;
  const MessageSelectionBar({super.key,required this.count,required this.onExit,required this.onDelete,this.onCopy});
  Widget get exitButton=>IconButton(key:const ValueKey('select-exit'),tooltip:S.t('messages.selectExit'),onPressed:onExit,icon:const Icon(Icons.close));
  Widget get title=>Text(S.t('messages.selectCount',{'n':count}),key:const ValueKey('select-count'));
  List<Widget> get actions=>[
    IconButton(key:const ValueKey('select-copy'),tooltip:S.t('messages.selectCopy'),onPressed:onCopy,icon:const Icon(Icons.copy)),
    IconButton(key:const ValueKey('select-delete'),tooltip:S.t('messages.selectDelete'),onPressed:onDelete,icon:const Icon(Icons.delete_outline)),
  ];
  @override Widget build(BuildContext context)=>Row(children:[
    exitButton,const SizedBox(width:8),
    Flexible(child:DefaultTextStyle.merge(style:Theme.of(context).textTheme.titleMedium,child:title)),
    const Spacer(),...actions,
  ]);
}

/// Back (Android) and Échap (computer) leave the selection first.
class MessageSelectionScope extends StatelessWidget {
  final MessageSelection selection; final FocusNode focusNode; final Widget child;
  const MessageSelectionScope({super.key,required this.selection,required this.focusNode,required this.child});
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:selection,builder:(_,inner)=>PopScope(
    canPop:!selection.active,
    // After the other handlers of the route: they see the selection still
    // open and leave Back to it.
    onPopInvokedWithResult:(didPop,_){if(!didPop&&selection.active)scheduleMicrotask(selection.clear);},
    child:inner!),
    child:Focus(focusNode:focusNode,onKeyEvent:(_,e){
      if(!selection.active||e is! KeyDownEvent||e.logicalKey!=LogicalKeyboardKey.escape)return KeyEventResult.ignored;
      selection.clear();
      return KeyEventResult.handled;
    },child:child));
}

/// « Supprimer pour moi » always; « Supprimer pour tous » only when allowed
/// on each message; distress messages and orders never for everyone.
/// Returns 'me', 'all' or null.
Future<String?> showSelectionDeleteDialog(BuildContext context,{required int count,required bool everyone,required bool mine,required bool kept})=>
  showDialog<String>(context:context,builder:(c)=>AlertDialog(
    title:Text(S.t('messages.selectDeleteTitle',{'n':count})),
    content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(everyone?S.t(mine?'messages.deleteHelpMine':'messages.deleteHelpPco'):S.t('messages.deleteHelpMe')),
      if(!everyone&&!kept)Padding(padding:const EdgeInsets.only(top:8),child:Text(S.t('messages.selectOnlyMe'))),
      if(kept)Padding(padding:const EdgeInsets.only(top:8),child:Text(S.t('messages.selectProtected'))),
    ]),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
      TextButton(key:const ValueKey('select-delete-me'),onPressed:()=>Navigator.pop(c,'me'),child:Text(S.t('messages.deleteForMe'))),
      if(everyone)FilledButton(key:const ValueKey('select-delete-all'),style:FilledButton.styleFrom(backgroundColor:Theme.of(c).colorScheme.error,foregroundColor:Theme.of(c).colorScheme.onError),
        onPressed:()=>Navigator.pop(c,'all'),child:Text(S.t('messages.deleteForAll'))),
    ]));
