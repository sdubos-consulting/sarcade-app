// Lot 19, card « MeshCore : bouton « Déconnecter » le module » (validated
// on 1 Nov 2026, 21 h 44): « Déconnecter » cuts the link and keeps the
// module, no automatic join even at the next start, « Se connecter » joins
// it again, « Oublier ce module » apart, grey icon in the pill.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/link_weather_pill.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_link.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_link_card.dart';
import 'package:sarcade_app/src/features/settings/diagnostics_panel.dart' show meshCoreDiagLine;
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  final link=MeshCoreLink.instance;
  setUp((){
    S.setLanguage('fr');
    link..testMode=true..resetForTest();
    link.testPrefs[meshCoreDeviceKey]='AA:BB:CC';
    link.testPrefs[meshCoreNameKey]='MeshCore-F4ABC';
  });
  tearDown((){link..resetForTest()..testMode=false;});

  test('a remembered module is joined at start',() async {
    link.restoreForTest();
    await Future<void>.delayed(Duration.zero);
    expect(link.testJoins,1);
    expect(link.state,MeshCoreState.connected);
  });

  test('« Déconnecter »: module kept, no automatic join, even at the next start',() async {
    link.restoreForTest();
    await Future<void>.delayed(Duration.zero);
    await link.disconnect();
    expect(link.state,MeshCoreState.disconnected);
    expect(link.remembered,isTrue,reason:'the module stays remembered');
    expect(link.testPrefs[meshCoreOffKey],'1');
    expect(link.testPrefs[meshCoreDeviceKey],'AA:BB:CC');

    // Next start of the application.
    final prefs=Map.of(link.testPrefs);
    link.resetForTest(); link.testPrefs.addAll(prefs);
    link.restoreForTest();
    await Future<void>.delayed(Duration.zero);
    expect(link.testJoins,0,reason:'no automatic join');
    expect(link.state,MeshCoreState.disconnected);
    expect(link.remembered,isTrue);
  });

  test('« Se connecter »: joined again, automatic link back',() async {
    link.testPrefs[meshCoreOffKey]='1';
    link.restoreForTest();
    expect(link.testJoins,0);
    await link.connect();
    expect(link.testJoins,1);
    expect(link.state,MeshCoreState.connected);
    expect(link.testPrefs[meshCoreOffKey],isNull);
  });

  test('« Oublier ce module » stays apart: the module is forgotten',() async {
    link.restoreForTest();
    await link.disconnect();
    await link.forget();
    expect(link.remembered,isFalse);
    expect(link.state,MeshCoreState.none);
    expect(link.testPrefs[meshCoreDeviceKey],isNull);
    expect(link.testPrefs[meshCoreOffKey],isNull);
  });

  test('grey pill, state in words, no error text, line of Liaisons',() async {
    expect(meshCorePillTone(MeshCoreState.disconnected),'off');
    expect(LinkWeatherPill.meshColor('off',const ColorScheme.light()),isNot(const ColorScheme.light().error));
    expect(meshCoreStateText(MeshCoreState.disconnected),'déconnecté');
    expect(meshCoreProblem(state:MeshCoreState.disconnected,trying:false,error:'x'),isNull);
    link.testPrefs[meshCoreOffKey]='1';
    link.restoreForTest();
    final l=meshCoreDiagLine('Liaisons',link);
    expect(l.value,'MeshCore-F4ABC · déconnecté');
    expect(l.state,'off');
  });

  testWidgets('« Déconnecter » then « Se connecter » on screen',(t) async {
    link.restoreForTest();
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:Center(child:MeshCoreConnectButton()))));
    expect(find.text('Déconnecter'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('meshcore-disconnect')));
    await t.pump();
    expect(link.state,MeshCoreState.disconnected);
    expect(find.byKey(const ValueKey('meshcore-off')),findsOneWidget);
    expect(find.text('Se connecter'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('meshcore-connect')));
    await t.pump();
    expect(link.state,MeshCoreState.connected);
    expect(find.text('Déconnecter'),findsOneWidget);
  });
}
