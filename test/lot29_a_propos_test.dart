import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/settings/about_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  setUp(()=>S.setLanguage('fr'));
  test('site under each link, version on one line',(){
    expect(linkSite('https://www.sdubos.com/'),'sdubos.com');
    expect(linkSite('https://github.com/sdubos-consulting/sarcade-app'),'github.com');
    expect(aboutVersionLine(version:'0.1.0',build:'2003'),'Version 0.1.0 (2003)');
    expect(aboutVersionLine(version:'0.1.0',build:''),'Version 0.1.0');
  });
  testWidgets('links with « › », no square external-link icon',(t) async {
    await t.pumpWidget(const MaterialApp(home:SarcadeAboutPage()));
    expect(find.byIcon(Icons.open_in_new),findsNothing);
    expect(find.text('Code source'),findsOneWidget);
    expect(find.text('Dans l’application'),findsOneWidget);
  });
}
