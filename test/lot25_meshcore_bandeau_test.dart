// Lot 25, card « Web, MeshCore : bandeau « le navigateur demande un clic
// pour le reconnecter » affiché en permanence » (decided on 2 Nov 2026,
// 21 h 57).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_banner.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_link.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_link_card.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  final link=MeshCoreLink.instance;
  setUp((){S.setLanguage('fr');link.testMode=true;link.resetForTest();meshCoreBannerLater.value=false;meshCoreScreensOpen.value=0;});
  tearDown((){link.resetForTest();meshCoreBannerLater.value=false;meshCoreScreensOpen.value=0;});

  test('one bar on the MeshCore screen, none after « Plus tard »',(){
    bool shown({MeshCoreState state=MeshCoreState.waitingClick,bool later=false,required bool inScreen,int open=0})=>
      meshCoreBannerShown(state:state,later:later,inScreen:inScreen,screensOpen:open);
    expect(shown(inScreen:false),isTrue,reason:'above the map');
    expect(shown(inScreen:false,open:1),isFalse,reason:'MeshCore screen open: the bar above the map hides');
    expect(shown(inScreen:true,open:1),isTrue,reason:'the bar of the screen stays');
    expect(shown(inScreen:false,later:true),isFalse);
    expect(shown(inScreen:true,later:true,open:1),isFalse);
    for(final s in MeshCoreState.values.where((s)=>s!=MeshCoreState.waitingClick)){
      expect(shown(state:s,inScreen:false),isFalse,reason:s.name);
    }
  });

  testWidgets('« Plus tard » hides the bar until the next opening',(t) async {
    link.state=MeshCoreState.waitingClick;
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:Column(children:[MeshCoreReconnectBanner()]))));
    expect(find.byKey(const ValueKey('meshcore-reconnect-bar')),findsOneWidget);
    expect(find.text('Plus tard'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('meshcore-later')));
    await t.pump();
    expect(find.byKey(const ValueKey('meshcore-reconnect-bar')),findsNothing);
    expect(meshCoreBannerLater.value,isTrue);
  });

  testWidgets('one bar while the MeshCore screen is open',(t) async {
    link.state=MeshCoreState.waitingClick;
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:Column(children:[
      MeshCoreReconnectBanner(key:ValueKey('top')),MeshCoreReconnectBanner(key:ValueKey('screen'),inScreen:true)]))));
    expect(find.byKey(const ValueKey('meshcore-reconnect-bar')),findsNWidgets(2));
    meshCoreScreensOpen.value=1;
    await t.pump();
    expect(find.byKey(const ValueKey('meshcore-reconnect-bar')),findsOneWidget);
    expect(find.descendant(of:find.byKey(const ValueKey('screen')),matching:find.byKey(const ValueKey('meshcore-reconnect-bar'))),findsOneWidget);
  });

  test('« Reconnecter » that fails: « module indisponible », the pill stays',() async {
    link.testPrefs[meshCoreDeviceKey]='AA:BB';
    link.restoreForTest();
    link.state=MeshCoreState.waitingClick;
    await link.reconnectInBrowser(pick:() async => null);
    expect(link.state,MeshCoreState.unavailable);
    expect(meshCoreStateText(link.state),'module indisponible');
    expect(meshCorePillTone(link.state),'bad',reason:'the pill stays, in red');
    expect(link.remembered,isTrue,reason:'the module is still remembered to reconnect later');
    expect(meshCoreBannerShown(state:link.state,later:false,inScreen:false,screensOpen:0),isFalse,reason:'the bar goes');
    S.setLanguage('en');
    expect(meshCoreStateText(MeshCoreState.unavailable),'module unavailable');
  });
}
