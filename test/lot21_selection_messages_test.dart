// Lot 21, card « Messages : sélection de plusieurs messages » (2 Nov 2026):
// « Sélectionner » in the menu of a message, the message touched already
// checked; a simple touch checks or unchecks; bar « N sélectionnés » with
// ✕, Copier and Supprimer; « Supprimer pour tous » only when allowed on
// each message; distress messages and orders never for everyone; Back
// (Android) and Échap (computer) leave the selection.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/message_deletion.dart';
import 'package:sarcade_app/src/features/messages/message_selection.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/message.dart';

final _now=DateTime.now();

SarcadeMessage _msg(String id,String body,{String sender='TEL-01',DateTime? at,String priority='routine',bool deleted=false})=>SarcadeMessage(
  id:id,eventId:'e1',senderId:sender,recipientIds:const [],priority:priority,body:body,createdAt:(at??_now).toUtc(),deleted:deleted);

/// A conversation built like the one of Messages: the bubble opens its menu
/// on a long press (« Sélectionner »), the selection bar replaces the title.
class _Chat extends StatefulWidget {
  final List<SarcadeMessage> messages; final String me;
  const _Chat({required this.messages,this.me='TEL-01'});
  @override State<_Chat> createState()=>_ChatState();
}
class _ChatState extends State<_Chat>{
  final selection=MessageSelection(); final focus=FocusNode();
  String? copied, deleteChoice; int bubbleTaps=0;
  @override void initState(){super.initState();selection.addListener(_changed);}
  void _changed(){if(mounted)setState((){});}
  @override void dispose(){selection.removeListener(_changed);selection.dispose();focus.dispose();super.dispose();}
  List<SarcadeMessage> get _selected=>selectedIn(widget.messages,selection);

  Future<void> _menu(SarcadeMessage m) async {
    final choice=await showModalBottomSheet<String>(context:context,builder:(c)=>Column(mainAxisSize:MainAxisSize.min,children:[
      ListTile(key:const ValueKey('msg-select'),title:Text(S.t('messages.select')),onTap:()=>Navigator.pop(c,'select')),
    ]));
    if(choice=='select'){selection.start(m.id);focus.requestFocus();}
  }

  Future<void> _delete() async {
    final list=_selected;
    deleteChoice=await showSelectionDeleteDialog(context,count:list.length,
      everyone:canDeleteAllForEveryone(list,widget.me,pco:widget.me=='PCO',now:DateTime.now()),
      mine:list.every((m)=>m.senderId==widget.me),kept:list.any(keptForEveryone));
    if(deleteChoice!=null)selection.clear();
  }

  @override Widget build(BuildContext context)=>MessageSelectionScope(selection:selection,focusNode:focus,child:Scaffold(
    appBar:PreferredSize(preferredSize:const Size.fromHeight(56),child:Material(child:selection.active
      ?MessageSelectionBar(count:_selected.length,onExit:()=>selection.clear(),onDelete:_delete,
        onCopy:_selected.any((m)=>!m.deleted)?(){copied=selectionCopyText(_selected);selection.clear();}:null)
      :const Text('Tous'))),
    body:ListView(children:[for(final m in widget.messages)SelectableMessage(id:m.id,selecting:selection.active,selected:selection.contains(m.id),
      onToggle:(){selection.toggle(m.id);if(selection.active)focus.requestFocus();},
      child:GestureDetector(onTap:()=>bubbleTaps++,onLongPress:()=>_menu(m),onSecondaryTap:()=>_menu(m),
        child:Padding(padding:const EdgeInsets.all(12),child:Text(m.body))))]),
  ));
}

Future<_ChatState> _open(WidgetTester tester,List<SarcadeMessage> messages,{String me='TEL-01'}) async {
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(c)=>Scaffold(body:Center(child:TextButton(
    onPressed:()=>Navigator.push(c,MaterialPageRoute<void>(builder:(_)=>_Chat(messages:messages,me:me))),child:const Text('ouvrir')))))));
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return tester.state<_ChatState>(find.byType(_Chat));
}

/// In selection mode, the whole row of the message is touched.
Finder _row(String id)=>find.byKey(ValueKey('msg-selectable-$id'));

Future<void> _select(WidgetTester tester,String body) async {
  await tester.longPress(find.text(body));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('msg-select')));
  await tester.pumpAndSettle();
}

void main(){
  setUp(()=>S.setLanguage('fr'));

  test('copy: chronological order, one per line, time and author',(){
    final a=_msg('a','Véhicule repéré',at:DateTime(2026,11,2,14,32));
    final b=_msg('b','En place\nau point P2',sender:'TEL-02',at:DateTime(2026,11,2,14,35));
    final c=_msg('c','',at:DateTime(2026,11,2,14,33),deleted:true);
    expect(selectionCopyText([b,c,a]),'[14:32] TEL-01 : Véhicule repéré\n[14:35] TEL-02 : En place au point P2');
  });

  test('« pour tous » only when allowed on each message',(){
    final recent=_msg('a','Véhicule repéré');
    final old=_msg('b','Ancien',at:_now.subtract(const Duration(days:3)));
    final other=_msg('c','Pas à moi',sender:'TEL-02');
    final distress=_msg('d','🆘 DÉTRESSE — TEL-01 — position 48.80000, 2.10000',priority:'immediate');
    final order=_msg('o','📍 Ordre de déplacement : rejoindre « P2 » (48.80000, 2.10000)',sender:'PCO',priority:'immediate');
    final end=_msg('f','Fin de détresse — TEL-01',priority:'urgent');
    expect(canDeleteAllForEveryone([recent],'TEL-01',pco:false,now:_now),isTrue);
    expect(canDeleteAllForEveryone([recent,old],'TEL-01',pco:false,now:_now),isFalse);
    expect(canDeleteAllForEveryone([recent,other],'TEL-01',pco:false,now:_now),isFalse);
    expect(canDeleteAllForEveryone([recent,old,other],'PCO',pco:true,now:_now),isTrue);
    expect(canDeleteAllForEveryone([],'PCO',pco:true,now:_now),isFalse);
    // Distress, its end and orders: never for everyone, not even by the PCO.
    for(final m in [distress,order,end,_msg('p','Aide',priority:'distress')]){
      expect(keptForEveryone(m),isTrue,reason:m.body);
      expect(canDeleteForEveryone(m,m.senderId,pco:true,now:_now),isFalse,reason:m.body);
    }
    expect(canDeleteAllForEveryone([recent,distress],'PCO',pco:true,now:_now),isFalse);
    expect(keptForEveryone(_msg('u','Véhicule repéré',priority:'immediate')),isFalse);
    expect(keptForEveryone(_msg('v','📍 P2')),isFalse);
  });

  test('selection: start, toggle, the last one unchecked leaves',(){
    final s=MessageSelection();
    expect(s.active,isFalse);
    s.start('a');
    expect(s.active,isTrue); expect(MessageSelection.anyActive,isTrue);
    s.toggle('b'); expect(s.count,2);
    s.toggle('a'); s.toggle('b');
    expect(s.active,isFalse); expect(MessageSelection.anyActive,isFalse);
    expect(s.clear(),isFalse);
    s.dispose();
  });

  testWidgets('« Sélectionner » checks the message, a touch checks or unchecks',(tester) async {
    final chat=await _open(tester,[_msg('a','Premier'),_msg('b','Deuxième'),_msg('c','Troisième')]);
    expect(find.byKey(const ValueKey('select-count')),findsNothing);
    await _select(tester,'Deuxième');
    expect(find.text('1 sélectionné'),findsOneWidget);
    expect(find.byKey(const ValueKey('msg-checked-b')),findsOneWidget);
    expect(find.byKey(const ValueKey('msg-unchecked-a')),findsOneWidget);
    // A simple touch checks (the bubble itself does not react).
    await tester.tap(_row('a'));
    await tester.pump();
    expect(find.text('2 sélectionnés'),findsOneWidget);
    expect(chat.bubbleTaps,0);
    await tester.tap(_row('c'));
    await tester.pump();
    expect(find.text('3 sélectionnés'),findsOneWidget);
    // And unchecks.
    await tester.tap(_row('a'));
    await tester.pump();
    expect(find.text('2 sélectionnés'),findsOneWidget);
    expect(find.byKey(const ValueKey('msg-unchecked-a')),findsOneWidget);
    // ✕ leaves; the bubble reacts again.
    await tester.tap(find.byKey(const ValueKey('select-exit')));
    await tester.pump();
    expect(find.byKey(const ValueKey('select-count')),findsNothing);
    await tester.tap(find.text('Premier'));
    expect(chat.bubbleTaps,1);
  });

  testWidgets('Copier: the messages in order, then the selection closes',(tester) async {
    final chat=await _open(tester,[_msg('a','Premier',at:_now.subtract(const Duration(minutes:5))),_msg('b','Deuxième',sender:'TEL-02')]);
    await _select(tester,'Deuxième');
    await tester.tap(_row('a'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('select-copy')));
    await tester.pump();
    expect(chat.copied!.split('\n'),hasLength(2));
    expect(chat.copied!.split('\n').first,endsWith('TEL-01 : Premier'));
    expect(chat.copied!.split('\n').last,endsWith('TEL-02 : Deuxième'));
    expect(chat.selection.active,isFalse);
  });

  testWidgets('Supprimer: « pour tous » only when allowed on each message',(tester) async {
    final chat=await _open(tester,[_msg('a','Premier'),_msg('b','Deuxième'),_msg('c','Ancien',at:_now.subtract(const Duration(days:3)))]);
    await _select(tester,'Premier');
    await tester.tap(_row('b'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('select-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer les 2 messages ?'),findsOneWidget);
    expect(find.byKey(const ValueKey('select-delete-me')),findsOneWidget);
    expect(find.byKey(const ValueKey('select-delete-all')),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('select-delete-all')));
    await tester.pumpAndSettle();
    expect(chat.deleteChoice,'all');
    // With a message of 3 days: « Supprimer pour moi » only.
    await _select(tester,'Premier');
    await tester.tap(_row('c'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('select-delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('select-delete-all')),findsNothing);
    expect(find.text(S.t('messages.selectOnlyMe')),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('select-delete-me')));
    await tester.pumpAndSettle();
    expect(chat.deleteChoice,'me');
  });

  testWidgets('PCO: distress and orders never for everyone',(tester) async {
    await _open(tester,[_msg('a','Véhicule repéré',sender:'TEL-02'),
      _msg('d','🆘 DÉTRESSE — TEL-01 — position 48.80000, 2.10000',priority:'immediate')],me:'PCO');
    await _select(tester,'Véhicule repéré');
    await tester.tap(find.byKey(const ValueKey('select-delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('select-delete-all')),findsOneWidget);
    await tester.tap(find.text(S.t('common.cancel')));
    await tester.pumpAndSettle();
    await tester.tap(_row('d'));
    await tester.pump();
    expect(find.text('2 sélectionnés'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('select-delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('select-delete-all')),findsNothing);
    expect(find.text(S.t('messages.selectProtected')),findsOneWidget);
  });

  testWidgets('Échap leaves the selection',(tester) async {
    final chat=await _open(tester,[_msg('a','Premier')]);
    await _select(tester,'Premier');
    expect(chat.selection.active,isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(chat.selection.active,isFalse);
    expect(find.byKey(const ValueKey('select-count')),findsNothing);
  });

  testWidgets('Back leaves the selection first, then the screen',(tester) async {
    final chat=await _open(tester,[_msg('a','Premier')]);
    await _select(tester,'Premier');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(_Chat),findsOneWidget);
    expect(chat.selection.active,isFalse);
    expect(MessageSelection.anyActive,isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(_Chat),findsNothing);
  });
}
