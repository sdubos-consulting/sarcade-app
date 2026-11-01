// Bouton « Écrans » and screen settings (cards validated 1 Nov 2026, 8 h 01
// and 8 h 27): automatic discovery can be switched off, mode of a screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/features/tv/tv_nearby.dart';
import 'package:sarcade_app/src/features/tv/tv_theme.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';

void main(){
  setUp(()=>S.setLanguage('fr'));
  tearDown(()=>tvDiscovery.value=true);

  test('discovery on by default, off when stored « 0 »',(){
    expect(tvDiscoveryOn(null),isTrue);
    expect(tvDiscoveryOn('0'),isFalse);
  });

  testWidgets('discovery off: the server is not even asked',(t) async {
    var calls=0;
    final api=SarcadeApi(baseUrl:'http://s',client:MockClient((r) async {calls++;return http.Response('[]',200);}));
    tvDiscovery.value=false;
    await t.pumpWidget(const MaterialApp(home:Scaffold()));
    final ctx=t.element(find.byType(Scaffold));
    await TvNearbyWatcher(api).check(ctx,'e');
    expect(calls,0);
    tvDiscovery.value=true;
    await TvNearbyWatcher(api).check(ctx,'e');
    expect(calls,1);
  });

  testWidgets('mode of a screen: Automatique, Jour, Nuit',(t) async {
    String? chosen;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(c)=>TextButton(
      onPressed:() async {chosen=await chooseTvTheme(c,{'theme':'night'});},child:const Text('go'))))));
    await t.tap(find.text('go')); await t.pumpAndSettle();
    expect(find.text('Automatique'),findsOneWidget);
    expect(find.text('Nuit du coucher au lever du soleil'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('tv-theme-day'))); await t.pumpAndSettle();
    expect(chosen,'day');
    expect(tvThemeOf({}),'auto');
  });
}
