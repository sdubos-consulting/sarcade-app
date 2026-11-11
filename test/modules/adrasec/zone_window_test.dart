// Card « Plusieurs zones » (1 Nov 2026), points 9 and 10: window of a zone
// and choice Auto / Plusieurs balises / Une seule balise.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/modules/adrasec/bearings/bearing_models.dart';
import 'package:sarcade_app/src/modules/adrasec/bearings/zone_window.dart';

import 'zones_multiples_test.dart' as z;

void main(){
  setUp(()=>S.setLanguage('fr'));

  ZoneTap tapOf(String mode){
    final all=[...z.good(),...z.other()];
    return ZoneTap(search:'121,375 MHz',zone:probableZones(all,mode:mode).first,bearings:all,position:const Offset(100,100));
  }

  test('facts of the window: frequency, kept, set aside, size',(){
    final facts=zoneFacts(tapOf('multi'));
    expect(facts.map((f)=>f.$1),['Fréquence','Relevés retenus','Relevés écartés','Taille de la zone']);
    expect(facts[0].$2,'121,375 MHz');
    expect(facts[1].$2,'4'); expect(facts[2].$2,'0');
    expect(facts[3].$2,startsWith('±'));
  });

  testWidgets('the window offers the three modes and saves the choice',(tester) async {
    final chosen=<String>[];
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(c)=>TextButton(
      onPressed:()=>showZoneWindow(c,tapOf('auto'),mode:'auto',onMode:(m) async {chosen.add(m);return true;}),
      child:const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('zone-window')),findsOneWidget);
    expect(find.text('Plusieurs balises'),findsOneWidget);
    expect(find.text('Une seule balise'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('zone-mode-multi')));
    await tester.pumpAndSettle();
    expect(chosen,['multi']);
    expect(find.byKey(const ValueKey('zone-window')),findsNothing);
  });

  testWidgets('same choice in the bearing sheet',(tester) async {
    String? chosen;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ZoneModeBlock(mode:'single',onChanged:(m)=>chosen=m))));
    expect(find.text('Zones de ce signal'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('zone-mode-auto')));
    expect(chosen,'auto');
  });

  test('a lone zone keeps the mode in its label',(){
    expect(zonesLabel(tapOf('single').zone),startsWith('Une seule balise · '));
  });
}
