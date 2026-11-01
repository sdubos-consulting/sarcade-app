// Lot 19, card « Messages : ouvrir une conversation sur le dernier
// message » (1 Nov 2026): a conversation of 200 messages, all unread (new
// device), opens on the last one; « ↑ N non lus » goes up to the separator;
// messages arriving while the list is built keep it at the bottom; same
// rule for the MeshCore threads.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_chat.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_chat_page.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_protocol.dart';
import 'package:sarcade_app/src/features/messages/chat_bottom.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

const _key='a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

Uint8List _u32(int v)=>Uint8List(4)..buffer.asByteData().setUint32(0,v,Endian.little);

/// CONTACT_MSG_RECV_V3 from the node [_key].
Uint8List _incoming(String text)=>Uint8List.fromList([0x10,30,0,0,0xa1,0xb2,0xc3,0xd4,0xe5,0xf6,2,0,..._u32(1793534400),...utf8.encode(text)]);

/// Text of message [i]: some long ones, so that the estimated heights of
/// the lazy list are wrong.
String _text(int i)=>i%7==0?'Message $i : ${List.filled(12,'compte rendu de la situation').join(' ')}':'Message $i';

/// A conversation built like the one of Messages: separator above the first
/// unread message, « ↑ N non lus », sticking to the bottom.
class _Chat extends StatefulWidget {
  final List<String> messages;
  final int firstUnread;
  const _Chat({required this.messages,required this.firstUnread});
  @override State<_Chat> createState()=>_ChatState();
}
class _ChatState extends State<_Chat>{
  final _scroll=ScrollController(); final _separator=SeparatorWatch();
  bool _atBottom=true;
  @override void initState(){
    super.initState();
    _scroll.addListener((){
      final atBottom=chatAtBottom(_scroll);
      if(atBottom!=_atBottom)setState(()=>_atBottom=atBottom);
      _separator.check(alive:()=>mounted,changed:()=>setState((){}));
    });
    WidgetsBinding.instance.addPostFrameCallback((_)=>chatJumpToBottom(_scroll,alive:()=>mounted));
  }
  @override void dispose(){_scroll.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final n=widget.messages.length-widget.firstUnread;
    return Stack(children:[
      StickToBottom(controller:_scroll,stick:()=>_atBottom,child:ListView.builder(controller:_scroll,itemCount:widget.messages.length,itemBuilder:(_,i){
        final b=Padding(padding:const EdgeInsets.all(8),child:Text(widget.messages[i]));
        if(i!=widget.firstUnread)return b;
        return Column(children:[Padding(key:_separator.key,padding:const EdgeInsets.all(6),child:Text(S.t('messages.unreadSeparator',{'n':n}))),b]);
      })),
      if(!_separator.seen)Positioned(top:10,left:0,right:0,child:Center(child:UnreadUpButton(count:n,
        onPressed:(){setState((){_separator.seen=true;_atBottom=false;});chatScrollToKey(_scroll,_separator.key,widget.firstUnread,widget.messages.length,alive:()=>mounted);}))),
    ]);
  }
}

void main(){
  setUp((){S.setLanguage('fr');MeshCoreChats.instance.reset();});

  test('MeshCore: first unread among the last messages received',(){
    expect(firstUnreadReceived([false,true,false,false],0),isNull);
    expect(firstUnreadReceived([false,true,false,false],2),2);
    expect(firstUnreadReceived([false,true,false,false],3),0);
    expect(firstUnreadReceived([true,false],5),1,reason:'more unread than received: the first received');
    expect(firstUnreadReceived([true,true],1),isNull);
  });

  test('« ↑ N non lus » in French and English',(){
    expect(S.t('messages.unreadUp',{'n':1}),'1 non lu');
    expect(S.t('messages.unreadUp',{'n':200}),'200 non lus');
    S.setLanguage('en');
    expect(S.t('messages.unreadUp',{'n':200}),'200 unread');
  });

  testWidgets('200 messages all unread: opened on the last one, « ↑ 200 non lus » goes up',(t) async {
    final messages=[for(var i=0;i<200;i++)_text(i)];
    await t.pumpWidget(MaterialApp(home:Scaffold(body:_Chat(messages:messages,firstUnread:0))));
    await t.pumpAndSettle();
    expect(find.text('Message 199').hitTestable(),findsOneWidget);
    expect(find.text('Message 1').hitTestable(),findsNothing);
    expect(find.byKey(const ValueKey('unread-up')),findsOneWidget);
    expect(find.text('200 non lus'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('unread-up')));
    await t.pumpAndSettle();
    expect(find.text('200 messages non lus').hitTestable(),findsOneWidget);
    expect(find.byKey(const ValueKey('unread-up')),findsNothing);
  });

  testWidgets('messages arriving while the list is built: still at the bottom',(t) async {
    final messages=[for(var i=0;i<200;i++)_text(i)];
    await t.pumpWidget(MaterialApp(home:Scaffold(body:_Chat(messages:messages,firstUnread:150))));
    await t.pump();
    for(var i=200;i<230;i++){
      messages.add(_text(i));
      await t.pumpWidget(MaterialApp(home:Scaffold(body:_Chat(messages:List.of(messages),firstUnread:150))));
      await t.pump();
    }
    await t.pumpAndSettle();
    expect(find.text('Message 229').hitTestable(),findsOneWidget);
  });

  testWidgets('MeshCore thread of 200 messages all unread: opened on the last one',(t) async {
    final chats=MeshCoreChats.instance..autoExpire=false;
    for(var i=0;i<200;i++){chats.onReceived(readMeshCoreMessage(_incoming(_text(i)))!,nameOf:(_)=>'Alice');}
    expect(chats.thread(_key)!.unread,200);
    await t.pumpWidget(MaterialApp(home:MeshCoreChatPage(prefix:meshCorePrefix(_key))));
    await t.pumpAndSettle();
    expect(find.text('Message 199').hitTestable(),findsOneWidget);
    expect(find.text('Message 1').hitTestable(),findsNothing);
    expect(chats.thread(_key)!.unread,0);
    expect(find.text('200 non lus'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('unread-up')));
    await t.pumpAndSettle();
    expect(find.text('200 messages non lus').hitTestable(),findsOneWidget);
    // A message received while reading higher up does not pull down.
    chats.onReceived(readMeshCoreMessage(_incoming('Nouveau'))!,nameOf:(_)=>'Alice');
    await t.pumpAndSettle();
    expect(find.text('200 messages non lus').hitTestable(),findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
