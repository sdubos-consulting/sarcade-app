// SPDX-License-Identifier: MPL-2.0
// © SDUBOS Consulting et contributeurs SARCADE

// Lot 28, card « Module Meshtastic, sur le modèle de MeshCore », point 3:
// direct message to a node and messages on the primary channel, threads
// « Meshtastic · nom » in Messages, acknowledgement when Meshtastic gives
// it; simulated module (fixtures/meshtastic_frames.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/meshtastic/meshtastic_chat.dart';
import 'package:sarcade_app/src/features/meshtastic/meshtastic_chat_page.dart';
import 'package:sarcade_app/src/features/meshtastic/meshtastic_link.dart';
import 'package:sarcade_app/src/features/meshtastic/meshtastic_protocol.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

import 'fixtures/meshtastic_frames.dart';

void main(){
  final link=MeshtasticLink.instance, chats=MeshtasticChats.instance;
  final notes=<String>[];
  final saved=<String,String?>{};

  setUp((){
    S.setLanguage('fr');
    link..testMode=true..resetForTest();
    link.testPrefs[meshtasticDeviceKey]='11:22:33';
    chats..reset()..autoExpire=false;
    link.restoreForTest();
    link.wireChatsForTest();
    // Fixed packet ids, as in the samples (acknowledgement 0x11223344).
    var next=0x11223344;
    chats.newId=()=>next++;
    notes.clear(); saved.clear();
    chats.notify=(title,body)=>notes.add('$title | $body');
    chats.attach(load:(k)=>saved[k],save:(k,v) async {saved[k]=v;});
    for(final s in ['myInfo','loraConfig','channelPrimary','nodeMe','nodeRouter','nodeNoPos','configComplete']){link.onFrame(meshtasticSample(s));}
  });
  tearDown((){chats..reset()..autoExpire=true;link..resetForTest()..testMode=false;});

  test('direct message: written as Meshtastic expects, sent, then received by the node',() async {
    link.testSent.clear();
    final m=await chats.write('!0badcafe','Relais Maurepas','Reçu, 5 sur 5');
    expect(m.state,MeshtasticMsgState.sending);
    expect(m.packetId,0x11223344);
    final sent=link.testSent.single;
    expect([for(final b in sent)b.toRadixString(16).padLeft(2,'0')].join(),meshtasticSamples['sendDirect']);
    link.onFrame(meshtasticSample('queue'));
    expect(m.state,MeshtasticMsgState.sent);
    link.onFrame(meshtasticSample('ackDelivered'));
    expect(m.state,MeshtasticMsgState.delivered,reason:'acknowledgement of the node itself');
    expect(saved[meshtasticChatsKey],contains('Reçu, 5 sur 5'));
  });

  test('no acknowledgement after the retries of the module: failure, « Renvoyer »',() async {
    final m=await chats.write('!0badcafe','Relais Maurepas','Allô');
    link.onFrame(meshtasticSample('nakMaxRetransmit'));
    expect(m.state,MeshtasticMsgState.failed);
    await chats.retry('!0badcafe',m);
    expect(m.state,MeshtasticMsgState.sending);
    expect(m.packetId,isNot(0x11223344),reason:'a new packet');
  });

  test('nothing heard in time: failure',() async {
    final at=DateTime.utc(2026,11,4,18);
    final m=await chats.write('!0badcafe','Relais Maurepas','Allô',now:at);
    chats.expire(at.add(const Duration(minutes:1)));
    expect(m.state,MeshtasticMsgState.sending);
    chats.expire(at.add(const Duration(minutes:3)));
    expect(m.state,MeshtasticMsgState.failed);
  });

  test('module not connected or text too long: failure at once',() async {
    expect((await chats.write('!0badcafe','R','x'*201)).state,MeshtasticMsgState.failed);
    await link.disconnect();
    expect((await chats.write('!0badcafe','R','Allô')).state,MeshtasticMsgState.failed);
  });

  test('primary channel: sent once taken; messages of the others with their name',() async {
    link.testSent.clear();
    final m=await chats.write(meshtasticChannelKey,link.channelName??'','A tous');
    final hex=[for(final b in link.testSent.single)b.toRadixString(16).padLeft(2,'0')].join();
    expect(hex,startsWith('0a'),reason:'ToRadio packet');
    expect(hex,contains('15ffffffff'),reason:'to every node');
    link.onFrame(meshtasticSample('queue'));
    expect(m.state,MeshtasticMsgState.sent);
    link.onFrame(meshtasticSample('textChannel'));
    final t=chats.thread(meshtasticChannelKey)!;
    expect(t.name,'LongFast');
    expect(meshtasticThreadTitle(t),'Meshtastic · Canal principal · LongFast');
    expect(t.last!.text,'Point radio 12 OK');
    expect(t.last!.sender,'Sans position');
    expect(notes.single,'Meshtastic · LongFast | Sans position : Point radio 12 OK');
  });

  test('direct message received: its thread, a notification, the name of the node',(){
    link.onFrame(meshtasticSample('textDirect'));
    final t=chats.thread('!0badcafe')!;
    expect(meshtasticThreadTitle(t),'Meshtastic · Relais Maurepas');
    expect(t.last!.text,'Bonjour Gérard');
    expect(t.unread,1);
    expect(notes.single,'Meshtastic · Relais Maurepas | Bonjour Gérard');
    chats.markRead('!0badcafe');
    expect(chats.unread,0);
  });

  test('a message on another channel, an encrypted one, or my own echo is not kept',(){
    link.onFrame(meshtasticSample('encrypted'));
    chats.onPacket(MeshtasticPacket(from:0xa1b2c3d4,to:meshtasticBroadcast,portnum:meshtasticPortText,payload:meshtasticSample('heartbeat')));
    chats.onPacket(MeshtasticPacket(from:0x0badcafe,to:meshtasticBroadcast,channel:1,portnum:meshtasticPortText,payload:meshtasticSample('heartbeat')));
    expect(chats.threads,isEmpty);
  });

  test('threads kept on this device, read again at the next start',() async {
    await chats.write('!0badcafe','Relais Maurepas','Allô');
    link.onFrame(meshtasticSample('textDirect'));
    final raw=saved[meshtasticChatsKey];
    chats.reset();
    chats.attach(load:(_)=>raw,save:(_,_) async {});
    final t=chats.thread('!0badcafe')!;
    expect(t.messages.map((m)=>m.text),['Allô','Bonjour Gérard']);
    expect(t.messages.first.state,MeshtasticMsgState.failed,reason:'still with the module when SARCADE stopped');
  });

  testWidgets('thread screen: write, state of the message, threads in Messages',(t) async {
    await t.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:Column(children:[
      TextButton(onPressed:()=>openMeshtasticNodeChat(context,link.node(0x0badcafe)!),child:const Text('open')),
      const MeshtasticThreadTiles(),
    ])))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Meshtastic · Relais Maurepas'),findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('meshtastic-chat-field')),'Bien reçu');
    await t.pump();
    expect(find.text('10 / 200'),findsOneWidget,reason:'bytes, « ç » takes two');
    await t.tap(find.byKey(const ValueKey('meshtastic-chat-send')));
    await t.pump();
    expect(find.text('Bien reçu'),findsOneWidget);
    expect(find.text('envoi…'),findsOneWidget);
    link.onFrame(meshtasticSample('queue'));
    link.onFrame(meshtasticSample('ackDelivered'));
    await t.pump();
    expect(find.text('reçu par le nœud'),findsOneWidget);
    // Back to the list: the thread is there.
    Navigator.of(t.element(find.byType(MeshtasticChatPage))).pop();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('meshtastic-thread-!0badcafe')),findsOneWidget);
  });
}
