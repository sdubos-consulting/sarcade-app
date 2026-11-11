// Lot 17, card « Application web : se connecter à un module MeshCore »
// (choices validated on 1 Nov 2026, 12 h 04): Chrome and Edge connect
// through Web Bluetooth; another browser shows a clear message; the
// browser asks for a click to join the module again.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_link.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_link_card.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/platform/platform_services.dart' show webBluetoothAvailable;

void main(){
  setUp(()=>S.setLanguage('fr'));

  testWidgets('browser without Web Bluetooth: the message instead of the button',(t) async {
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:MeshCoreWebConnect(bluetooth:false))));
    expect(find.text('Utilisez Chrome ou Edge, ou l’application'),findsOneWidget);
    expect(find.byKey(const ValueKey('meshcore-web-connect')),findsNothing);
  });

  testWidgets('Chrome or Edge: « Connecter un module MeshCore » opens the choice',(t) async {
    var asked=0;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:MeshCoreWebConnect(bluetooth:true,onConnect:()=>asked++))));
    expect(find.text('Connecter un module MeshCore'),findsOneWidget);
    expect(find.byKey(const ValueKey('meshcore-web-unsupported')),findsNothing);
    await t.tap(find.byKey(const ValueKey('meshcore-web-connect')));
    expect(asked,1);
  });

  testWidgets('« Reconnecter le module » in one click',(t) async {
    var asked=0;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:MeshCoreReconnectBar(onReconnect:()=>asked++))));
    expect(find.text('Module MeshCore : le navigateur demande un clic pour le reconnecter'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('meshcore-reconnect')));
    expect(asked,1);
    // Nothing to reconnect: no bar.
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:MeshCoreReconnectBanner())));
    expect(find.byKey(const ValueKey('meshcore-reconnect-bar')),findsNothing);
  });

  test('waiting for a click: orange pill, state in words; MeshCore everywhere',(){
    expect(meshCorePillTone(MeshCoreState.waitingClick),'wait');
    expect(meshCoreStateText(MeshCoreState.waitingClick),'à reconnecter (un clic)');
    expect(MeshCoreLink.instance.supported,isTrue);
    expect(MeshCoreLink.instance.browserReady,isTrue,reason:'installed app: Bluetooth directly');
    expect(webBluetoothAvailable(),isFalse);
  });
}
