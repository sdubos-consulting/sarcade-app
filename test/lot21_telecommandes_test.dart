// Outils › Télécommandes (lot 21, card « Télécommandes de relais : fonction
// à part entière, indépendante de MeshCore », 2 Nov 2026, 5 h 05), born in
// lot 19 (card « MeshCore : télécommande de relais (boîtier d'un membre de
// l'ADRASEC) », 1 Nov 2026, 22 h 03 to 22 h 07): codes filled in, a
// simulated box (answer, no answer, failure), the logbook lines, the
// remote on screen (mock-up « Relais Maurepas »), the rights of the PCO;
// lot 21: the remote of Maurepas taken over as it is (MeshCore transport),
// a transport unusable here said on the remote.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_chat.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_map.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_page.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_protocol.dart';
import 'package:sarcade_app/src/features/remotes/remote.dart';
import 'package:sarcade_app/src/features/remotes/remote_meshcore.dart';
import 'package:sarcade_app/src/features/remotes/remotes_page.dart';
import 'package:sarcade_app/src/features/tools/tools_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/comm_group.dart';

const boxKey='b0b1b2b3b4b5b6b7b8b9';
const otherKey='c0c1c2c3c4c5c6c7c8c9';

Remote maurepas({int relays=2})=>Remote(id:'rc-1',name:'Relais Maurepas',target:boxKey,targetName:'Boîtier Maurepas',
  relays:[for(var n=1;n<=relays;n++)RemoteRelay.numbered(n)]);

/// The simulated box: the codes it gets, and how the module takes them.
class Box {
  final sent=<String>[];
  MeshCoreMsgState answer=MeshCoreMsgState.sent;
  bool fail=false, ready=true;
  final messages=<MeshCoreChatMessage>[];
  Future<MeshCoreChatMessage> send(String key,String name,String text) async {
    if(fail)throw StateError('no module');
    sent.add(text);
    final m=MeshCoreChatMessage(id:'${sent.length}',text:text,mine:true,at:DateTime.now(),state:answer);
    messages.add(m);
    return m;
  }
  RemoteLink get link=>meshCoreRemoteLink(send:send,ready:()=>ready);
}

/// A tall window: every relay on screen.
void tall(WidgetTester t){
  t.view..physicalSize=const Size(900,2200)..devicePixelRatio=1;
  addTearDown(t.view.reset);
}

/// The remote of Maurepas as lot 19 kept it, under `meshcore_remotes`.
String lot19Prefs()=>jsonEncode({
  'remotes':[{'id':'rc-1','name':'Relais Maurepas','node':boxKey,'nodeName':'Boîtier Maurepas','relays':[
    {'name':'Relais VHF','on':'1111#','off':'2222#'},{'name':'Balise','on':'3333#','off':'4444#'}]}],
  'states':{'rc-1':[{'on':true,'at':'2026-11-01T21:58:08Z','reply':'Relais 1 activé'},{}]},
  'log':[{'at':'2026-11-01T21:58:08Z','actor':'PCO-Web','rid':'rc-1','remote':'Relais Maurepas','text':'Relais VHF allumé · confirmé'}],
});

void main(){
  setUp(()=>S.setLanguage('fr'));

  test('codes filled in: relay n on = 2n−1 four times then #, off = 2n',(){
    expect([for(var n=1;n<=4;n++)remoteRelayCodes(n)],[
      (on:'1111#',off:'2222#'),(on:'3333#',off:'4444#'),(on:'5555#',off:'6666#'),(on:'7777#',off:'8888#')]);
    final r=RemoteRelay.numbered(2);
    expect(r.name,'Relais 2'); expect(r.onCode,'3333#'); expect(r.offCode,'4444#');
    expect(r.readCode,isNull,reason:'« Lire l’état » ready but hidden');
  });

  group('simulated box',(){
    late Remotes remotes; late Box box; late Remote r;
    final t0=DateTime(2026,11,1,21,58);
    setUp(() async {
      box=Box();
      remotes=Remotes()..autoExpire=false..actor=(()=>'PCO-Web');
      remotes.links[RemoteTransport.meshcore]=box.link;
      r=maurepas();
      await remotes.put(r);
    });

    test('answer within 30 s: confirmed by the box, text kept, logbook line',() async {
      await remotes.command(r,0,true,now:t0);
      expect(box.sent,['1111#']);
      expect(remotes.states(r)[0].status,RemoteRelayStatus.waiting);
      expect(remoteRelayChip(remotes.states(r)[0]),'En attente');
      remotes.onIncoming(RemoteTransport.meshcore,otherKey,'R1 ON',now:t0.add(const Duration(seconds:3)));
      expect(remotes.states(r)[0].status,RemoteRelayStatus.waiting,reason:'another node does not confirm');
      remotes.onIncoming(RemoteTransport.meshtastic,boxKey,'R1 ON',now:t0.add(const Duration(seconds:4)));
      expect(remotes.states(r)[0].status,RemoteRelayStatus.waiting,reason:'another transport does not confirm');
      remotes.onIncoming(RemoteTransport.meshcore,meshCorePrefix(boxKey),' Relais 1 activé ',now:t0.add(const Duration(seconds:8)));
      final s=remotes.states(r)[0];
      expect(s.status,RemoteRelayStatus.confirmed); expect(s.on,isTrue); expect(s.reply,'Relais 1 activé');
      expect(remoteRelayChip(s),'Allumé');
      expect(remoteRelayDetail(s),['Confirmé par le boîtier à 21:58 · supposé','Relais 1 activé']);
      final line=remotes.log.single;
      expect(line.actor,'PCO-Web'); expect(line.text,'Relais 1 allumé · confirmé'); expect(line.remote,'Relais Maurepas');
      remotes.expire(t0.add(const Duration(minutes:2)));
      expect(s.status,RemoteRelayStatus.confirmed,reason:'nothing to expire');
    });

    test('no answer: « pas de confirmation » after 30 s, received by the node, then « Renvoyer »',() async {
      await remotes.command(r,1,false,now:t0);
      expect(box.sent,['4444#'],reason:'relay 2 off');
      box.messages.single.state=MeshCoreMsgState.delivered;
      remotes.expire(t0.add(const Duration(seconds:29)));
      expect(remotes.states(r)[1].status,RemoteRelayStatus.waiting);
      remotes.expire(t0.add(const Duration(seconds:30)));
      final s=remotes.states(r)[1];
      expect(s.status,RemoteRelayStatus.noConfirmation);
      expect(remoteRelayChip(s),'Pas de confirmation');
      expect(remoteRelayDetail(s).first,'« Éteindre » envoyé à 21:58 · reçu par le nœud · aucune réponse en 30 s');
      expect(remotes.log.single.text,'Relais 2 éteindre · pas de confirmation');
      // A late answer does not confirm a command given up.
      remotes.onIncoming(RemoteTransport.meshcore,boxKey,'R2 OFF',now:t0.add(const Duration(seconds:45)));
      expect(s.status,RemoteRelayStatus.noConfirmation);
      // « Renvoyer »: a new command, confirmed this time.
      await remotes.command(r,1,false,now:t0.add(const Duration(minutes:1)));
      remotes.onIncoming(RemoteTransport.meshcore,boxKey,'R2 OFF',now:t0.add(const Duration(minutes:1,seconds:4)));
      expect(s.status,RemoteRelayStatus.confirmed); expect(s.on,isFalse);
      expect(remoteRelayChip(s),'Éteint');
      expect(remotes.logOf(r.id).first.text,'Relais 2 éteint · confirmé');
    });

    test('failure: no module, the message fails at once',() async {
      box.fail=true;
      await remotes.command(r,0,true,now:t0);
      final s=remotes.states(r)[0];
      expect(s.status,RemoteRelayStatus.failed);
      expect(remoteRelayChip(s),'Échec');
      expect(remoteRelayDetail(s).single,'« Allumer » non envoyé : module MeshCore non connecté');
      expect(remotes.log.single.text,'Relais 1 allumer · échec');
      box..fail=false..answer=MeshCoreMsgState.failed;
      await remotes.command(r,1,true,now:t0);
      expect(remotes.states(r)[1].status,RemoteRelayStatus.failed);
    });

    test('no transport on this device: failed, nothing sent',() async {
      remotes.links.clear();
      expect(remotes.ready(r),isFalse);
      await remotes.command(r,0,true,now:t0);
      expect(box.sent,isEmpty);
      expect(remotes.states(r)[0].status,RemoteRelayStatus.failed);
    });

    test('two commands waiting: the answers come in order',() async {
      await remotes.command(r,0,true,now:t0);
      await remotes.command(r,1,true,now:t0.add(const Duration(seconds:2)));
      remotes.onIncoming(RemoteTransport.meshcore,boxKey,'ok 1',now:t0.add(const Duration(seconds:5)));
      expect(remotes.states(r)[0].status,RemoteRelayStatus.confirmed);
      expect(remotes.states(r)[1].status,RemoteRelayStatus.waiting);
      remotes.onIncoming(RemoteTransport.meshcore,boxKey,'ok 2',now:t0.add(const Duration(seconds:6)));
      expect(remotes.states(r)[1].reply,'ok 2');
    });

    test('kept on this device: remotes, transport, last confirmed state, logbook',() async {
      final prefs=<String,String?>{};
      remotes.attach(load:(k)=>prefs[k],save:(k,v) async {prefs[k]=v;});
      await remotes.command(r,0,true,now:t0);
      remotes.onIncoming(RemoteTransport.meshcore,boxKey,'R1 ON',now:t0.add(const Duration(seconds:4)));
      await Future<void>.delayed(Duration.zero);
      final kept=jsonDecode(prefs[remotesKey]!)['remotes'].single;
      expect(kept['relays'][1]['on'],'3333#');
      expect(kept['transport'],'meshcore'); expect(kept['target'],boxKey);
      final again=Remotes()..attach(load:(k)=>prefs[k],save:(k,v) async {prefs[k]=v;});
      final back=again.byId('rc-1')!;
      expect(back.name,'Relais Maurepas'); expect(back.relays.length,2); expect(back.transport,RemoteTransport.meshcore);
      expect(again.states(back)[0].on,isTrue);
      expect(again.states(back)[0].status,RemoteRelayStatus.confirmed);
      expect(again.states(back)[1].on,isNull);
      expect(again.log.single.text,'Relais 1 allumé · confirmé');
      expect(again.ofTarget(RemoteTransport.meshcore,boxKey).single.id,'rc-1');
      expect(again.ofTarget(RemoteTransport.meshtastic,boxKey),isEmpty);
    });
  });

  group('taken over from Outils › MeshCore (lot 19)',(){
    test('the remote of Maurepas, its states and its logbook, as they were',() async {
      final prefs=<String,String?>{remotesOldKey:lot19Prefs()};
      final remotes=Remotes()..attach(load:(k)=>prefs[k],save:(k,v) async {if(v==null){prefs.remove(k);}else{prefs[k]=v;}});
      final r=remotes.byId('rc-1')!;
      expect(r.name,'Relais Maurepas'); expect(r.transport,RemoteTransport.meshcore);
      expect(r.target,boxKey); expect(r.targetName,'Boîtier Maurepas');
      expect([for(final x in r.relays)'${x.name} ${x.onCode} ${x.offCode}'],['Relais VHF 1111# 2222#','Balise 3333# 4444#']);
      expect(remotes.states(r)[0].on,isTrue); expect(remotes.states(r)[0].reply,'Relais 1 activé');
      expect(remotes.states(r)[1].on,isNull);
      expect(remotes.log.single.text,'Relais VHF allumé · confirmé');
      expect(remotes.ofTarget(RemoteTransport.meshcore,boxKey).single.id,'rc-1');
      await Future<void>.delayed(Duration.zero);
      expect(prefs.containsKey(remotesOldKey),isFalse,reason:'old place emptied once copied');
      final kept=jsonDecode(prefs[remotesKey]!);
      expect(kept['remotes'].single['target'],boxKey);
      expect(kept['states']['rc-1'][0]['reply'],'Relais 1 activé');
      // Read again at the next start: the same, from the new place.
      final again=Remotes()..attach(load:(k)=>prefs[k],save:(k,v) async {prefs[k]=v;});
      expect(again.byId('rc-1')!.relays.length,2);
      expect(again.log.length,1);
    });

    test('the new place wins over an old one left behind',(){
      final prefs=<String,String?>{remotesOldKey:lot19Prefs(),remotesKey:jsonEncode({'remotes':[]})};
      final remotes=Remotes()..attach(load:(k)=>prefs[k],save:(k,v) async {prefs[k]=v;});
      expect(remotes.remotes,isEmpty);
    });

    test('unreadable old place: left untouched',() async {
      final prefs=<String,String?>{remotesOldKey:'{oops'};
      final remotes=Remotes()..attach(load:(k)=>prefs[k],save:(k,v) async {prefs[k]=v;});
      await Future<void>.delayed(Duration.zero);
      expect(remotes.remotes,isEmpty);
      expect(prefs[remotesOldKey],'{oops');
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
    expect(remoteCanDeclare('PCO-Web'),isTrue);
    expect(remoteCanDeclare('TEL-1'),isFalse);
  });

  test('Outils › Télécommandes: famille « Radio et liaisons »',(){
    String? opened;
    final item=remotesToolItem(open:(id,build){opened=id;});
    expect(item.id,'remotes'); expect(item.title,'Télécommandes'); expect(item.group,ToolGroup.radio);
    item.onTap();
    expect(opened,'remotes');
  });

  group('on screen',(){
    final remotes=Remotes.instance;
    late Box box;
    setUp(() async {
      box=Box();
      remotes..reset()..autoExpire=false..actor=(()=>'PCO-Web');
      remotes.links[RemoteTransport.meshcore]=box.link;
      await remotes.put(maurepas());
    });
    tearDown((){remotes.reset();myActorId=null;myRoles={};});

    testWidgets('« Allumer »: confirmation with the code, then confirmed by the box',(t) async {
      tall(t);
      await t.pumpWidget(const MaterialApp(home:RemotePage(remoteId:'rc-1')));
      expect(find.text('Relais Maurepas'),findsOneWidget);
      expect(find.text('Relais 1'),findsOneWidget); expect(find.text('Relais 2'),findsOneWidget);
      expect(find.text('Inconnu'),findsNWidgets(2));
      expect(find.text('Module MeshCore connecté'),findsOneWidget);
      expect(find.text('Boîtier redémarré : relais éteints. État non interrogeable pour l’instant'),findsOneWidget);
      expect(find.textContaining('Lire'),findsNothing,reason:'« Lire l’état » hidden');

      await t.tap(find.byKey(const ValueKey('remote-on-0')));
      await t.pumpAndSettle();
      expect(find.text('Allumer Relais 1 ?'),findsOneWidget);
      expect(find.textContaining('1111#'),findsOneWidget);
      expect(find.textContaining('par MeshCore'),findsOneWidget);
      await t.tap(find.byKey(const ValueKey('remote-confirm-send')));
      await t.pumpAndSettle();
      expect(box.sent,['1111#']);
      expect(find.text('En attente'),findsOneWidget);

      remotes.onIncoming(RemoteTransport.meshcore,boxKey,'Relais 1 activé');
      await t.pump();
      expect(find.text('Allumé'),findsOneWidget);
      expect(find.textContaining('Confirmé par le boîtier à'),findsOneWidget);
      expect(find.text('Relais 1 activé'),findsOneWidget);
      expect(find.textContaining('PCO-Web · Relais 1 allumé · confirmé'),findsOneWidget);
    });

    testWidgets('« Annuler »: nothing sent; no answer: « Renvoyer »',(t) async {
      tall(t);
      await t.pumpWidget(const MaterialApp(home:RemotePage(remoteId:'rc-1')));
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

    testWidgets('transport unusable here: said on the remote, states and logbook still shown',(t) async {
      tall(t);
      final r=remotes.byId('rc-1')!;
      await remotes.command(r,0,true);
      remotes.onIncoming(RemoteTransport.meshcore,boxKey,'Relais 1 activé');
      box.ready=false;
      await t.pumpWidget(const MaterialApp(home:RemotePage(remoteId:'rc-1')));
      expect(find.text('Module MeshCore non connecté : commandes impossibles'),findsOneWidget);
      expect(find.text('Allumé'),findsOneWidget,reason:'last state still shown');
      expect(find.textContaining('Relais 1 allumé · confirmé'),findsOneWidget,reason:'logbook still shown');
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('remote-on-0'))).onPressed,isNull);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('remote-off-1'))).onPressed,isNull);
      await t.tap(find.byKey(const ValueKey('remote-on-1')),warnIfMissed:false);
      await t.pumpAndSettle();
      expect(find.text('Allumer Relais 2 ?'),findsNothing);
      expect(box.sent,['1111#']);
    });

    testWidgets('list: transport and companion of each remote',(t) async {
      tall(t);
      await t.pumpWidget(const MaterialApp(home:RemotesPage()));
      expect(find.text('Télécommandes'),findsOneWidget);
      expect(find.text('MeshCore · Boîtier Maurepas · 2 relais'),findsOneWidget);
    });

    testWidgets('Outils › MeshCore keeps a link « Télécommandes »',(t) async {
      await t.pumpWidget(const MaterialApp(home:Scaffold(body:MeshCoreRemotesTile())));
      expect(find.byKey(const ValueKey('remote-tile')),findsOneWidget);
      expect(find.text('Télécommandes'),findsOneWidget);
      expect(find.text('Relais Maurepas'),findsOneWidget);
    });

    testWidgets('declaration: PCO only, Relais Maurepas first, MeshCore transport, codes filled in for 1 to 4 relays',(t) async {
      tall(t);
      remotes.reset();
      myActorId='TEL-1'; myRoles={};
      await t.pumpWidget(const MaterialApp(home:RemoteEditPage()));
      expect(find.text('Déclaration réservée au PCO'),findsOneWidget);
      myActorId='PCO-Web';
      await t.pumpWidget(const MaterialApp(home:RemoteEditPage(key:ValueKey('pco'))));
      expect(find.widgetWithText(TextField,'Relais Maurepas'),findsWidgets);
      expect(find.text('Transmission'),findsOneWidget);
      expect(find.text('MeshCore'),findsOneWidget);
      expect(find.text('Meshtastic et VHF plus tard'),findsOneWidget);
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

    testWidgets('a relay taken away: its fields freed after the frame, no error',(t) async {
      tall(t);
      myActorId='PCO-Web';
      await t.pumpWidget(const MaterialApp(home:RemoteEditPage(key:ValueKey('pco'))));
      await t.tap(find.text('4'));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('remote-code-on-3')));
      await t.pump();
      await t.tap(find.text('1'));
      await t.pumpAndSettle();
      expect(t.takeException(),isNull);
      expect(find.widgetWithText(TextField,'3333#'),findsNothing);
      await t.tap(find.text('2'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(TextField,'3333#'),findsOneWidget);
      expect(t.takeException(),isNull);
    });

    testWidgets('« Télécommande » on the floating card of the node',(t) async {
      await t.pumpWidget(MaterialApp(home:Scaffold(body:MeshCoreNodeCard(node:const MeshCoreContact(key:boxKey,type:1,name:'Boîtier Maurepas'),
        now:DateTime(2026,11,1,22),onClose:(){},onRemote:(){}))));
      expect(find.byKey(const ValueKey('mesh-card-remote')),findsOneWidget);
      expect(find.text('Télécommande'),findsOneWidget);
    });
  });
}
