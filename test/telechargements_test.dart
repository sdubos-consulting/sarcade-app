// Card « Téléchargements servis par le serveur SARCADE » (validated on
// 9 Nov 2026): À propos without GitHub links, the Windows installer of the
// image of the server taken as the update.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/settings/about_page.dart';
import 'package:sarcade_app/src/features/settings/windows_update.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  setUp(()=>S.setLanguage('fr'));

  test('pages of the server of the session',(){
    expect(serverPageUrl('https://app.sarcade.org/','telechargements'),'https://app.sarcade.org/telechargements');
    expect(serverPageUrl('http://192.168.0.110:8000','confidentialite'),'http://192.168.0.110:8000/confidentialite');
    expect(serverPageUrl('','telechargements'),isNull);
    expect(serverPageUrl('pas une adresse','telechargements'),isNull);
  });

  test('« Signaler un problème »: e-mail with the version',(){
    final m=Uri.parse(aboutFeedbackMailto(version:'0.1.0',build:'main@abc1234',number:'1286'));
    expect(m.scheme,'mailto');
    expect(m.path,'github@sdubos.com');
    expect(m.queryParameters['subject'],'SARCADE 0.1.0 (1286) : problème ou suggestion');
    expect(m.queryParameters['body'],contains('main@abc1234'));
  });

  testWidgets('À propos: downloads of the server, e-mail, licence in the app, no GitHub',(t) async {
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:SingleChildScrollView(child:SarcadeAboutContent(serverUrl:'https://app.sarcade.org')))));
    expect(find.text('Télécharger et code source'),findsOneWidget);
    expect(find.text('app.sarcade.org'),findsNWidgets(2), reason:'downloads and privacy policy on the server');
    expect(find.text('github@sdubos.com'),findsOneWidget);
    expect(find.textContaining('github.com'),findsNothing);
    await t.ensureVisible(find.byKey(const ValueKey('about-licence')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('about-licence')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('about-licence-text')),findsOneWidget);
    expect(find.textContaining('Mozilla Public License'),findsOneWidget);
  });

  test('installer of the image: URL of /telechargements on the server',(){
    final r=releaseFromServer({'windows':{'version':'0.1.0+1286','sha256':'a'*64,'size':10,
      'url':'/telechargements/sarcade-windows-setup.exe','source':'image'}},'https://s/')!;
    expect(r.url,'https://s/telechargements/sarcade-windows-setup.exe');
    expect(r.source,WindowsUpdateSource.server);
  });
}
