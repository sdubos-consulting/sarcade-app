// Lot 25, card « Boîtiers LoRa (MeshCore, puis Meshtastic) : alerte de
// batterie faible » (choices validated on 3 Nov 2026, 10 h 53), point 9:
// levels 25, 19, 9, 4 %, recharge, remote relay.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/lora/lora_battery.dart';
import 'package:sarcade_app/src/features/lora/lora_battery_view.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  late LoraBatteryMonitor m;
  late Map<String,String?> prefs;
  late List<String> notified;
  setUp((){
    S.setLanguage('fr');
    prefs={}; notified=[];
    m=LoraBatteryMonitor()
      ..read=((k)=>prefs[k])
      ..save=((k,v) async {prefs[k]=v;})
      ..notify=((t,b)=>notified.add(b));
  });

  void mc(int p)=>m.report(id:'AA',name:'T1000',box:LoraBox.meshcore,percent:p);

  test('25, 19, 9, 4 %: warning, alert with a notification, reminder 5 % lower',(){
    mc(25);
    expect(m.low,isEmpty);
    mc(19);
    expect(m.stateOf('AA')!.level,LoraBatteryLevel.warning);
    expect(loraBatteryText(m.low.single),'Boîtier LoRa : batterie faible (19 %)');
    expect(notified,isEmpty,reason:'orange bar only');
    mc(9);
    expect(m.stateOf('AA')!.level,LoraBatteryLevel.alert);
    expect(notified,['Boîtier LoRa : batterie faible (9 %)']);
    mc(8);
    expect(notified.length,1,reason:'once per threshold');
    mc(4);
    expect(notified.length,2,reason:'reminder: 5 % lower');
    expect(notified.last,'Boîtier LoRa : batterie faible (4 %)');
    mc(3);
    expect(notified.length,2);
  });

  test('recharge: the alert goes by itself at the threshold + 5 %',(){
    mc(9);
    mc(12);
    expect(m.stateOf('AA')!.level,LoraBatteryLevel.alert,reason:'under 10 + 5');
    mc(15);
    expect(m.stateOf('AA')!.level,LoraBatteryLevel.warning);
    mc(22);
    expect(m.stateOf('AA')!.level,LoraBatteryLevel.warning,reason:'under 20 + 5');
    mc(25);
    expect(m.stateOf('AA')!.level,LoraBatteryLevel.ok);
    expect(m.low,isEmpty);
    mc(9);
    expect(notified.length,2,reason:'a new discharge is told again');
  });

  // Card « Diagnostic : modules LoRa… », choice 9 (10 Nov 2026): the
  // discharge curve of a lithium cell instead of the straight line.
  test('percentage from the voltage (lithium discharge curve)',(){
    expect(loraBatteryPercent(3000),0);
    expect(loraBatteryPercent(3100),0);
    expect(loraBatteryPercent(4200),100);
    expect(loraBatteryPercent(4190),100);
    expect(loraBatteryPercent(3800),60);
    expect(loraBatteryPercent(3720),50);
    expect(loraBatteryPercent(3600),37);
    expect(loraBatteryPercent(4100),94);
    expect(loraBatteryPercent(2800),0);
    expect(loraBatteryPercent(4350),100);
    m.report(id:'AA',name:'T1000',box:LoraBox.meshcore,millivolts:3400);
    expect(m.stateOf('AA')!.percent,18);
    expect(m.stateOf('AA')!.level,LoraBatteryLevel.warning);
  });

  test('remote relay: same alert with the name of the relay',(){
    m.report(id:'relay-1',name:'Septeuil',box:LoraBox.relay,percent:8);
    expect(notified,['Relais Septeuil : batterie faible (8 %)']);
    mc(18);
    expect(m.low.first.box,LoraBox.relay,reason:'the worst first');
  });

  test('Meshtastic later: same watch',(){
    m.report(id:'MT',name:'Heltec',box:LoraBox.meshtastic,percent:9);
    expect(m.stateOf('MT')!.level,LoraBatteryLevel.alert);
  });

  test('thresholds set in Outils › MeshCore, kept on the device',() async {
    expect(m.thresholds,(warn:20,alert:10));
    await m.setThresholds(warn:30,alert:15);
    expect(prefs[loraBatteryWarnKey],'30');
    expect(prefs[loraBatteryAlertKey],'15');
    mc(28);
    expect(m.stateOf('AA')!.level,LoraBatteryLevel.warning);
    expect(loraBatteryThresholds('10','20'),(warn:10,alert:9),reason:'alert always under the warning');
    expect(loraBatteryThresholds('x',null),(warn:20,alert:10));
  });

  test('pill orange with a battery, Liaisons line with the level',(){
    expect(meshCorePillToneWithBattery('ok','AA',monitor:m),'ok');
    mc(18);
    expect(meshCorePillToneWithBattery('ok','AA',monitor:m),'battery');
    expect(meshCorePillToneWithBattery('wait','AA',monitor:m),'wait');
    expect(meshCorePillToneWithBattery('ok',null,monitor:m),'ok');
    expect(loraBatteryLine(18),'batterie 18 %');
    m.forget('AA');
    expect(meshCorePillToneWithBattery('ok','AA',monitor:m),'ok');
  });

  testWidgets('bar orange at the warning, red at the alert',(t) async {
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Column(children:[LoraBatteryBanner(monitor:m)]))));
    expect(find.byKey(const ValueKey('lora-battery-warning')),findsNothing);
    mc(18);
    await t.pump();
    expect(find.byKey(const ValueKey('lora-battery-warning')),findsOneWidget);
    expect(find.text('Boîtier LoRa : batterie faible (18 %)'),findsOneWidget);
    mc(9);
    await t.pump();
    expect(find.byKey(const ValueKey('lora-battery-alert')),findsOneWidget);
    mc(40);
    await t.pump();
    expect(find.byKey(const ValueKey('lora-battery-alert')),findsNothing);
  });

  test('English',(){
    S.setLanguage('en');
    mc(18);
    expect(loraBatteryText(m.low.single),'LoRa box: low battery (18 %)');
  });
}
