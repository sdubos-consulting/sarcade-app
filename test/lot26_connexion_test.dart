// Lot 26, connexion par code e-mail et appareil enrôlé (docs/accounts-v0.1.md
// du serveur): jeton `sdt_…` envoyé en Bearer, oublié sur un refus.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/access/access_manager.dart';
import 'package:sarcade_app/src/account/account_api.dart';
import 'package:sarcade_app/src/account/account_section.dart';
import 'package:sarcade_app/src/account/api_error.dart';
import 'package:sarcade_app/src/account/device_account.dart';
import 'package:sarcade_app/src/account/sign_in_dialog.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

const server = 'https://app.example.org';
const token = 'sdt_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGH';

http.Response reply(Object body, [int status = 200, Map<String, String> headers = const {}]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json', ...headers});

Map<String, dynamic> enrolment(String email) => {
      'token': token,
      'device': {'id': 'dev-1', 'device_id': 'TEL-01', 'method': 'email_code'},
      'account': {'id': 'u-1', 'email': email},
      'created': true,
    };

/// Answers of the mock server without moving the clock (countdown kept).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => S.setLanguage('fr'));

  test('the token goes as Bearer to its server only', () async {
    final account = AccountManager(persistent: false);
    await account.save(server, const DeviceSession(token: token, email: 'paul@adrasec78.fr', id: 'dev-1'));
    final seen = <String, String?>{};
    final client = AccessHttpClient(account: account, inner: MockClient((r) async {
      seen[r.url.host] = r.headers['authorization'];
      return reply({});
    }));
    await client.get(Uri.parse('$server/api/v0.1/me'));
    await client.get(Uri.parse('https://other.example.org/api/v0.1/me'));
    expect(seen['app.example.org'], 'Bearer $token');
    expect(seen['other.example.org'], isNull);
    expect(account.headersFor(Uri.parse('wss://app.example.org/api/v0.1/events/e/ws')), {'Authorization': 'Bearer $token'});
  });

  test('a revoked token is forgotten and the call sent again without it', () async {
    final account = AccountManager(persistent: false);
    await account.save(server, const DeviceSession(token: token, email: 'paul@adrasec78.fr'));
    final sent = <String?>[];
    final client = AccessHttpClient(account: account, inner: MockClient((r) async {
      sent.add(r.headers['authorization']);
      if (r.headers['authorization'] != null) {
        return reply({'detail': 'device_revoked'}, 401, {'www-authenticate': 'Bearer realm="SARCADE"'});
      }
      return reply([]);
    }));
    final r = await client.get(Uri.parse('$server/api/v0.1/events'));
    expect(r.statusCode, 200);
    expect(sent, ['Bearer $token', null]);
    expect(account.sessionFor(server), isNull);
    expect(account.refusedFor(server), 'device_revoked');
  });

  test('another 401 keeps the token and its answer', () async {
    final account = AccountManager(persistent: false);
    await account.save(server, const DeviceSession(token: token, email: 'a@b.fr'));
    final client = AccessHttpClient(account: account, inner: MockClient((r) async => reply({'detail': 'account_required'}, 401)));
    final r = await client.get(Uri.parse('$server/api/v0.1/me/devices'));
    expect(r.statusCode, 401);
    expect(jsonDecode(r.body)['detail'], 'account_required');
    expect(account.sessionFor(server), isNotNull);
  });

  test('device.revoked: only the token of this enrolment', () async {
    final account = AccountManager(persistent: false);
    await account.save(server, const DeviceSession(token: token, email: 'a@b.fr', id: 'dev-1', deviceId: 'TEL-01'));
    expect(await account.onDeviceRevoked(server, {'id': 'dev-2', 'device_id': 'TEL-01'}), isFalse);
    expect(account.sessionFor(server), isNotNull);
    expect(await account.onDeviceRevoked(server, {'id': 'dev-1', 'device_id': 'TEL-01'}), isTrue);
    expect(account.sessionFor(server), isNull);
  });

  test('refusals of the contract are read and translated', () {
    final e = ApiError.from('auth_verify', 401, jsonEncode({'detail': {'error': 'invalid_code', 'attempts_left': 2}}));
    expect(e.code, 'invalid_code');
    expect(authErrorText(e), 'Code incorrect : 2 essais restants');
    expect(authErrorText(ApiError.from('auth_code', 429, jsonEncode({'detail': {'error': 'too_many_codes', 'retry_after_s': 1700}}))),
        'Trop de codes demandés : réessayez dans 29 min');
    expect(authErrorText(ApiError.from('auth_verify', 410, jsonEncode({'detail': 'code_expired'}))), 'Code expiré : demandez-en un nouveau');
    expect(ApiError.from('x', 502, '<html>').code, '');
  });

  testWidgets('Se connecter: email, code, then this device is enrolled', (tester) async {
    final account = AccountManager(persistent: false);
    final bodies = <String, Map<String, dynamic>>{};
    final api = AccountApi(server, client: MockClient((r) async {
      if (r.method == 'POST') bodies[r.url.path] = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
      switch (r.url.path) {
        case '/api/v0.1/auth/state':
          return reply({'code_length': 6, 'resend_after_s': 60});
        case '/api/v0.1/me':
          return reply({'email': null, 'via': null});
        case '/api/v0.1/auth/code/request':
          return reply({'status': 'sent', 'delivery': 'simulated', 'resend_after_s': 60, 'code_length': 6}, 202);
        case '/api/v0.1/auth/code/verify':
          final code = bodies[r.url.path]!['code'];
          return code == '123456'
              ? reply(enrolment('paul@adrasec78.fr'))
              : reply({'detail': {'error': 'invalid_code', 'attempts_left': 4}}, 401);
      }
      return reply({}, 404);
    }));
    bool? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => TextButton(
        onPressed: () async => result = await showSignInDialog(c, server: server, deviceId: 'TEL-01', api: api, account: account),
        child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('auth-email')), 'paul@adrasec78.fr');
    await tester.tap(find.byKey(const ValueKey('auth-request')));
    await settle(tester);
    expect(find.text('Code envoyé à paul@adrasec78.fr'), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-simulated')), findsOneWidget);
    expect(find.text('Renvoyer dans 60 s'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('auth-code')), '111111');
    await settle(tester);
    expect(find.text('Code incorrect : 4 essais restants'), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
    expect(find.text('Renvoyer le code'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('auth-code')), '123456');
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(account.sessionFor(server)?.token, token);
    expect(account.sessionFor(server)?.email, 'paul@adrasec78.fr');
    expect(bodies['/api/v0.1/auth/code/verify']!['device_id'], 'TEL-01');
  });

  testWidgets('Paramètres › Profil: Se connecter, then Mes appareils and Se déconnecter', (tester) async {
    final account = AccountManager(persistent: false);
    Widget row(String label, {String? help, required Widget child}) => Column(children: [Text(label), if (help != null) Text(help), child]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AccountSection(server: server, deviceId: 'TEL-01', row: row, account: account))));
    expect(find.byKey(const ValueKey('auth-signin')), findsOneWidget);
    expect(find.text('Non connecté'), findsOneWidget);
    await account.save(server, const DeviceSession(token: token, email: 'paul@adrasec78.fr'));
    await tester.pump();
    expect(find.text('Connecté : paul@adrasec78.fr'), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-devices')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-signout')), findsOneWidget);
    await account.forget(server, reason: 'device_revoked');
    await tester.pump();
    expect(find.text('Appareil déconnecté de votre compte'), findsOneWidget);
  });

  testWidgets('a refused token shows « Se connecter » above the map', (tester) async {
    final account = AccountManager(persistent: false);
    await account.save(server, const DeviceSession(token: token, email: 'a@b.fr'));
    var changes = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AccountBanner(server: server, deviceId: 'TEL-01', account: account, onChanged: () => changes++))));
    expect(find.byKey(const ValueKey('auth-banner')), findsNothing);
    await account.forget(server, reason: 'device_token_invalid');
    await tester.pump();
    expect(find.byKey(const ValueKey('auth-banner')), findsOneWidget);
    expect(changes, 1);
    await tester.tap(find.text('Plus tard'));
    await tester.pump();
    expect(find.byKey(const ValueKey('auth-banner')), findsNothing);
  });
}
