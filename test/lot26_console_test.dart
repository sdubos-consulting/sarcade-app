// Lot 26, console Paramètres › Administration (docs/directory-v0.1.md du
// serveur): arborescence, fiche d'un groupe, erreurs en phrases claires.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/account/api_error.dart';
import 'package:sarcade_app/src/account/rights.dart';
import 'package:sarcade_app/src/admin/admin_api.dart';
import 'package:sarcade_app/src/admin/admin_errors.dart';
import 'package:sarcade_app/src/admin/admin_groups_page.dart';
import 'package:sarcade_app/src/admin/admin_section.dart';
import 'package:sarcade_app/src/admin/admin_tree.dart';
import 'package:sarcade_app/src/features/settings/settings_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

const server = 'https://app.example.org';

Map<String, dynamic> group(String id, String name, {String? parent, bool system = false, bool organization = false, int users = 0}) => {
      'id': id, 'short_name': name, 'name': name, 'description': '', 'color': '#1E88E5', 'parent_id': parent, 'system': system,
      'organization': organization, 'organization_id': organization ? id : null, 'member_groups': [], 'member_of': [], 'children': [],
      'users': users, 'invitations': 0, 'can_admin': true, 'can_manage_members': true,
    };

final groups = [
  group('public', 'Public', system: true),
  group('server-admins', 'Administrateurs du serveur', system: true, users: 1),
  group('vcmb', 'VCMB', organization: true),
  group('fnrasec', 'FNRASEC', organization: true),
  group('adrasec-78', 'ADRASEC 78', parent: 'fnrasec', users: 2),
  group('pco-adrasec-78', 'PCO ADRASEC 78', parent: 'adrasec-78', users: 1),
];

http.Response reply(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

MockClient directoryServer(List<String> calls) => MockClient((r) async {
      calls.add('${r.method} ${r.url.path}');
      final p = r.url.path.replaceFirst('/api/v0.1', '');
      if (p == '/admin/groups' && r.method == 'GET') return reply(groups);
      if (p == '/admin/directory/catalogue') {
        return reply({'rights': [
          {'right': 'group_admin', 'label': 'Administrateur de groupe', 'kind': 'admin', 'scope': 'group'},
          {'right': 'module.adrasec', 'label': 'Module ADRASEC', 'kind': 'module', 'scope': 'none', 'module': 'adrasec'},
        ], 'max_depth': 8});
      }
      if (p == '/admin/groups/adrasec-78') {
        return reply({...group('adrasec-78', 'ADRASEC 78', parent: 'fnrasec'),
          'users': [{'user_id': 'u1', 'email': 'paul@adrasec78.fr', 'display_name': null, 'status': 'active', 'added_at': '2026-11-03T10:00:00Z'}],
          'invitations': [{'email': 'marie@adrasec78.fr', 'invited_at': '2026-11-03T10:00:00Z', 'invited_by': 'stephane@sdubos.com'}],
          'groups': [],
          'habilitations': [{'id': 'h1', 'group_id': 'adrasec-78', 'right': 'module.adrasec', 'label': 'Module ADRASEC', 'scope_group_id': null,
            'scope_name': null, 'until': '2026-12-31T23:00:00Z', 'expired': false, 'granted_at': '2026-11-03T10:00:00Z', 'granted_by': 'migration'}],
          'ancestors': [{'id': 'fnrasec', 'short_name': 'FNRASEC'}]});
      }
      if (p == '/admin/groups/adrasec-78/members' && r.method == 'POST') {
        return reply({'detail': {'error': 'cycle', 'path': ['VCMB', 'Signaleurs VCMB', 'ADRASEC 78'],
          'message': 'Impossible : VCMB contient déjà Signaleurs VCMB, qui contient ADRASEC 78'}}, 409);
      }
      if (p == '/transition') return reply({'active': true, 'until': null, 'pco_by_name': true, 'anonymous_rights': 'legacy'});
      if (p == '/admin/mail') return reply({'delivery': 'simulated', 'host': null, 'port': 587, 'sender': null, 'missing': ['SARCADE_SMTP_HOST']});
      return reply({'detail': 'not_found'}, 404);
    });

void main() {
  setUp(() => S.setLanguage('fr'));
  tearDown(() => S.setLanguage('fr'));

  test('tree by attachment: system groups first, sub-groups under their parent', () {
    final lines = groupTree(groups);
    expect([for (final l in lines) '${'  ' * l.depth}${l.group['short_name']}'], [
      'Administrateurs du serveur', 'Public', 'FNRASEC', '  ADRASEC 78', '    PCO ADRASEC 78', 'VCMB',
    ]);
  });

  test('refusals of the directory in clear sentences', () {
    final cycle = ApiError.from('member_add', 409, jsonEncode({'detail': {'error': 'cycle', 'path': ['VCMB', 'ADRASEC 78'],
      'message': 'Impossible : VCMB contient déjà ADRASEC 78'}}));
    expect(adminErrorText(cycle), 'Impossible : VCMB contient déjà ADRASEC 78');
    S.setLanguage('en');
    expect(adminErrorText(cycle), 'Impossible: loop of groups (VCMB › ADRASEC 78)');
    S.setLanguage('fr');
    expect(adminErrorText(ApiError.from('x', 409, jsonEncode({'detail': {'error': 'last_admin'}}))),
        'Impossible : il doit rester au moins un administrateur actif');
    expect(adminErrorText(ApiError.from('x', 403, jsonEncode({'detail': {'error': 'no_elevation', 'right': 'module.adrasec'}})),
        rightLabel: (r) => 'Module ADRASEC'), 'Vous ne pouvez accorder que les droits que vous détenez vous-même (Module ADRASEC)');
    expect(adminErrorText(ApiError.from('x', 409, jsonEncode({'detail': 'group_has_events'}))),
        'Ce groupe organise des événements : il ne peut pas être supprimé');
  });

  test('Administration tab for administrators only, before Diagnostic', () {
    expect(settingsTabs(firstRun: false, event: false, admin: true), ['general', 'profile', 'notifications', 'admin', 'diagnostics', 'about']);
    expect(settingsTabs(firstRun: false, event: false), isNot(contains('admin')));
    expect(settingsTabLabel('admin'), 'Administration');
    expect(settingsShowsSaveBar(tab: 'admin', firstRun: false, dirty: false), isFalse);
  });

  testWidgets('computer: tree on the left, sheet of the group on the right; a cycle refused in a window', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <String>[];
    final api = AdminApi(server, client: directoryServer(calls));
    const rights = MyRights(isServerAdmin: true, canAdminister: true, modulesKnown: true);
    await tester.pumpWidget(MaterialApp(home: AdminGroupsPage(api: api, rights: rights)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin-tree')), findsOneWidget);
    expect(find.text('Choisissez un groupe'), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-new-org')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('admin-group-adrasec-78')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin-user-paul@adrasec78.fr')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-invitation-marie@adrasec78.fr')), findsOneWidget);
    expect(find.text('Module ADRASEC'), findsOneWidget);
    expect(find.textContaining('jusqu’au 31/12/2026'), findsOneWidget);
    expect(find.text('Rattaché à FNRASEC'), findsOneWidget);
    // Sub-group PCO ADRASEC 78 listed under « Sous-groupes ».
    expect(find.text('PCO ADRASEC 78'), findsNWidgets(2));
    // Add VCMB in ADRASEC 78: the server refuses the cycle.
    await tester.tap(find.byKey(const ValueKey('admin-members-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un groupe dans ADRASEC 78'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VCMB').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin-error')), findsOneWidget);
    expect(find.text('Impossible : VCMB contient déjà Signaleurs VCMB, qui contient ADRASEC 78'), findsOneWidget);
    expect(calls, contains('POST /api/v0.1/admin/groups/adrasec-78/members'));
  });

  testWidgets('phone: the sheet of a group opens on its own page', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = AdminApi(server, client: directoryServer([]));
    await tester.pumpWidget(MaterialApp(home: AdminGroupsPage(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Choisissez un groupe'), findsNothing);
    expect(find.byKey(const ValueKey('admin-new-org')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('admin-group-adrasec-78')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin-panel-adrasec-78')), findsOneWidget);
  });

  testWidgets('server administrator: transition with its warning, simulated emails', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = AdminApi(server, client: directoryServer([]));
    Widget row(String label, {String? help, required Widget child}) => Column(children: [Text(label), if (help != null) Text(help), child]);
    const rights = MyRights(isServerAdmin: true, canAdminister: true, modulesKnown: true);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: AdminSection(server: server, rights: rights, row: row, api: api)))));
    await tester.pumpAndSettle();
    expect(find.text('En cours, sans date de fin'), findsOneWidget);
    expect(find.text('Vérifiez que les PCO se sont connectés avant la fin'), findsOneWidget);
    expect(find.text('Simulé : les codes vont au journal de sécurité (manque SARCADE_SMTP_HOST)'), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-codes')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-open-accounts')), findsOneWidget);
  });

  testWidgets('group administrator: no accounts, transition nor emails', (tester) async {
    final api = AdminApi(server, client: directoryServer([]));
    Widget row(String label, {String? help, required Widget child}) => Column(children: [Text(label), if (help != null) Text(help), child]);
    const rights = MyRights(canAdminister: true, modulesKnown: true,
        adminRights: [{'right': 'group_admin', 'scope_group_id': 'adrasec-78', 'scope_name': 'ADRASEC 78'}]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: AdminSection(server: server, rights: rights, row: row, api: api)))));
    await tester.pumpAndSettle();
    expect(find.text('Vos droits : Administrateur de groupe · ADRASEC 78'), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-open-groups')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-open-accounts')), findsNothing);
    expect(find.byKey(const ValueKey('admin-transition')), findsNothing);
  });
}
