// Card « Signaler un problème : mail en principal, lien GitHub en second une
// fois le dépôt rétabli », validated on 11 Nov 2026 (choices 1 to 3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/settings/about_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

Future<void> pump(WidgetTester t, Future<String?> Function() repo) async {
  await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
    child: SarcadeAboutContent(serverUrl: 'https://app.sarcade.org', loadPublicRepo: repo)))));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => S.setLanguage('fr'));

  test('choice 1: the e-mail with the version and the platform', () {
    final mail = Uri.decodeFull(aboutFeedbackMailto(version: '0.9.0', build: 'abc', number: '2001', platform: 'iPhone'));
    expect(mail, startsWith('mailto:github@sdubos.com'));
    expect(mail, contains('SARCADE 0.9.0 (2001) · abc · iPhone'));
  });

  test('choice 2: issue with version and platform only, reminder that it is public', () {
    final url = Uri.parse(githubIssueUrl('https://github.com/sdubos-consulting/sarcade-app', version: '0.9.0', number: '2001', platform: 'Android'));
    expect('${url.scheme}://${url.host}${url.path}', 'https://github.com/sdubos-consulting/sarcade-app/issues/new');
    final body = url.queryParameters['body']!;
    expect(body, contains('SARCADE 0.9.0 (2001) · Android'));
    expect(body, contains('Ce ticket est public'));
    expect(body.toLowerCase(), isNot(contains('lat')));
    expect(url.queryParameters['title'], 'SARCADE 0.9.0 (2001) : ');
  });

  testWidgets('choice 3: no GitHub link while the server gives no public repository', (t) async {
    await pump(t, () async => null);
    expect(find.byKey(const ValueKey('about-feedback')), findsOneWidget);
    expect(find.byKey(const ValueKey('about-github-issue')), findsNothing);
  });

  testWidgets('choice 2 and 3: the link under the e-mail when the server gives it', (t) async {
    await pump(t, () async => 'https://github.com/sdubos-consulting/sarcade-app');
    final gh = find.byKey(const ValueKey('about-github-issue'));
    expect(gh, findsOneWidget);
    expect(find.text('Ou sur GitHub (compte requis)'), findsOneWidget);
    expect(t.getTopLeft(gh).dy, greaterThan(t.getTopLeft(find.byKey(const ValueKey('about-feedback'))).dy), reason: 'second');
  });
}
