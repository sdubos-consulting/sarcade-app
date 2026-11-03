// Lot 26, droits effectifs lus sur /me (docs/directory-v0.1.md du serveur):
// menus des modules selon `modules`, sauf pendant la transition.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/account/account_api.dart';
import 'package:sarcade_app/src/account/account_section.dart';
import 'package:sarcade_app/src/account/device_account.dart';
import 'package:sarcade_app/src/account/rights.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/comm_group.dart';
import 'package:sarcade_app/src/modules/registry.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';

const server = 'https://app.example.org';

Map<String, dynamic> me({required bool transition, List<String> modules = const [], bool admin = false}) => {
      'email': 'paul@adrasec78.fr', 'checked': true, 'roles': admin ? ['admin', 'pco'] : <String>[], 'via': 'device',
      'groups': [{'id': 'adrasec-78', 'short_name': 'ADRASEC 78', 'name': 'ADRASEC des Yvelines', 'direct': true}],
      'admin_rights': admin ? [{'right': 'group_admin', 'scope_group_id': 'adrasec-78', 'scope_name': 'ADRASEC 78', 'until': null}] : [],
      'modules': modules, 'module_rights': [for (final m in modules) {'module': m, 'licensed': true}],
      'is_server_admin': false, 'can_administer': admin, 'rights_version': 12,
      'transition': {'active': transition, 'until': transition ? null : '2026-12-31T23:00:00Z', 'pco_by_name': transition,
        'anonymous_rights': transition ? 'legacy' : 'core'},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => S.setLanguage('fr'));
  tearDown(() => pcoByName = true);

  test('transition active : aucun menu ne disparaît', () {
    final state = RightsState();
    state.apply(server, me(transition: true));
    for (final m in [...appModules.map((m) => m.id), 'race', 'assist', 'siem']) {
      expect(state.allows(m), isTrue, reason: m);
    }
    expect(state.of(server)!.transition.active, isTrue);
    expect(pcoByName, isTrue);
  });

  test('after the transition only the modules of the account', () {
    final state = RightsState();
    state.apply(server, me(transition: false, modules: ['adrasec']));
    expect(state.allows('adrasec'), isTrue);
    expect(state.allows('race'), isFalse);
    state.apply(server, me(transition: false));
    expect(state.allows('adrasec'), isFalse);
    // PCO by its name: over with the transition.
    expect(isPco('PCO-1'), isFalse);
  });

  test('older server or rights not read: nothing hidden', () {
    final state = RightsState();
    expect(state.allows('adrasec'), isTrue);
    state.apply(server, {'email': null, 'checked': false, 'roles': []});
    expect(state.allows('adrasec'), isTrue);
    expect(state.canAdminister, isFalse);
  });

  test('offline: the last rights read stay', () {
    final state = RightsState();
    state.apply(server, me(transition: false, modules: ['adrasec'], admin: true));
    state.apply(server, null);
    expect(state.canAdminister, isTrue);
    expect(state.of('https://other.example.org'), isNull);
  });

  test('rights read with the account: groups, administration, version', () {
    final r = MyRights.fromMe(me(transition: false, modules: ['adrasec'], admin: true));
    expect(r.groups.single['short_name'], 'ADRASEC 78');
    expect(r.canAdminister, isTrue);
    expect(r.organizes, isTrue);
    expect(r.rightsVersion, 12);
    expect(r.transition.until, DateTime.utc(2026, 12, 31, 23));
  });

  test('Cloudflare Access without device token: enrolled once, without code', () async {
    const access = 'https://access.example.org';
    final account = AccountManager(persistent: false);
    final state = RightsState();
    var enrolled = 0;
    http.Response reply(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    final mock = MockClient((r) async {
      if (r.url.path == '/api/v0.1/me') return reply({...me(transition: true), 'via': 'access'});
      if (r.url.path == '/api/v0.1/auth/access/enroll') {
        enrolled++;
        return reply({'token': 'sdt_access0123456789', 'device': {'id': 'dev-9', 'device_id': 'TEL-01', 'method': 'access'},
          'account': {'email': 'paul@adrasec78.fr'}});
      }
      return http.Response('{}', 404);
    });
    final api = SarcadeApi(baseUrl: access, client: mock);
    await refreshRights(api, deviceId: 'TEL-01', account: account, state: state, accountApi: AccountApi(access, client: mock));
    await account.forget(access);
    await refreshRights(api, deviceId: 'TEL-01', account: account, state: state, accountApi: AccountApi(access, client: mock));
    expect(enrolled, 1);
    expect(state.of(access)?.email, 'paul@adrasec78.fr');
  });

  test('invitation: only on a server of lot 26, without account, not for a week after « Plus tard »', () {
    final now = DateTime(2026, 11, 3, 15);
    final rights = MyRights.fromMe(me(transition: true));
    expect(showsSignInInvite(rights: rights, signedIn: false, now: now), isTrue);
    expect(showsSignInInvite(rights: rights, signedIn: true, now: now), isFalse);
    expect(showsSignInInvite(rights: null, signedIn: false, now: now), isFalse);
    expect(showsSignInInvite(rights: MyRights.fromMe({'roles': []}), signedIn: false, now: now), isFalse);
    expect(showsSignInInvite(rights: rights, signedIn: false, later: now.subtract(const Duration(days: 2)), now: now), isFalse);
    expect(showsSignInInvite(rights: rights, signedIn: false, later: now.subtract(const Duration(days: 8)), now: now), isTrue);
  });

  testWidgets('discreet invitation during the transition, gone after « Plus tard »', (tester) async {
    final account = AccountManager(persistent: false);
    final state = RightsState()..apply(server, me(transition: true));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AccountBanner(server: server, deviceId: 'TEL-01', account: account, rights: state))));
    expect(find.byKey(const ValueKey('auth-invite')), findsOneWidget);
    expect(find.text('Connectez-vous pour garder vos droits après la transition'), findsOneWidget);
    await tester.tap(find.text('Plus tard'));
    await tester.pump();
    expect(find.byKey(const ValueKey('auth-invite')), findsNothing);
  });
}
