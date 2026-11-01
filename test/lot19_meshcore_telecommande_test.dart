// Lot 19, card « MeshCore : télécommande de relais (boîtier d'un membre de
// l'ADRASEC) » (1 Nov 2026, 22 h 03 to 22 h 07): codes filled in, a
// simulated box (answer, no answer, failure), the logbook lines, the
// remote on screen (mock-up « Relais Maurepas »), the rights of the PCO.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_chat.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_map.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_protocol.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_remote.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_remote_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/comm_group.dart';

const boxKey='b0b1b2b3b4b5b6b7b8b9';
const otherKey='c0c1c2c3c4c5c6c7c8c9';

MeshCoreRemote maurepas({int relays=2})=>MeshCoreRemote(id:'rc-1',name:'Relais Maurepas',nodeKey:boxKey,nodeName:'Boîtier Maurepas',
  relays:[for(var n=1;n<=relays;n++)MeshCoreRelay.numbered(n)]);

/// The simulated box: the codes it gets, and how the module takes them.
class Box {
  final sent=<String>[];
  MeshCoreMsgState answer=MeshCoreMsgState.sent;
  bool fail=false;
  final messages=<MeshCoreChatMessage>[];
  Future<MeshCoreChatMessage> send(String key,String name,String text) async {
    if(fail)throw StateError('no module');
    sent.add(text);
    final m=MeshCoreChatMessage(id:'${sent.length}',text:text,mine:true,at:DateTime.now(),state:answer);
    messages.add(m);
    return m;
  }
}

/// A tall window: every relay on screen.
void tall(WidgetTester t){
  t.view..physicalSize=const Size(900,2200)..devicePixelRatio=1;
  addTearDown(t.view.reset);
}

void main(){
  setUp(()=>S.setLanguage('fr'));

  test('codes filled in: relay n on = 2n−1 four times then #, off = 2n',(){
    expect([for(var n=1;n<=4;n++)meshCoreRelayCodes(n)],[
      (on:'1111#',off:'2222#'),(on:'3333#',off:'4444#'),(on:'5555#',off:'6666#'),(on:'7777#',off:'8888#')]);
    final r=MeshCoreRelay.numbered(2);
    expect(r.name,'Relais 2'); expect(r.onCode,'3333#'); expect(r.offCode,'4444#');
    expect(r.readCode,isNull,reason:'« Lire l’état » ready but hidden');
  });

  group('simulated box',(){
    late MeshCoreRemotes remotes; late Box box; late MeshCoreRemote r;
    final t0=DateTime(2026,11,1,21,58);
    setUp(() async {
      box=Box();
      remotes=MeshCoreRemotes()..autoExpire=false..actor=(()=>'PCO-Web')..send=box.send;
      r=maurepas();
      await remotes.put(r);
    });

    test('answer within 30 s: confirmed by the box, text kept, logbook line',() async {
      await remotes.command(r,0,true,now:t0);
      expect(box.sent,['1111#']);
      expect(remotes.states(r)[0].status,MeshCoreRelayStatus.waiting);
      expect(meshCoreRelayChip(remotes.states(r)[0]),'En attente');
      remotes.onIncoming(otherKey,'R1 ON',now:t0.add(const Duration(seconds:3)));
      expect(remotes.states(r)[0].status,MeshCoreRelayStatus.waiting,reason:'another node does not confirm');
      remotes.onIncoming(meshCorePrefix(boxKey),' Relais 1 activé ',now:t0.add(const Duration(seconds:8)));
      final s=remotes.states(r)[0];
      expect(s.status,MeshCoreRelayStatus.confirmed); expect(s.on,isTrue); expect(s.reply,'Relais 1 activé');
      expect(meshCoreRelayChip(s),'Allumé');
      expect(meshCoreRelayDetail(s),['Confirmé par le boîtier à 21:58 · supposé','Relais 1 activé']);
      final line=remotes.log.single;
      expect(line.actor,'PCO-Web'); expect(line.text,'Relais 1 allumé · confirmé'); expect(line.remote,'Relais Maurepas');
      remotes.expire(t0.add(const Duration(minutes:2)));
      expect(s.status,MeshCoreRelayStatus.confirmed,reason:'nothing to expire');
    });

    test('no answer: « pas de confirmation » after 30 s, received by the node, then « Renvoyer »',() async {
      await remotes.command(r,1,false,now:t0);
      expect(box.sent,['4444#'],reason:'relay 2 off');
      box.messages.single.state=MeshCoreMsgState.delivered;
      remotes.expire(t0.add(const Duration(seconds:29)));
      expect(remotes.states(r)[1].status,MeshCoreRelayStatus.waiting);
      remotes.expire(t0.add(const Duration(seconds:30)));
      final s=remotes.states(r)[1];
      expect(s.status,MeshCoreRelayStatus.noConfirmation);
      expect(meshCoreRelayChip(s),'Pas de confirmation');
      expect(meshCoreRelayDetail(s).first,'« Éteindre » envoyé à 21:58 · reçu par le nœud · aucune réponse en 30 s');
      expect(remotes.log.single.text,'Relais 2 éteindre · pas de confirmation');
      // A late answer does not confirm a command given up.
      remotes.onIncoming(boxKey,'R2 OFF',now:t0.add(const Duration(seconds:45)));
      expect(s.status,MeshCoreRelayStatus.noConfirmation);
      // « Renvoyer »: a new command, confirmed this time.
      await remotes.command(r,1,false,now:t0.add(const Duration(minutes:1)));
      remotes.onIncoming(boxKey,'R2 OFF',now:t0.add(const Duration(minutes:1,seconds:4)));
      expect(s.status,MeshCoreRelayStatus.confirmed); expect(s.on,isFalse);
      expect(meshCoreRelayChip(s),'Éteint');
      expect(remotes.logOf(r.id).first.text,'Relais 2 éteint · confirmé');
    });

    test('failure: no module, the message fails at once',() async {
      box.fail=true;
      await remotes.command(r,0,true,now:t0);
      final s=remotes.states(r)[0];
      expect(s.status,MeshCoreRelayStatus.failed);
      expect(meshCoreRelayChip(s),'Échec');
      expect(meshCoreRelayDetail(s).single,'« Allumer » non envoyé : module MeshCore non connecté');
      expect(remotes.log.single.text,'Relais 1 allumer · échec');
      box..fail=false..answer=MeshCoreMsgState.failed;
      await remotes.command(r,1,true,now:t0);
      expect(remotes.states(r)[1].status,MeshCoreRelayStatus.failed);
    });

    test('two commands waiting: the answers come in order',() async {
      await remotes.command(r,0,true,now:t0);
      await remotes.command(r,1,true,now:t0.add(const Duration(seconds:2)));
      remotes.onIncoming(boxKey,'ok 1',now:t0.add(const Duration(seconds:5)));
      expect(remotes.states(r)[0].status,MeshCoreRelayStatus.confirmed);
      expect(remotes.states(r)[1].status,MeshCoreRelayStatus.waiting);
      remotes.onIncoming(boxKey,'ok 2',now:t0.add(const Duration(seconds:6)));
      expect(remotes.states(r)[1].reply,'ok 2');
    });

    test('kept on this device: remotes, last confirmed state, logbook',() async {
      final prefs=<String,String?>{};
      remotes.attach(load:(k)=>prefs[k],save:(k,v) async {prefs[k]=v;});
      await remotes.command(r,0,true,now:t0);
      remotes.onIncoming(boxKey,'R1 ON',now:t0.add(const Duration(seconds:4)));
      await Future<void>.delayed(Duration.zero);
      expect(jsonDecode(prefs[meshCoreRemotesKey]!)['remotes'].single['relays'][1]['on'],'3333#');
      final again=MeshCoreRemotes()..attach(load:(k)=>prefs[k],save:(k,v) async {prefs[k]=v;});
      final back=again.byId('rc-1')!;
      expect(back.name,'Relais Maurepas'); expect(back.relays.length,2);
      expect(again.states(back)[0].on,isTrue);
      expect(again.states(back)[0].status,MeshCoreRelayStatus.confirmed);
      expect(again.states(back)[1].on,isNull);
      expect(again.log.single.text,'Relais 1 allumé · confirmé');
      expect(again.ofNode(boxKey).single.id,'rc-1');
    });
  });

  test('the answers of the box come through the private messages',(){
    final chats=MeshCoreChats()..autoExpire=false;
    final got=<String>[];
    chats.onIncoming=(p,text,at)=>got.add('$p|$text');
    chats.onReceived(MeshCoreIncoming(prefix:meshCorePrefix(boxKey),text:'Relais 1 activé'));
    expect(got,['${meshCorePrefix(boxKey)}|Relais 1 activé']);
    expect(chats.thread(boxKey)!.messages.single.text,'Relais 1 activé',reason:'also in the thread « MeshCore · nom du nœud »');
  });

  test('declare: the PCO only; use: every operator',(){
    expect(meshCoreRemoteCanDeclare('PCO-Web'),isTrue);
    expect(meshCoreRemoteCanDeclare('TEL-1'),isFalse);
  });

  group('on screen',(){
    final remotes=MeshCoreRemotes.instance;
    late Box box;
    setUp(() async {
      box=Box();
      remotes..reset()..autoExpire=false..send=box.send..actor=(()=>'PCO-Web');
      await remotes.put(maurepas());
    });
    tearDown((){remotes.reset();myActorId=null;myRoles={};});

    testWidgets('« Allumer »: confirmation with the code, then confirmed by the box',(t) async {
      tall(t);
      await t.pumpWidget(const MaterialApp(home:MeshCoreRemotePage(remoteId:'rc-1')));
      expect(find.text('Relais Maurepas'),findsOneWidget);
      expect(find.text('Relais 1'),findsOneWidget); expect(find.text('Relais 2'),findsOneWidget);
      expect(find.text('Inconnu'),findsNWidgets(2));
      expect(find.text('Boîtier redémarré : relais éteints. État non interrogeable pour l’instant'),findsOneWidget);
      expect(find.textContaining('Lire'),findsNothing,reason:'« Lire l’état » hidden');

      await t.tap(find.byKey(const ValueKey('remote-on-0')));
      await t.pumpAndSettle();
      expect(find.text('Allumer Relais 1 ?'),findsOneWidget);
      expect(find.textContaining('1111#'),findsOneWidget);
      await t.tap(find.byKey(const ValueKey('remote-confirm-send')));
      await t.pumpAndSettle();
      expect(box.sent,['1111#']);
      expect(find.text('En attente'),findsOneWidget);

      remotes.onIncoming(boxKey,'Relais 1 activé');
      await t.pump();
      expect(find.text('Allumé'),findsOneWidget);
      expect(find.textContaining('Confirmé par le boîtier à'),findsOneWidget);
      expect(find.text('Relais 1 activé'),findsOneWidget);
      expect(find.textContaining('PCO-Web · Relais 1 allumé · confirmé'),findsOneWidget);
    });

    testWidgets('« Annuler »: nothing sent; no answer: « Renvoyer »',(t) async {
      tall(t);
      await t.pumpWidget(const MaterialApp(home:MeshCoreRemotePage(remoteId:'rc-1')));
      await t.tap(find.byKey(const ValueKey('remote-off-1')));
      await t.pumpAndSettle();
      expect(find.text('Éteindre Relais 2 ?'),findsOneWidget);
      await t.tap(find.text('Annuler'));
      await t.pumpAndSettle();
      expect(box.sent,isEmpty);

      await t.tap(find.byKey(const ValueKey('remote-off-1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('remote-confirm-send')));
      await t.pumpAndSettle();
      expect(box.sent,['4444#']);
      remotes.expire(DateTime.now().add(const Duration(seconds:31)));
      await t.pump();
      expect(find.text('Pas de confirmation'),findsOneWidget);
      expect(find.byKey(const ValueKey('remote-resend-1')),findsOneWidget);
      expect(find.text('Renvoyer « Éteindre »'),findsOneWidget);
      await t.tap(find.byKey(const ValueKey('remote-resend-1')));
      await t.pumpAndSettle();
      expect(find.text('Éteindre Relais 2 ?'),findsOneWidget,reason:'confirmation before every sending');
    });

    testWidgets('declaration: PCO only, Relais Maurepas first, codes filled in for 1 to 4 relays',(t) async {
      tall(t);
      remotes.reset();
      myActorId='TEL-1'; myRoles={};
      await t.pumpWidget(const MaterialApp(home:MeshCoreRemoteEditPage()));
      expect(find.text('Déclaration réservée au PCO'),findsOneWidget);
      myActorId='PCO-Web';
      await t.pumpWidget(const MaterialApp(home:MeshCoreRemoteEditPage(key:ValueKey('pco'))));
      expect(find.widgetWithText(TextField,'Relais Maurepas'),findsWidgets);
      expect(find.widgetWithText(TextField,'1111#'),findsOneWidget);
      await t.tap(find.text('3'));
      await t.pump();
      expect(find.widgetWithText(TextField,'5555#'),findsOneWidget);
      expect(find.widgetWithText(TextField,'6666#'),findsOneWidget);
      expect(find.widgetWithText(TextField,'7777#'),findsNothing);
      await t.tap(find.text('4'));
      await t.pump();
      expect(find.widgetWithText(TextField,'8888#'),findsOneWidget);
    });

    testWidgets('« Télécommande » on the floating card of the node',(t) async {
      await t.pumpWidget(MaterialApp(home:Scaffold(body:MeshCoreNodeCard(node:const MeshCoreContact(key:boxKey,type:1,name:'Boîtier Maurepas'),
        now:DateTime(2026,11,1,22),onClose:(){},onRemote:(){}))));
      expect(find.byKey(const ValueKey('mesh-card-remote')),findsOneWidget);
      expect(find.text('Télécommande'),findsOneWidget);
    });
  });
}
