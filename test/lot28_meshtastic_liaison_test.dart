// SPDX-License-Identifier: MPL-2.0
// © SDUBOS Consulting et contributeurs SARCADE

// Lot 28, card « Module Meshtastic, sur le modèle de MeshCore », points 1,
// 4 and 8: link remembered, joined again, « Déconnecter », « Oublier »,
// pill, low battery alert, web bar with « Plus tard », Outils › Meshtastic,
// with a simulated module (messages of fixtures/meshtastic_frames.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/lora/lora_battery.dart';
import 'package:sarcade_app/src/features/lora/lora_link.dart';
import 'package:sarcade_app/src/features/map/link_weather_pill.dart';
import 'package:sarcade_app/src/features/meshtastic/meshtastic_hooks.dart';
import 'package:sarcade_app/src/features/meshtastic/meshtastic_link.dart';
import 'package:sarcade_app/src/features/meshtastic/meshtastic_link_card.dart';
import 'package:sarcade_app/src/features/meshtastic/meshtastic_protocol.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

import 'fixtures/meshtastic_frames.dart';

/// The simulated module answers want_config.
void feedConfig(MeshtasticLink link){
  for(final s in ['myInfo','metadata','loraConfig','channelPrimary','nodeMe','nodeRouter','nodeNoPos','configComplete']){
    link.onFrame(meshtasticSample(s));
  }
}

void main(){
  final link=MeshtasticLink.instance;
  setUp((){
    S.setLanguage('fr');
    link..testMode=true..resetForTest();
    link.testPrefs[meshtasticDeviceKey]='11:22:33';
    link.testPrefs[meshtasticNameKey]='Meshtastic_c3d4';
    LoraBatteryMonitor.instance.resetForTest();
    meshtasticBannerLater.value=false; meshtasticScreensOpen.value=0;
  });
  tearDown((){link..resetForTest()..testMode=false;LoraBatteryMonitor.instance.resetForTest();});

  test('a remembered module is joined at start, settings asked',() async {
    link.restoreForTest();
    await Future<void>.delayed(Duration.zero);
    expect(link.testJoins,1);
    expect(link.state,LoraLinkState.connected);
    await link.refresh();
    expect(link.testSent.single[0],0x18,reason:'ToRadio want_config_id');
  });

  test('« Déconnecter » keeps the module, no join at the next start; « Se connecter »; « Oublier »',() async {
    link.restoreForTest();
    await link.disconnect();
    expect(link.state,LoraLinkState.disconnected);
    expect(link.testPrefs[meshtasticOffKey],'1');
    final prefs=Map.of(link.testPrefs);
    link.resetForTest(); link.testPrefs.addAll(prefs);
    link.restoreForTest();
    expect(link.testJoins,0);
    expect(link.state,LoraLinkState.disconnected);
    await link.connect();
    expect(link.testJoins,1);
    expect(link.testPrefs[meshtasticOffKey],isNull);
    await link.forget();
    expect(link.remembered,isFalse);
    expect(link.testPrefs[meshtasticDeviceKey],isNull);
    expect(meshtasticPillTone(),isNull,reason:'no module: nothing in the pill');
  });

  test('simulated module: its node, the other nodes, the low battery alert',(){
    link.restoreForTest();
    feedConfig(link);
    expect(link.info.myNum,0xa1b2c3d4);
    expect(link.me?.longName,'F4ABC Mobile');
    expect(link.nodes.length,3);
    expect(link.others.map((n)=>n.name),['Relais Maurepas','Sans position'],reason:'heard most recently first, the module apart');
    final s=LoraBatteryMonitor.instance.stateOf('11:22:33');
    expect(s?.percent,18); expect(s?.level,LoraBatteryLevel.warning); expect(s?.box,LoraBox.meshtastic);
    expect(meshtasticPillTone(),'battery');
    // Telemetry of the module: 9 %, alert.
    link.onFrame(meshtasticSample('telemetryMe'));
    expect(LoraBatteryMonitor.instance.stateOf('11:22:33')?.level,LoraBatteryLevel.alert);
  });

  test('packets update the nodes: position, last heard, hops',(){
    link.restoreForTest();
    feedConfig(link);
    link.onFrame(meshtasticSample('positionPacket'));
    final n=link.node(0x12345678)!;
    expect(n.placed,isTrue); expect(n.lat,closeTo(48.7,1e-7)); expect(n.hops,1);
    expect(link.others.first.num,0x12345678,reason:'heard last');
    link.onFrame(meshtasticSample('encrypted'));
    expect(link.nodes.length,3,reason:'an encrypted packet adds nothing');
  });

  test('an unreadable message goes to the journal, nothing breaks',(){
    link.restoreForTest();
    link.onFrame(meshtasticSample('myInfo').sublist(0,4));
    expect(link.journal.last,contains('illisible'));
  });

  test('pill: tone and tooltip',(){
    expect(loraPillTone(LoraLinkState.connected),'ok');
    expect(loraPillTone(LoraLinkState.waitingClick),'wait');
    expect(loraPillTone(LoraLinkState.disconnected),'off');
    link.restoreForTest();
    expect(meshtasticPillTone(),'ok');
    expect(meshtasticPillTooltip(),'Module Meshtastic : connecté');
  });

  testWidgets('pill: the Meshtastic icon next to the MeshCore one',(t) async {
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Center(child:LinkWeatherPill(dot:Colors.green,linkTooltip:'',onLinks:(){},onWeather:(){},
      mesh:'ok',meshtastic:'battery')))));
    expect(find.byKey(const ValueKey('pill-mesh')),findsOneWidget);
    expect(find.byKey(const ValueKey('pill-meshtastic')),findsOneWidget);
    expect(find.byIcon(Icons.battery_alert),findsOneWidget);
  });

  testWidgets('web bar: « Plus tard » hides it; one bar while the screen is open',(t) async {
    link.restoreForTest();
    link.setStateForTest(LoraLinkState.waitingClick);
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:Column(children:[MeshtasticReconnectBanner()]))));
    expect(find.byKey(const ValueKey('meshtastic-reconnect-bar')),findsOneWidget);
    expect(find.text('Module Meshtastic : le navigateur demande un clic pour le reconnecter'),findsOneWidget);
    meshtasticScreensOpen.value=1;
    await t.pump();
    expect(find.byKey(const ValueKey('meshtastic-reconnect-bar')),findsNothing);
    meshtasticScreensOpen.value=0;
    await t.pump();
    await t.tap(find.byKey(const ValueKey('meshtastic-later')));
    await t.pump();
    expect(find.byKey(const ValueKey('meshtastic-reconnect-bar')),findsNothing);
  });

  test('web: « Reconnecter » that fails gives « module indisponible »',() async {
    link.restoreForTest();
    await link.reconnectInBrowser(pick:() async =>null);
    expect(link.state,LoraLinkState.unavailable);
    expect(loraStateText(link.state),'module indisponible');
  });

  testWidgets('Outils › Meshtastic: diagnostic of the module',(t) async {
    link.restoreForTest();
    feedConfig(link);
    await t.binding.setSurfaceSize(const Size(900,1400));
    addTearDown(()=>t.binding.setSurfaceSize(null));
    await t.pumpWidget(const MaterialApp(home:MeshtasticPage()));
    await t.pump();
    expect(find.text('F4ABC Mobile'),findsOneWidget);
    expect(find.text('Région et préréglage'),findsOneWidget);
    expect(find.text('EU_868 · LongFast'),findsOneWidget);
    expect(find.text('Canal principal'),findsOneWidget);
    expect(find.text('18 % · 3.62 V'),findsOneWidget);
    expect(find.text('Heltec V3'),findsOneWidget);
    expect(find.text('!a1b2c3d4'),findsOneWidget);
    expect(find.byKey(const ValueKey('meshtastic-disconnect')),findsOneWidget);
    expect(find.byKey(const ValueKey('lora-battery-thresholds')),findsOneWidget);
    expect(find.text('Nœuds connus (2)'),findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  test('tool item: Outils › Meshtastic, in the Core',(){
    final item=meshtasticToolItem(open:(_,_){});
    expect(item.id,'meshtastic');
    expect(item.title,'Meshtastic');
  });

  test('a node of the module in the samples is read as a Meshtastic node',(){
    expect(meshtasticBatteryReport(MeshtasticNode(1,battery:meshtasticPowered)).percent,100);
    expect(meshtasticBatteryReport(MeshtasticNode(1,voltage:3.6)).millivolts,3600);
    expect(meshtasticBatteryReport(MeshtasticNode(1)).percent,isNull);
  });
}
