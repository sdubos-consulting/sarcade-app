// Lot 21, card « Télécommande : la liste des nœuds ne se ferme pas sans
// choisir une ligne » (2 Nov 2026, 10 h 45): a window of choice in place of
// the drop-down list, « Annuler » at the top, a search field as in Outils ›
// MeshCore, the node already chosen first and ticked, the same window on a
// phone and a computer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_protocol.dart';
import 'package:sarcade_app/src/features/remotes/remote.dart';
import 'package:sarcade_app/src/features/remotes/remote_node_picker.dart';
import 'package:sarcade_app/src/features/remotes/remotes_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/comm_group.dart';

final now=DateTime.now();
MeshCoreContact node(String key,String name,int minutesAgo)=>
  MeshCoreContact(key:key,type:1,name:name,lastAdvert:now.subtract(Duration(minutes:minutesAgo)));

final nodes=[
  for(var i=0;i<40;i++)node('a${i.toString().padLeft(2,'0')}0000000000000000','Compagnon $i',i+1),
  node('b0b1b2b3b4b5b6b7b8b9','Boîtier Maurepas',600),
  node('c0c1c2c3c4c5c6c7c8c9','Élancourt',2),
];

/// A page with a button that opens the window; [size]: phone or computer.
Future<List<String?>> openPicker(WidgetTester t,{required Size size,String? selected,String selectedName=''}) async {
  t.view..physicalSize=size..devicePixelRatio=1;
  addTearDown(t.view.reset);
  final got=<String?>[];
  await t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(context)=>TextButton(
    onPressed:() async {got.add(await pickRemoteNode(context,nodes:nodes,selected:selected,selectedName:selectedName));},
    child:const Text('ouvrir'))))));
  await t.tap(find.text('ouvrir'));
  await t.pumpAndSettle();
  return got;
}

void main(){
  setUp(()=>S.setLanguage('fr'));

  test('the chosen node first, then the others heard most recently first',(){
    final l=remoteNodeChoices(nodes,selected:'b0b1b2b3b4b5b6b7b8b9');
    expect(l.first.name,'Boîtier Maurepas');
    expect(l[1].name,'Compagnon 0'); expect(l[2].name,'Compagnon 1'); expect(l[3].name,'Élancourt');
    expect(l.length,nodes.length,reason:'no line twice');
    expect(remoteNodeChoices(nodes).first.name,'Compagnon 0');
  });

  test('search as in Outils › MeshCore: words of the name, accents ignored, start of the key',(){
    expect([for(final c in remoteNodeChoices(nodes,query:'elan'))c.name],['Élancourt']);
    expect([for(final c in remoteNodeChoices(nodes,query:'b0b1'))c.name],['Boîtier Maurepas']);
    final l=remoteNodeChoices(nodes,selected:'b0b1b2b3b4b5b6b7b8b9',query:'compagnon 3');
    expect(l.first.name,'Compagnon 3');
    expect(l.every((c)=>c.name.startsWith('Compagnon')&&c.name.contains('3')),isTrue,reason:'the chosen node is filtered too');
  });

  test('a chosen node no longer heard stays first, under its kept name',(){
    final l=remoteNodeChoices(nodes,selected:'d0d1d2d3d4d5d6d7d8d9',selectedName:'Ancien boîtier');
    expect(l.first.name,'Ancien boîtier'); expect(l.length,nodes.length+1);
  });

  for(final (what,size) in [('phone',const Size(390,844)),('computer',const Size(1400,900))]){
    testWidgets('$what: « Annuler » at the top closes without choosing',(t) async {
      final got=await openPicker(t,size:size,selected:'b0b1b2b3b4b5b6b7b8b9');
      expect(find.byKey(const ValueKey('remote-pick')),findsOneWidget);
      expect(find.byKey(const ValueKey('remote-pick-cancel')),findsOneWidget);
      final cancelY=t.getTopLeft(find.byKey(const ValueKey('remote-pick-cancel'))).dy;
      final firstY=t.getTopLeft(find.byKey(const ValueKey('remote-pick-b0b1b2b3'))).dy;
      expect(cancelY,lessThan(firstY),reason:'« Annuler » above the list');
      expect(find.descendant(of:find.byKey(const ValueKey('remote-pick-b0b1b2b3')),matching:find.byKey(const ValueKey('remote-pick-ticked'))),findsOneWidget);
      expect(find.byKey(const ValueKey('remote-pick-ticked')),findsOneWidget);
      await t.tap(find.byKey(const ValueKey('remote-pick-cancel')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('remote-pick')),findsNothing);
      expect(got,[null]);
    });

    testWidgets('$what: search then choose a line',(t) async {
      final got=await openPicker(t,size:size);
      await t.enterText(find.byKey(const ValueKey('remote-pick-find')),'élancourt');
      await t.pump();
      expect(find.text('Élancourt'),findsOneWidget);
      expect(find.text('Compagnon 0'),findsNothing);
      await t.enterText(find.byKey(const ValueKey('remote-pick-find')),'zzz');
      await t.pump();
      expect(find.byKey(const ValueKey('remote-pick-none')),findsOneWidget);
      await t.tap(find.byKey(const ValueKey('remote-pick-clear')));
      await t.pump();
      expect(find.text('Compagnon 0'),findsOneWidget);
      await t.tap(find.text('Compagnon 0'));
      await t.pumpAndSettle();
      expect(got,[nodes.first.key]);
    });
  }

  group('declaration',(){
    final remotes=Remotes.instance;
    setUp(()=>remotes.reset());
    tearDown((){remotes.reset();myActorId=null;myRoles={};});

    testWidgets('the field opens the window, the box already chosen ticked; « Annuler » keeps it',(t) async {
      t.view..physicalSize=const Size(390,844)..devicePixelRatio=1;
      addTearDown(t.view.reset);
      myActorId='PCO-Web';
      final r=Remote(id:'rc-1',name:'Relais Maurepas',target:'b0b1b2b3b4b5b6b7b8b9',targetName:'Boîtier Maurepas',relays:[RemoteRelay.numbered(1)]);
      await t.pumpWidget(MaterialApp(home:RemoteEditPage(remote:r)));
      expect(find.byType(DropdownButtonFormField<String>),findsNothing);
      expect(find.text('Boîtier Maurepas'),findsOneWidget);
      await t.tap(find.byKey(const ValueKey('remote-node')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('remote-pick')),findsOneWidget);
      expect(find.byKey(const ValueKey('remote-pick-ticked')),findsOneWidget);
      await t.tap(find.byKey(const ValueKey('remote-pick-cancel')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('remote-pick')),findsNothing);
      expect(find.text('Boîtier Maurepas'),findsOneWidget);
    });
  });
}
