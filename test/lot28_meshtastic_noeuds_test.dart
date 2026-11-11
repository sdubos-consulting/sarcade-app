// SPDX-License-Identifier: MPL-2.0
// © SDUBOS Consulting et contributeurs SARCADE

// Lot 28, card « Module Meshtastic, sur le modèle de MeshCore », points 2
// and 5: list of the nodes with search and filters, « Nœuds Meshtastic »
// layer (off by default), floating card, search of the map.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/meshtastic/meshtastic_link.dart';
import 'package:sarcade_app/src/features/meshtastic/meshtastic_nodes.dart';
import 'package:sarcade_app/src/features/meshtastic/meshtastic_protocol.dart';
import 'package:sarcade_app/src/features/search/map_search.dart';
import 'package:sarcade_app/src/features/search/map_search_sources.dart' show openFoundOnMap;
import 'package:sarcade_app/src/l10n/strings.dart';

import 'fixtures/meshtastic_frames.dart';

void main(){
  final link=MeshtasticLink.instance;
  final now=DateTime.utc(2026,11,4,18);
  MeshtasticNode node(int num,String long,{String short='',int? role,double? lat,double? lon,Duration ago=const Duration(minutes:5)})=>
    MeshtasticNode(num,longName:long,shortName:short,role:role,lat:lat,lon:lon,lastHeard:now.subtract(ago));
  final nodes=[
    node(0x0badcafe,'Relais Maurepas',short:'RMAU',role:2,lat:48.78,lon:1.95,ago:const Duration(hours:2)),
    node(0x12345678,'Équipe Élancourt',short:'EQ1',lat:48.77,lon:1.96),
    node(0x0000beef,'Tracker voiture',short:'TV',role:5,ago:const Duration(days:2)),
  ];

  setUp((){
    S.setLanguage('fr');
    link..testMode=true..resetForTest();
    link.testPrefs[meshtasticDeviceKey]='11:22:33';
    meshtasticSelected.value=null;
  });
  tearDown((){link..resetForTest()..testMode=false;meshtasticSelected.value=null;});

  test('search: names without accents, short name, id with or without « ! »',(){
    expect(filterMeshtasticNodes(nodes,query:'elancourt').single.shortName,'EQ1');
    expect(filterMeshtasticNodes(nodes,query:'rmau').single.longName,'Relais Maurepas');
    expect(filterMeshtasticNodes(nodes,query:'!0bad').single.num,0x0badcafe);
    expect(filterMeshtasticNodes(nodes,query:'1234').single.num,0x12345678);
    expect(filterMeshtasticNodes(nodes,query:'personne'),isEmpty);
  });

  test('filters: kind, with position; heard most recently first',(){
    expect(filterMeshtasticNodes(nodes).map((n)=>n.shortName),['EQ1','RMAU','TV']);
    expect(filterMeshtasticNodes(nodes,kind:MeshtasticKindFilter.router).single.shortName,'RMAU');
    expect(filterMeshtasticNodes(nodes,kind:MeshtasticKindFilter.tracker).single.shortName,'TV');
    expect(filterMeshtasticNodes(nodes,kind:MeshtasticKindFilter.client).single.shortName,'EQ1');
    expect(filterMeshtasticNodes(nodes,withPosition:true).length,2);
    expect(meshtasticNodesTitle(shown:1,total:3,filtered:true),'Nœuds connus (1 sur 3)');
  });

  test('grey when not heard for 24 h; subtitle',(){
    expect(meshtasticStale(nodes[2],now),isTrue);
    expect(meshtasticStale(nodes[1],now),isFalse);
    expect(meshtasticNodeSubtitle(nodes[2],now),'Tracker · TV · il y a 2 j · route inconnue · sans position');
  });

  testWidgets('list: field, filters, count',(t) async {
    await t.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:MeshtasticNodeList(nodes:nodes,
      tile:(n)=>ListTile(key:ValueKey('tile-${n.id}'),title:Text(n.name)))))));
    expect(find.text('Nœuds connus (3)'),findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('meshtastic-find')),'maurepas');
    await t.pump();
    expect(find.text('Nœuds connus (1 sur 3)'),findsOneWidget);
    expect(find.byKey(const ValueKey('tile-!0badcafe')),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('meshtastic-find-clear')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('meshtastic-find-tracker')));
    await t.pump();
    expect(find.byKey(const ValueKey('tile-!0000beef')),findsOneWidget);
    expect(find.byKey(const ValueKey('tile-!0badcafe')),findsNothing);
  });

  testWidgets('layer off by default; on: the placed nodes; a touch opens the card',(t) async {
    link.restoreForTest();
    for(final s in ['myInfo','nodeMe','nodeRouter','nodeNoPos']){link.onFrame(meshtasticSample(s));}
    final map=MapController();
    Widget app()=>MaterialApp(home:Scaffold(body:Stack(children:[
      FlutterMap(mapController:map,options:const MapOptions(initialCenter:LatLng(48.78,1.95),initialZoom:12),children:const [MeshtasticNodesLayer()]),
      MeshtasticNodeOverlay(map:map),
    ])));
    await t.pumpWidget(app());
    expect(link.showOnMap,isFalse);
    expect(find.byKey(const ValueKey('meshtastic-marker-!0badcafe')),findsNothing);
    await link.setShowOnMap(true);
    await t.pump();
    expect(find.byKey(const ValueKey('meshtastic-marker-!0badcafe')),findsOneWidget);
    expect(find.byKey(const ValueKey('meshtastic-marker-!a1b2c3d4')),findsNothing,reason:'the module itself is not drawn');
    expect(find.byKey(const ValueKey('meshtastic-marker-!12345678')),findsNothing,reason:'no position');
    await t.tap(find.byKey(const ValueKey('meshtastic-marker-!0badcafe')));
    await t.pump();
    expect(find.byKey(const ValueKey('meshtastic-card')),findsOneWidget);
    expect(find.text('Relais Maurepas'),findsOneWidget);
    expect(find.text('RMAU'),findsWidgets);
    expect(find.text('RAK4631'),findsOneWidget);
    expect(find.text('6.3 dB'),findsOneWidget);
    expect(find.text('2 saut(s)'),findsOneWidget);
    expect(find.text('secteur'),findsOneWidget);
    expect(find.textContaining('km'),findsOneWidget,reason:'distance from the module');
    await t.tap(find.byKey(const ValueKey('meshtastic-card-close')));
    await t.pump();
    expect(find.byKey(const ValueKey('meshtastic-card')),findsNothing);
  });

  test('search of the map: found by name or id, shown on the map or in the tool',() async {
    link.restoreForTest();
    for(final s in ['myInfo','nodeMe','nodeRouter','nodeNoPos']){link.onFrame(meshtasticSample(s));}
    final items=meshtasticSearchables(link.others,now);
    final r=searchLocal('maurepas',items).single;
    expect(r.kind,SearchKind.meshNode);
    expect(r.subtitle,startsWith('Meshtastic · Routeur'));
    expect(searchLocal('!0badca',items).single.ref,r.ref);
    expect(searchLocal('0badca',items).single.ref,r.ref);
    final map=MapController();
    MeshtasticNode? opened;
    expect(openMeshtasticFound(r,map:map,openInTool:(n)=>opened=n),isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(link.showOnMap,isTrue,reason:'the layer comes on');
    expect(meshtasticSelected.value,0x0badcafe);
    final o=searchLocal('sans position',items).single;
    expect(o.placed,isFalse);
    expect(openMeshtasticFound(o,map:map,openInTool:(n)=>opened=n),isTrue);
    expect(opened?.num,0x12345678,reason:'no position: Outils › Meshtastic on the node');
    // A MeshCore result is not taken, and MeshCore does not take this one.
    const meshCore=SearchResult(SearchKind.meshNode,'X','',LatLng(0,0),ref:'abcdef');
    expect(openMeshtasticFound(meshCore,map:map,openInTool:(_){}),isFalse);
    expect(openFoundOnMap(meshCore,map:map,openNodeInTool:(_){},nodes:const []),isTrue);
  });
}
