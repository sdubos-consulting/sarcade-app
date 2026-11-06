import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/team/operator_status.dart';
import 'package:sarcade_app/src/features/team/teams_view.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  setUp(()=>S.setLanguage('fr'));
  test('search: name, callsign, status; accents and case ignored',(){
    expect(teamMatches('thim',name:'Thiméo-Android'),isTrue);
    expect(teamMatches('THIME',name:'Thiméo-Android'),isTrue);
    expect(teamMatches('sur place',name:'PCO',status:'Sur place'),isTrue);
    expect(teamMatches('f4',name:'Voiture',callsign:'F4JPO-9'),isTrue);
    expect(teamMatches('zz',name:'PCO'),isFalse);
    expect(teamMatches('',name:'PCO'),isTrue);
  });
  testWidgets('status in one pill: two touches to change it',(t) async {
    String? chosen='x';
    await t.pumpWidget(MaterialApp(home:Scaffold(appBar:AppBar(actions:[MyStatusPill(status:'disponible',onChanged:(v)=>chosen=v)]))));
    expect(find.text('Disponible'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('my-status-pill'))); await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-status-sur_place'))); await t.pumpAndSettle();
    expect(chosen,'sur_place');
  });
}
