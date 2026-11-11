// Lot 17, card « MeshCore : nœuds sur la carte et discussion directe avec
// un nœud » (1 Nov 2026): nodes with and without position, a repeater
// that cannot be written to, a message sent then acknowledged, an answer
// received.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_chat.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_chat_page.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_map.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_protocol.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

const _key='a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

MeshCoreContact node({int type=1,String name='Alice',double? lat=48.80,double? lon=2.13,DateTime? advert,String key=_key})=>
  MeshCoreContact(key:key,type:type,name:name,lat:lat,lon:lon,hops:1,lastAdvert:advert??DateTime(2026,11,1,11));

Uint8List _u32(int v)=>Uint8List(4)..buffer.asByteData().setUint32(0,v,Endian.little);

/// CONTACT_MSG_RECV_V3 from the node [_key]: SNR 7.5 dB, 2 hops.
Uint8List incomingV3(String text,{int type=0})=>Uint8List.fromList([0x10,30,0,0,0xa1,0xb2,0xc3,0xd4,0xe5,0xf6,2,type,..._u32(1793534400),
  if(type==2)...[1,2,3,4],...utf8.encode(text)]);

void main(){
  setUp((){S.setLanguage('fr');MeshCoreChats.instance.reset();meshCoreSelected.value=null;});

  group('protocol',(){
    test('CMD_SEND_TXT_MSG: plain text, attempt, timestamp, key prefix',(){
      final f=sendTextMessage(meshCorePrefix(_key),'Bonjour',at:DateTime.fromMillisecondsSinceEpoch(1793534400*1000,isUtc:true),attempt:1);
      expect(f.sublist(0,3),[0x02,0,1]);
      expect(f.sublist(3,7),_u32(1793534400));
      expect(f.sublist(7,13),[0xa1,0xb2,0xc3,0xd4,0xe5,0xf6]);
      expect(utf8.decode(f.sublist(13)),'Bonjour');
      expect(syncNextMessage(),[0x0A]);
    });

    test('RESP_CODE_SENT, SEND_CONFIRMED and the kinds of frames',(){
      final sent=readMeshCoreSent(Uint8List.fromList([0x06,1,..._u32(0xCAFE),..._u32(4500)]))!;
      expect(sent.flood,isTrue); expect(sent.ack,0xCAFE); expect(sent.timeout,const Duration(milliseconds:4500));
      expect(readMeshCoreConfirmed(Uint8List.fromList([0x82,..._u32(0xCAFE),..._u32(900)])),0xCAFE);
      final i=MeshCoreInfo();
      expect(readMeshCoreFrame(Uint8List.fromList([0x06,0,0,0,0,0,0,0,0,0]),i),'sent');
      expect(readMeshCoreFrame(Uint8List.fromList([0x82,0,0,0,0]),i),'confirmed');
      expect(readMeshCoreFrame(Uint8List.fromList([0x83]),i),'waiting');
      expect(readMeshCoreFrame(incomingV3('x'),i),'contactMsg');
      expect(readMeshCoreFrame(Uint8List.fromList([0x0A]),i),'noMore');
    });

    test('a message of a node, version 3, version 2 and signed',(){
      final m=readMeshCoreMessage(incomingV3('Reçu, j’arrive'))!;
      expect(m.prefix,'a1b2c3d4e5f6'); expect(m.text,'Reçu, j’arrive'); expect(m.snr,7.5); expect(m.hops,2);
      expect(readMeshCoreMessage(incomingV3('Signé',type:2))!.text,'Signé');
      final old=readMeshCoreMessage(Uint8List.fromList([0x07,0xa1,0xb2,0xc3,0xd4,0xe5,0xf6,0xFF,0,..._u32(1),...utf8.encode('OK')]))!;
      expect(old.text,'OK'); expect(old.hops,isNull,reason:'0xFF: direct'); expect(old.snr,isNull);
    });

    test('133 characters at most',(){
      expect(meshCoreTextFits('a'*133),isTrue);
      expect(meshCoreTextFits('a'*134),isFalse);
      expect(meshCoreTextFits('   '),isFalse);
    });
  });

  group('nodes on the map',(){
    test('with and without position; grey after 24 h; a repeater is not written to',(){
      final now=DateTime(2026,11,1,12);
      final placed=node(), nowhere=node(name:'Bob',lat:null,lon:null,key:'ff$_key');
      expect(meshCoreOnMap([placed,nowhere]).map((c)=>c.name),['Alice']);
      expect(meshCoreStale(placed,now),isFalse);
      expect(meshCoreStale(node(advert:DateTime(2026,10,31,11)),now),isTrue);
      expect(meshCoreWritable(placed),isTrue);
      expect(meshCoreWritable(node(type:2,name:'Relais')),isFalse);
      expect(meshCoreWritable(node(type:3,name:'Salon')),isFalse);
      expect(meshCoreDistance(placed,const LatLng(48.80,2.13)),'0 m');
      expect(meshCoreDistance(nowhere,const LatLng(48.80,2.13)),isNull);
    });

    testWidgets('the card: « Écrire » for a companion only, « Centrer » with a position',(t) async {
      Future<void> card(MeshCoreContact c,{VoidCallback? write,VoidCallback? centre})=>t.pumpWidget(MaterialApp(home:Scaffold(body:MeshCoreNodeCard(
        node:c,now:DateTime(2026,11,1,12),distance:'1,20 km',snr:7.5,onClose:(){},onWrite:write,onCenter:centre))));
      await card(node(),write:(){},centre:(){});
      expect(find.text('Alice'),findsOneWidget);
      expect(find.text('Compagnon'),findsOneWidget);
      expect(find.text('1,20 km'),findsOneWidget);
      expect(find.text('7.5 dB'),findsOneWidget);
      expect(find.byKey(const ValueKey('mesh-card-write')),findsOneWidget);
      expect(find.byKey(const ValueKey('mesh-card-center')),findsOneWidget);
      final relay=node(type:2,name:'Relais Rambouillet',lat:null,lon:null);
      await card(relay,write:meshCoreWritable(relay)?(){}:null,centre:meshCoreHasPosition(relay)?(){}:null);
      expect(find.text('Répéteur'),findsOneWidget);
      expect(find.byKey(const ValueKey('mesh-card-write')),findsNothing);
      expect(find.byKey(const ValueKey('mesh-card-center')),findsNothing);
      expect(find.text('sans position'),findsOneWidget);
    });
  });

  group('private messages',(){
    test('sent, then received by the node (acknowledgement)',() async {
      final chats=MeshCoreChats()..autoExpire=false;
      final frames=<Uint8List>[];
      chats.send=(f,_) async=>frames.add(f);
      final m=await chats.write(_key,'Alice','Où êtes-vous ?',now:DateTime(2026,11,1,12));
      expect(frames.single[0],0x02);
      expect(m.state,MeshCoreMsgState.sending);
      expect(chats.thread(_key)!.name,'Alice');
      chats.onSent(0xCAFE,const Duration(seconds:3),now:DateTime(2026,11,1,12));
      expect(m.state,MeshCoreMsgState.sent);
      chats.onConfirmed(0xBEEF);
      expect(m.state,MeshCoreMsgState.sent,reason:'another acknowledgement');
      chats.onConfirmed(0xCAFE);
      expect(m.state,MeshCoreMsgState.delivered);
      expect(meshCoreMsgStateText(m.state),'reçu par le nœud');
    });

    test('failure: no acknowledgement in time, an error of the module, no module',() async {
      final chats=MeshCoreChats()..autoExpire=false;
      chats.send=(f,_) async {};
      final t0=DateTime(2026,11,1,12);
      final a=await chats.write(_key,'Alice','Un',now:t0);
      chats.onSent(1,const Duration(seconds:3),now:t0);
      chats.expire(t0.add(const Duration(seconds:19)));
      expect(a.state,MeshCoreMsgState.sent);
      chats.expire(t0.add(const Duration(seconds:21)));
      expect(a.state,MeshCoreMsgState.failed);
      final b=await chats.write(_key,'Alice','Deux',now:t0);
      chats.onError();
      expect(b.state,MeshCoreMsgState.failed);
      chats.send=null;
      final c=await chats.write(_key,'Alice','Trois',now:t0);
      expect(c.state,MeshCoreMsgState.failed);
      expect(meshCoreMsgStateText(c.state),'échec');
    });

    test('an answer of the node: in its thread and as a notification',(){
      final chats=MeshCoreChats()..autoExpire=false;
      final shown=<String>[];
      chats.notify=(title,body)=>shown.add('$title|$body');
      chats.onReceived(readMeshCoreMessage(incomingV3('Bien reçu'))!,nameOf:(p)=>p=='a1b2c3d4e5f6'?'Alice':null);
      final t=chats.thread(_key)!;
      expect(t.name,'Alice');
      expect(t.messages.single.text,'Bien reçu');
      expect(t.messages.single.mine,isFalse);
      expect(t.unread,1);
      expect(chats.snr['a1b2c3d4e5f6'],7.5);
      expect(shown,['MeshCore · Alice|Bien reçu']);
      // Thread on screen: no notification, nothing unread.
      chats.markRead(_key); chats.openThread=t.prefix;
      chats.onReceived(readMeshCoreMessage(incomingV3('Encore'))!);
      expect(shown.length,1); expect(t.unread,0); expect(t.messages.length,2);
    });

    test('threads kept on the device; a message left with the module is failed',() async {
      final prefs=<String,String?>{};
      final a=MeshCoreChats()..autoExpire=false;
      a.attach(load:(k)=>prefs[k],save:(k,v) async=>prefs[k]=v);
      a.send=(f,_) async {};
      await a.write(_key,'Alice','Bonjour');
      await Future<void>.delayed(Duration.zero);
      final b=MeshCoreChats()..attach(load:(k)=>prefs[k],save:(k,v) async=>prefs[k]=v);
      final t=b.thread(_key)!;
      expect(t.name,'Alice');
      expect(t.messages.single.text,'Bonjour');
      expect(t.messages.single.state,MeshCoreMsgState.failed);
    });

    testWidgets('the thread « MeshCore · nom » in Messages and its page',(t) async {
      final chats=MeshCoreChats.instance..autoExpire=false;
      chats.onReceived(readMeshCoreMessage(incomingV3('Bien reçu'))!,nameOf:(_)=>'Alice');
      await t.pumpWidget(const MaterialApp(home:Scaffold(body:MeshCoreThreadTiles())));
      expect(find.text('MeshCore · Alice'),findsOneWidget);
      expect(find.text('1'),findsOneWidget,reason:'unread');
      await t.pumpWidget(MaterialApp(home:MeshCoreChatPage(prefix:meshCorePrefix(_key))));
      await t.pump();
      expect(find.text('MeshCore · Alice'),findsOneWidget);
      expect(find.text('Bien reçu'),findsOneWidget);
      // No module connected: said, and nothing can be sent.
      expect(find.byKey(const ValueKey('mesh-chat-offline')),findsOneWidget);
      expect(t.widget<IconButton>(find.byKey(const ValueKey('mesh-chat-send'))).onPressed,isNull);
      expect(chats.thread(_key)!.unread,0);
      await t.pumpWidget(const SizedBox());
      expect(chats.openThread,isNull);
    });
  });
}
