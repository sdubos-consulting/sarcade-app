// Lot 19, card « MeshCore : champ de recherche dans la liste des nœuds »
// (validated on 1 Nov 2026, 21 h 49): search by name and start of the key,
// accents and capitals ignored, filters by kind and « avec position », the
// most recent first, the count following the filter, the cross.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_node_list.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_protocol.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

MeshCoreContact node(String key,String name,int type,{int advert=0,double? lat,double? lon})=>MeshCoreContact(key:key,type:type,name:name,
  lastAdvert:advert==0?null:DateTime.fromMillisecondsSinceEpoch(advert*1000,isUtc:true),lat:lat,lon:lon);

final nodes=[
  node('a1b2c3d4e5','Relais Élancourt',2,advert:300,lat:48.78,lon:1.95),
  node('f0e1d2c3b4','Stéphane mobile',1,advert:500),
  node('0011223344','Salon ADRASEC 78',3,advert:100),
  node('a1ffee0000','Relais Septeuil',2,advert:400),
  node('9988776655','Capteur météo',4,advert:200,lat:48.9,lon:1.7),
];

void main(){
  setUp(()=>S.setLanguage('fr'));

  group('filter',(){
    test('by name, accents and capitals ignored',(){
      expect(filterMeshCoreNodes(nodes,query:'elancourt').map((n)=>n.name),['Relais Élancourt']);
      expect(filterMeshCoreNodes(nodes,query:'STEPHANE').single.name,'Stéphane mobile');
      expect(filterMeshCoreNodes(nodes,query:'relais sept').single.name,'Relais Septeuil');
      expect(filterMeshCoreNodes(nodes,query:'brest'),isEmpty);
    });

    test('by start of the public key, not its middle',(){
      expect(filterMeshCoreNodes(nodes,query:'A1').map((n)=>n.name),['Relais Septeuil','Relais Élancourt']);
      expect(filterMeshCoreNodes(nodes,query:'a1b2').single.name,'Relais Élancourt');
      expect(filterMeshCoreNodes(nodes,query:'c3d4'),isEmpty);
    });

    test('by kind and with position; heard most recently first',(){
      expect(filterMeshCoreNodes(nodes).map((n)=>n.name),
        ['Stéphane mobile','Relais Septeuil','Relais Élancourt','Capteur météo','Salon ADRASEC 78']);
      expect(filterMeshCoreNodes(nodes,kind:MeshCoreKindFilter.repeater).map((n)=>n.name),['Relais Septeuil','Relais Élancourt']);
      expect(filterMeshCoreNodes(nodes,kind:MeshCoreKindFilter.companion).single.name,'Stéphane mobile');
      expect(filterMeshCoreNodes(nodes,kind:MeshCoreKindFilter.room).single.name,'Salon ADRASEC 78');
      expect(filterMeshCoreNodes(nodes,withPosition:true).map((n)=>n.name),['Relais Élancourt','Capteur météo']);
      expect(filterMeshCoreNodes(nodes,kind:MeshCoreKindFilter.repeater,withPosition:true).single.name,'Relais Élancourt');
    });

    test('the count follows the filter',(){
      expect(meshCoreNodesTitle(shown:5,total:48,filtered:true),'Nœuds connus (5 sur 48)');
      expect(meshCoreNodesTitle(shown:48,total:48,filtered:false),'Nœuds connus (48)');
    });
  });

  testWidgets('the field, the filters, the count and the cross',(t) async {
    await t.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:MeshCoreNodeList(nodes:nodes,
      tile:(n)=>ListTile(key:ValueKey('tile-${n.shortKey}'),title:Text(n.name)))))));
    expect(find.text('Nœuds connus (5)'),findsOneWidget);
    expect(find.byType(ListTile),findsNWidgets(5));

    await t.enterText(find.byKey(const ValueKey('mesh-find')),'relais');
    await t.pump();
    expect(find.text('Nœuds connus (2 sur 5)'),findsOneWidget);
    expect(find.byType(ListTile),findsNWidgets(2));

    await t.tap(find.byKey(const ValueKey('mesh-find-clear')));
    await t.pump();
    expect(find.text('Nœuds connus (5)'),findsOneWidget);
    expect(find.byKey(const ValueKey('mesh-find-clear')),findsNothing);

    await t.tap(find.byKey(const ValueKey('mesh-find-room')));
    await t.pump();
    expect(find.text('Nœuds connus (1 sur 5)'),findsOneWidget);
    expect(find.text('Salon ADRASEC 78'),findsOneWidget);

    await t.tap(find.byKey(const ValueKey('mesh-find-position')));
    await t.pump();
    expect(find.byKey(const ValueKey('mesh-find-none')),findsOneWidget);
  });

  testWidgets('opened on a node: its name already in the field',(t) async {
    await t.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:MeshCoreNodeList(nodes:nodes,initialQuery:'Capteur',
      tile:(n)=>ListTile(title:Text(n.name)))))));
    expect(find.text('Nœuds connus (1 sur 5)'),findsOneWidget);
    expect(find.text('Capteur météo'),findsNWidgets(1));
  });
}
