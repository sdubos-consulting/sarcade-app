// Card « Diagnostic : modules LoRa (MeshCore, Meshtastic) injoignables, lien
// vers Outils et reconnexion économe » (validated on 10 Nov 2026, choices 1
// to 10): box off → orange, then grey « hors de portée » after 5 minutes,
// out of « À vérifier »; a try every 5 minutes; « Déconnecter » from the
// Diagnostic stops the tries; Bluetooth off → grey; back → joined again
// without any action; battery percentage shown and hidden.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/features/lora/lora_battery.dart';
import 'package:sarcade_app/src/features/lora/lora_battery_view.dart';
import 'package:sarcade_app/src/features/lora/lora_link.dart';
import 'package:sarcade_app/src/features/lora/lora_watch.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_link.dart';
import 'package:sarcade_app/src/features/meshtastic/meshtastic_link.dart';
import 'package:sarcade_app/src/features/settings/diagnostics_panel.dart';
import 'package:sarcade_app/src/features/settings/diagnostics_reach.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';
import 'package:universal_ble/universal_ble.dart' show AvailabilityState;

const server='https://sarcade.example.org';

void main(){
  final mc=MeshCoreLink.instance, mt=MeshtasticLink.instance, watch=LoraWatch.instance;
  late DateTime t;

  setUp((){
    S.setLanguage('fr');
    watch.resetForTest(); watch.testMode=true; watch.passiveOverride=false;
    mc.resetForTest(); mc.testMode=true;
    mt.resetForTest(); mt.testMode=true;
    t=DateTime(2026,11,10,9,15);
    mc.now=()=>t; mt.now=()=>t;
    mc.testPrefs[meshCoreDeviceKey]='AA:BB:CC:DD:EE:FF'; mc.testPrefs[meshCoreNameKey]='MeshCore-FR78 T1000';
    LoraBatteryMonitor.instance.resetForTest();
  });
  tearDown((){mc.resetForTest();mt.resetForTest();watch.resetForTest();LoraBatteryMonitor.instance.resetForTest();});

  /// Lets the next try run, the clock moving with it.
  Future<void> next(WidgetTester tester,MeshCoreLink l) async {
    final wait=l.retryIn!; t=t.add(wait); await tester.pump(wait);
  }

  group('pure rules',(){
    test('orange for 5 minutes, then grey every 5 minutes; red only for a real fault',(){
      expect(loraAfterFailure(attempt:0,failing:Duration.zero),(state:LoraLinkState.reconnecting,wait:const Duration(seconds:5)));
      expect(loraAfterFailure(attempt:5,failing:const Duration(minutes:4,seconds:59)),(state:LoraLinkState.reconnecting,wait:const Duration(minutes:1)));
      expect(loraAfterFailure(attempt:6,failing:const Duration(minutes:5)),(state:LoraLinkState.outOfReach,wait:const Duration(minutes:5)));
      expect(loraAfterFailure(attempt:0,failing:Duration.zero,manual:true).state,LoraLinkState.failed);
      expect(loraAfterFailure(attempt:0,failing:Duration.zero,joined:true).state,LoraLinkState.failed);
      expect(loraPillTone(LoraLinkState.outOfReach),'off');
      expect(loraPillTone(LoraLinkState.bluetoothOff),'off');
      expect(loraTryingState(before:LoraLinkState.outOfReach,attempt:7),LoraLinkState.outOfReach,reason:'no orange flash every 5 minutes');
      expect(loraTryingState(before:LoraLinkState.reconnecting,attempt:2),LoraLinkState.reconnecting);
      expect(loraProblem(state:LoraLinkState.outOfReach,trying:false,error:'x'),'Module injoignable : éteint ou hors de portée. Nouvel essai toutes les 5 min.');
    });

    test('lithium discharge curve (choice 9): known voltages',(){
      expect(loraBatteryPercent(4200),100);
      expect(loraBatteryPercent(4050),90);
      expect(loraBatteryPercent(3890),70);
      expect(loraBatteryPercent(3720),50);
      expect(loraBatteryPercent(3530),30);
      expect(loraBatteryPercent(3300),10);
      expect(loraBatteryPercent(3200),5);
      expect(loraBatteryPercent(3000),0);
    });
  });

  testWidgets('box off: orange, then grey « hors de portée » after 5 minutes, out of « À vérifier », a try every 5 minutes',(tester) async {
    mc.testReachable=false;
    mc.restoreForTest();
    expect(mc.state,LoraLinkState.reconnecting);
    var l=meshCoreDiagLine('Liaisons',mc,now:t);
    expect(l.state,'orange');
    expect(diagnosticProblems([l]),hasLength(1));
    while(mc.state!=LoraLinkState.outOfReach){
      expect(t.difference(DateTime(2026,11,10,9,15)),lessThan(const Duration(minutes:5)),reason:'orange during 5 minutes at most');
      await next(tester,mc);
      if(mc.state!=LoraLinkState.outOfReach)expect(mc.state,LoraLinkState.reconnecting);
    }
    l=meshCoreDiagLine('Liaisons',mc,now:t);
    expect(l.state,'off');
    expect(l.value,'MeshCore-FR78 T1000 · hors de portée depuis 09:15 · nouvel essai toutes les 5 min');
    expect(diagnosticProblems([l]),isEmpty);
    expect(summaryProblems([l]).problems,isEmpty);
    expect(mc.retryIn,const Duration(minutes:5));
    final joins=mc.testJoins;
    await next(tester,mc);
    expect(mc.testJoins,joins+1);
    expect(mc.state,LoraLinkState.outOfReach);
    await tester.pump(const Duration(minutes:4,seconds:59));
    expect(mc.testJoins,joins+1,reason:'nothing between two tries');
    // Box switched on again: joined at the next try, without any action.
    mc.testReachable=true;
    await tester.pump(const Duration(seconds:1));
    expect(mc.state,LoraLinkState.connected);
    expect(mc.failingSince,isNull);
    expect(meshCoreDiagLine('Liaisons',mc).state,'green');
  });

  testWidgets('Android, Windows: the module heard is joined at once (choice 3)',(tester) async {
    watch.passiveOverride=true;
    mc.testReachable=false;
    mc.restoreForTest();
    while(mc.state!=LoraLinkState.outOfReach){await next(tester,mc);}
    expect(watch.listening,isTrue);
    expect(watch.testScans,greaterThan(0));
    mc.testReachable=true;
    watch.advert('aa:bb:cc:dd:ee:ff');
    expect(mc.state,LoraLinkState.connected);
    expect(watch.listening,isFalse,reason:'no scan once joined');
    expect(mc.journal.any((j)=>j.contains('module entendu')),isTrue);
  });

  testWidgets('iPhone: no listening, tries every 5 minutes only',(tester) async {
    mc.testReachable=false;
    mc.restoreForTest();
    while(mc.state!=LoraLinkState.outOfReach){await next(tester,mc);}
    expect(watch.listening,isFalse);
    expect(watch.testScans,0);
    await tester.pump(const Duration(minutes:5));
    mc.resetForTest();
  });

  testWidgets('« Déconnecter » stops the tries; written in the journal',(tester) async {
    mc.testReachable=false;
    mc.restoreForTest();
    while(mc.state!=LoraLinkState.outOfReach){await next(tester,mc);}
    final joins=mc.testJoins;
    await mc.disconnect(from:'Diagnostic');
    expect(mc.state,LoraLinkState.disconnected);
    expect(mc.journal.last,endsWith('déconnecté à la demande (Diagnostic)'));
    await tester.pump(const Duration(minutes:30));
    expect(mc.testJoins,joins,reason:'no try once disconnected');
    expect(meshCoreDiagLine('Liaisons',mc).state,'off');
  });

  testWidgets('Bluetooth off: grey, no try; back: joined again without any action (choice 4)',(tester) async {
    mc.restoreForTest();
    expect(mc.state,LoraLinkState.connected);
    watch.availability(AvailabilityState.poweredOff);
    expect(mc.state,LoraLinkState.bluetoothOff);
    final l=meshCoreDiagLine('Liaisons',mc);
    expect(l.state,'off');
    expect(l.value,'MeshCore-FR78 T1000 · Bluetooth du téléphone coupé');
    final joins=mc.testJoins;
    await mc.connect();
    expect(mc.testJoins,joins,reason:'no try with the Bluetooth off');
    expect(mc.state,LoraLinkState.bluetoothOff);
    watch.availability(AvailabilityState.poweredOn);
    expect(mc.state,LoraLinkState.connected);
  });

  testWidgets('red only for a real fault: connection asked by hand, or joined but silent (choice 5)',(tester) async {
    mc.testReachable=false;
    mc.testPrefs[meshCoreOffKey]='1';
    mc.restoreForTest();
    expect(mc.state,LoraLinkState.disconnected);
    await mc.connect();
    expect(mc.state,LoraLinkState.failed);
    expect(meshCoreDiagLine('Liaisons',mc).state,'red');
    mc.testReachable=true;
    await next(tester,mc);
    expect(mc.state,LoraLinkState.connected);
    mc.noAnswer=true;
    final l=meshCoreDiagLine('Liaisons',mc);
    expect(l.state,'red');
    expect(l.value,'MeshCore-FR78 T1000 · joint, ne répond pas');
  });

  testWidgets('Meshtastic: same rules',(tester) async {
    mt.testPrefs[meshtasticDeviceKey]='11:22:33:44:55:66'; mt.testPrefs[meshtasticNameKey]='Meshtastic_ab12';
    mt.testReachable=false;
    mt.restoreForTest();
    expect(mt.state,LoraLinkState.reconnecting);
    while(mt.state!=LoraLinkState.outOfReach){final w=mt.retryIn!;t=t.add(w);await tester.pump(w);}
    final l=meshtasticDiagLine('Liaisons',mt,now:t);
    expect(l.label,'Meshtastic');
    expect(l.state,'off');
    expect(l.value,startsWith('Meshtastic_ab12 · hors de portée depuis 09:15'));
    await mt.disconnect(from:'Diagnostic');
    expect(mt.journal.last,endsWith('(Diagnostic)'));
  });

  group('battery of the boxes (choices 8 and 10)',(){
    late Map<String,String?> prefs;
    setUp((){
      prefs={};
      LoraBatteryMonitor.instance..read=((k)=>prefs[k])..save=((k,v) async {prefs[k]=v;})..notify=((_,_){});
    });

    test('percentage always on the line, hidden by the setting, low battery always told',() async {
      mc.restoreForTest();
      final m=LoraBatteryMonitor.instance;
      m.report(id:'AA:BB:CC:DD:EE:FF',name:'T1000',box:LoraBox.meshcore,millivolts:3950);
      expect(meshCoreDiagLine('Liaisons',mc).value,'MeshCore-FR78 T1000 · connecté · batterie 76 %');
      expect(m.percentShown,isTrue,reason:'shown by default');
      await m.setPercentShown(false);
      expect(prefs[loraBatteryShownKey],'0');
      expect(meshCoreDiagLine('Liaisons',mc).value,'MeshCore-FR78 T1000 · connecté');
      expect(meshCoreDiagLine('Liaisons',mc).state,'green');
      // Low battery: the alert stays, the level with it.
      m.report(id:'AA:BB:CC:DD:EE:FF',name:'T1000',box:LoraBox.meshcore,millivolts:3400);
      expect(m.low,hasLength(1));
      expect(meshCoreDiagLine('Liaisons',mc).value,'MeshCore-FR78 T1000 · connecté · batterie 18 %');
      expect(meshCoreDiagLine('Liaisons',mc).state,'orange');
      await m.setPercentShown(true);
      expect(prefs[loraBatteryShownKey],isNull);
    });

    testWidgets('« Afficher le pourcentage de batterie » in Outils',(tester) async {
      await tester.pumpWidget(const MaterialApp(home:Scaffold(body:LoraBatteryShownTile())));
      expect(find.text('Pourcentage de batterie'),findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lora-battery-shown')));
      await tester.pump();
      expect(LoraBatteryMonitor.instance.percentShown,isFalse);
    });
  });

  testWidgets('Diagnostic: grey line with « Déconnecter » and « Ouvrir MeshCore », not in « À vérifier »',(tester) async {
    mc.testReachable=false;
    mc.restoreForTest();
    while(mc.state!=LoraLinkState.outOfReach){await next(tester,mc);}
    final api=SarcadeApi(baseUrl:server,client:MockClient((r) async {
      if(r.url.path.endsWith('/diagnostics/client'))return http.Response('{"ip":"203.0.113.7"}',200);
      return http.Response('{}',404);
    }));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:DiagnosticsPanel(api:api,server:server,eventId:'ev-1')))));
    for(var i=0;i<20&&find.byKey(const ValueKey('diag-toggle-links')).evaluate().isEmpty;i++){
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));
      await tester.pump();
    }
    // « À vérifier » (the itinerary of this fake server) without the module.
    expect(find.descendant(of:find.byKey(const ValueKey('diag-problems')),matching:find.text('MeshCore')),findsNothing,
      reason:'a module out of reach is not counted');
    expect(find.text('À vérifier (1)'),findsOneWidget);
    if(find.byKey(const ValueKey('diag-lora-disconnect-meshcore')).evaluate().isEmpty){
      await tester.tap(find.byKey(const ValueKey('diag-toggle-links')));
      await tester.pump();
    }
    expect(find.textContaining('hors de portée depuis'),findsOneWidget);
    expect(find.byKey(const ValueKey('diag-open-meshcore')),findsOneWidget);
    expect(find.byKey(const ValueKey('diag-open-meshtastic')),findsOneWidget,reason:'link to Outils › Meshtastic');
    await tester.ensureVisible(find.byKey(const ValueKey('diag-lora-disconnect-meshcore')));
    await tester.tap(find.byKey(const ValueKey('diag-lora-disconnect-meshcore')));
    await tester.pump();
    expect(mc.state,LoraLinkState.disconnected);
    expect(mc.journal.last,endsWith('(Diagnostic)'));
    await tester.pump(const Duration(seconds:3));
    expect(find.byKey(const ValueKey('diag-lora-connect-meshcore')),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
