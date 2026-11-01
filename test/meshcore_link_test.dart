// MeshCore as a transport (lot D, 1 Nov 2026): contacts of the module, the
// order of the nodes, the retry delays and the pill.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/link_weather_pill.dart';
import 'package:sarcade_app/src/features/settings/diagnostics_panel.dart' show meshCoreDiagLine;
import 'package:sarcade_app/src/features/meshcore/meshcore_link.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_page.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_protocol.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

Uint8List contact({int type=2,int path=-1,String name='Relais Rambouillet',int advert=1793491200,int lat=48644000,int lon=1830000}){
  final f=Uint8List(148)..[0]=0x03;
  for(var i=0;i<32;i++){f[1+i]=i;}
  f[33]=type; f[34]=0; f[35]=path&0xFF;
  f.setRange(100,100+name.length,ascii.encode(name));
  final d=f.buffer.asByteData();
  d.setUint32(132,advert,Endian.little); d.setInt32(136,lat,Endian.little); d.setInt32(140,lon,Endian.little);
  return f;
}

void main(){
  setUp(()=>S.setLanguage('fr'));

  test('contacts command and frame kinds',(){
    expect(contactsQuery(),[0x04]);
    final i=MeshCoreInfo();
    expect(readMeshCoreFrame(Uint8List.fromList([0x02,3,0,0,0]),i),'contactsStart');
    expect(readMeshCoreFrame(contact(),i),'contact');
    expect(readMeshCoreFrame(Uint8List.fromList([0x04,0,0,0,0]),i),'contactsEnd');
    expect(readMeshCoreFrame(Uint8List.fromList([0x80,1,2]),i),'advert');
    expect(readMeshCoreFrame(Uint8List.fromList([0x8A,1,2]),i),'advert');
  });

  test('CONTACT: key, kind, hops, name, last advert, position',(){
    final c=readMeshCoreContact(contact())!;
    expect(c.shortKey,'00010203');
    expect(c.kind,'repeater');
    expect(c.hops,isNull,reason:'-1: route not known yet');
    expect(c.name,'Relais Rambouillet');
    expect(c.lastAdvert,DateTime.utc(2026,11,1));
    expect(c.lat,closeTo(48.644,1e-6)); expect(c.lon,closeTo(1.83,1e-6));
    final d=readMeshCoreContact(contact(type:1,path:2,lat:0,lon:0,advert:0))!;
    expect(d.kind,'companion'); expect(d.hops,2); expect(d.lat,isNull); expect(d.lastAdvert,isNull);
    expect(readMeshCoreContact(Uint8List(20)..[0]=0x03),isNull);
  });

  test('nodes heard most recently first',(){
    final a=readMeshCoreContact(contact(name:'B',advert:100))!, b=readMeshCoreContact(contact(name:'A',advert:200))!;
    final c=readMeshCoreContact(contact(name:'C',advert:0))!;
    expect(sortedContacts([a,c,b]).map((x)=>x.name),['A','B','C']);
  });

  test('retries 5 s, 15 s, 30 s, then every minute; pill tones',(){
    expect([for(var i=0;i<6;i++)meshCoreRetryDelay(i).inSeconds],[5,15,30,60,60,60]);
    expect(meshCorePillTone(MeshCoreState.none),'off');
    expect(meshCorePillTone(MeshCoreState.connected),'ok');
    expect(meshCorePillTone(MeshCoreState.reconnecting),'wait');
    expect(meshCorePillTone(MeshCoreState.failed),'bad');
  });

  test('hops and ages in words',(){
    expect(meshCoreHops(null),'route inconnue');
    expect(meshCoreHops(0),'direct');
    expect(meshCoreHops(3),'3 saut(s)');
    final now=DateTime(2026,11,1,12);
    expect(meshCoreAge(null,now),'jamais');
    expect(meshCoreAge(now.subtract(const Duration(seconds:20)),now),'à l’instant');
    expect(meshCoreAge(now.subtract(const Duration(minutes:7)),now),'il y a 7 min');
    expect(meshCoreAge(now.subtract(const Duration(hours:5)),now),'il y a 5 h');
    expect(meshCoreAge(now.subtract(const Duration(days:2)),now),'il y a 2 j');
  });

  testWidgets('the pill shows the module only when one is remembered',(t) async {
    Widget pill(String? mesh)=>MaterialApp(home:Scaffold(body:Center(child:LinkWeatherPill(dot:Colors.green,linkTooltip:'x',
      onLinks:(){},onWeather:(){},mesh:mesh))));
    await t.pumpWidget(pill(null));
    expect(find.byKey(const ValueKey('pill-mesh')),findsNothing);
    await t.pumpWidget(pill('ok'));
    expect(find.byKey(const ValueKey('pill-mesh')),findsOneWidget);
  });

  test('a module out of reach in words, the technical error in the journal only (8 h 15)',(){
    expect(meshCoreProblem(state:MeshCoreState.reconnecting,trying:false,error:'TimeoutException after 0:00:20',retryIn:const Duration(seconds:30)),
      'Module injoignable : éteint ou hors de portée. Nouvel essai dans 30 s.');
    expect(meshCoreProblem(state:MeshCoreState.reconnecting,trying:true,error:'x',retryIn:null),isNull,reason:'while trying');
    expect(meshCoreProblem(state:MeshCoreState.connected,trying:false,error:'x'),isNull);
    expect(S.t('mesh.help'),contains('123456'));
  });

  test('one line in Liaisons (8 h 17)',(){
    final l=meshCoreDiagLine('Liaisons',MeshCoreLink.instance);
    expect(l.label,'MeshCore'); expect(l.value,'aucun module'); expect(l.state,isNull);
  });
}
