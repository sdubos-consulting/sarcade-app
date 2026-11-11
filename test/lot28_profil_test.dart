// Lot 28 · card « Paramètres : deux « Connecté / Se déconnecter » différents
// (Cloudflare et compte SARCADE), nom du serveur en double », revised by the
// project holder on 3 Nov 2026, 23 h 59: everything in Profil › Connexion.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/access/access_manager.dart';
import 'package:sarcade_app/src/access/access_session.dart';
import 'package:sarcade_app/src/account/account_api.dart';
import 'package:sarcade_app/src/account/account_section.dart';
import 'package:sarcade_app/src/account/device_account.dart';
import 'package:sarcade_app/src/config/saved_servers.dart';
import 'package:sarcade_app/src/features/settings/settings_page.dart' show serverChoiceLabel;
import 'package:sarcade_app/src/l10n/strings.dart';

const server = 'https://lot28.example.org';
const token = 'sdt_lot28';

String jwt(String email, DateTime exp) {
  String part(Map<String, Object> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'RS256'})}.${part({'email': email, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

Widget row(String label, {String? help, required Widget child}) => Column(children: [Text(label), if (help != null) Text(help), child]);

void main() {
  setUp(() => S.setLanguage('fr'));

  test('one « Se déconnecter »: the account, the access or both', () {
    expect(signOutChoices(account: true, access: true), [SignOutChoice.account, SignOutChoice.access, SignOutChoice.both]);
    expect(signOutChoices(account: true, access: false), [SignOutChoice.account]);
    expect(signOutChoices(account: false, access: true), [SignOutChoice.access]);
    expect(signOutChoices(account: false, access: false), isEmpty);
  });

  test('« Accès Internet (Cloudflare) : sdubos@gmail.com, valable jusqu’au 23/11 »', () {
    final now = DateTime.utc(2026, 11, 4, 8);
    final s = AccessSession.fromToken(jwt('sdubos@gmail.com', DateTime.utc(2026, 11, 23, 10)))!;
    expect(accessLine(s, now: now), 'sdubos@gmail.com, valable jusqu’au 23/11');
    expect(accessLine(s, now: DateTime.utc(2026, 12, 1)), 'sdubos@gmail.com : accès expiré');
    expect(accessLine(null, now: now), 'Connexion requise');
  });

  // 9 Nov 2026: no « › Profil » (Profil is no tab any more); the line sits
  // under the account at the top of Paramètres and under the server.
  test('one line « Connecté : … » or « Non connecté · Se connecter »', () {
    expect(connectionSummary(account: const DeviceSession(token: token, email: 'a@b.fr')), 'Connecté : a@b.fr');
    final cf = AccessSession.fromToken(jwt('c@d.fr', DateTime.utc(2030)))!;
    expect(connectionSummary(access: cf), 'Connecté : c@d.fr');
    expect(connectionSummary(accessRequired: true), 'Connexion requise · Se connecter');
    expect(connectionSummary(), 'Non connecté · Se connecter');
  });

  test('server name without the address twice', () {
    expect(serverChoiceLabel(const SavedServer(url: 'https://app.sarcade.org', label: 'SARCADE · app.sarcade.org')),
        'SARCADE · app.sarcade.org');
    expect(serverChoiceLabel(const SavedServer(url: 'http://192.168.0.110:8000', label: 'Club')), 'Club · 192.168.0.110:8000');
    expect(serverChoiceLabel(const SavedServer(url: 'https://app.sarcade.org', label: 'app.sarcade.org')), 'app.sarcade.org');
  });

  testWidgets('Profil › Connexion: account, then Internet access, one « Se déconnecter »', (tester) async {
    final account = AccountManager(persistent: false);
    final access = AccessManager.instance;
    final api = AccountApi(server, client: MockClient((r) async => http.Response('{"status":"revoked"}', 200)));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: AccountSection(server: server, deviceId: 'TEL-01', row: row, account: account, access: access, api: api)))));
    expect(find.text('Connexion'), findsOneWidget);
    expect(find.text('Compte SARCADE'), findsOneWidget);
    expect(find.text('Accès Internet (Cloudflare)'), findsNothing); // the server does not go through Cloudflare
    expect(find.byKey(const ValueKey('auth-signout')), findsNothing);

    await account.save(server, const DeviceSession(token: token, email: 'sdubos@gmail.com'));
    // The secure storage answers on the real event loop.
    await tester.runAsync(() => access.save(server, jwt('sdubos@gmail.com', DateTime.now().toUtc().add(const Duration(days: 19)))));
    await tester.pump();
    expect(find.text('Accès Internet (Cloudflare)'), findsOneWidget);
    expect(find.text('Renouveler l’accès'), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-signout')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('auth-signout')));
    await tester.pumpAndSettle();
    expect(find.text('Se déconnecter de quoi ?'), findsOneWidget);
    expect(find.text('Les deux'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-signout-access')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(access.sessionFor(server), isNull);
    expect(account.sessionFor(server)?.email, 'sdubos@gmail.com');
    expect(find.text('Accès Internet (Cloudflare)'), findsNothing);

    // Only the account left: a plain confirmation.
    await tester.tap(find.byKey(const ValueKey('auth-signout')));
    await tester.pumpAndSettle();
    expect(find.text('Se déconnecter de quoi ?'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('auth-signout-ok')));
    await tester.pumpAndSettle();
    expect(account.sessionFor(server), isNull);
    expect(find.byKey(const ValueKey('auth-signin')), findsOneWidget);
  });
}
