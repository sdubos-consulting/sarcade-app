// Lot 26, événements rattachés à un groupe organisateur et visibles des
// groupes invités (docs/directory-v0.1.md du serveur, « Événements »).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/features/events/event_access.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';

const server = 'https://app.example.org';

final directory = <Map<String, dynamic>>[
  {'id': 'public', 'short_name': 'Public', 'name': 'Public', 'parent_id': null, 'system': true, 'can_organize': false},
  {'id': 'server-admins', 'short_name': 'Administrateurs du serveur', 'system': true, 'can_organize': false},
  {'id': 'adrasec-78', 'short_name': 'ADRASEC 78', 'parent_id': 'fnrasec', 'system': false, 'can_organize': true},
  {'id': 'vcmb', 'short_name': 'VCMB', 'parent_id': null, 'system': false, 'can_organize': true},
  {'id': 'lga', 'short_name': 'LGA', 'parent_id': null, 'system': false, 'can_organize': false},
];

http.Response reply(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

void main() {
  setUp(() => S.setLanguage('fr'));

  test('groups to invite: Public first, never the organiser nor the administrators', () {
    expect([for (final g in invitableGroups(directory, 'adrasec-78')) g['id']], ['public', 'lga', 'vcmb']);
    expect(defaultOrganizer([directory[3]]), 'vcmb');
    expect(defaultOrganizer([directory[3], directory[2]]), 'adrasec-78');
    expect(defaultOrganizer(const []), isNull);
  });

  test('new event with its organiser group and invited groups', () async {
    Map<String, dynamic>? sent;
    final api = SarcadeApi(baseUrl: server, client: MockClient((r) async {
      sent = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
      return reply({'id': 'e1', 'name': 'Course', 'organizer_group_id': 'vcmb'}, 201);
    }));
    await api.createEvent('Course', 'race', organizerGroupId: 'vcmb', invitedGroupIds: ['adrasec-78']);
    expect(sent, {'name': 'Course', 'kind': 'race', 'organizer_group_id': 'vcmb', 'invited_group_ids': ['adrasec-78']});
    await api.createEvent('Famille', 'family');
    expect(sent, {'name': 'Famille', 'kind': 'family'});
  });

  testWidgets('window « Nouvel événement »: organiser group and invited groups', (tester) async {
    final selection = EventGroupsSelection();
    final api = EventAccessApi(server, client: MockClient((r) async => reply(directory)));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: EventGroupsChoice(server: server, selection: selection, api: api))));
    await tester.pumpAndSettle();
    expect(selection.offered, isTrue);
    expect(selection.organizer, 'adrasec-78');
    expect(find.byKey(const ValueKey('event-new-invite-adrasec-78')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('event-new-invite-public')));
    await tester.pump();
    expect(selection.invited, ['public']);
  });

  testWidgets('no group organised: nothing offered, the server chooses', (tester) async {
    final selection = EventGroupsSelection();
    final api = EventAccessApi(server, client: MockClient((r) async => reply({'detail': 'event_organizer_required'}, 403)));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: EventGroupsChoice(server: server, selection: selection, api: api))));
    await tester.pumpAndSettle();
    expect(selection.offered, isFalse);
    expect(find.byKey(const ValueKey('event-new-organizer')), findsNothing);
  });

  testWidgets('Paramètres › Événement › Accès: invited groups changed, communication group from a group', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final puts = <Map<String, dynamic>>[];
    Map<String, dynamic>? created;
    Map<String, dynamic> access = {
      'event_id': 'e1', 'organizer_group': {'id': 'adrasec-78', 'short_name': 'ADRASEC 78', 'name': 'ADRASEC des Yvelines'},
      'invited_groups': <Map<String, dynamic>>[], 'organization_id': 'fnrasec', 'can_organize': true,
    };
    final api = EventAccessApi(server, client: MockClient((r) async {
      final p = r.url.path.replaceFirst('/api/v0.1', '');
      if (p == '/directory/groups') return reply(directory);
      if (p == '/events/e1/access' && r.method == 'GET') return reply(access);
      if (p == '/events/e1/access' && r.method == 'PUT') {
        final b = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
        puts.add(b);
        access = {...access, 'invited_groups': [for (final id in b['invited_group_ids'] as List) {'id': id, 'short_name': id == 'lga' ? 'LGA' : id}]};
        return reply(access);
      }
      if (p == '/events/e1/groups/from-directory') {
        created = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
        return reply({'id': 'g1', 'name': 'ADRASEC 78', 'members': ['TEL-01', 'TEL-02'], 'devices': [{}, {}], 'people': []}, 201);
      }
      return reply({}, 404);
    }));
    Widget row(String label, {String? help, required Widget child}) => Column(children: [Text(label), if (help != null) Text(help), child]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: EventAccessSection(server: server, eventId: 'e1', row: row, api: api)))));
    await tester.pumpAndSettle();
    expect(find.text('ADRASEC 78 · ADRASEC des Yvelines'), findsOneWidget);
    expect(find.text('Aucun groupe invité'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('access-invited')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('access-invite-lga')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('access-invite-save')));
    await tester.pumpAndSettle();
    expect(puts.single, {'invited_group_ids': ['lga']});
    expect(find.text('LGA'), findsOneWidget);
    // « Accès enregistré » goes away.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('access-comm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('access-comm-create')));
    await tester.pumpAndSettle();
    expect(created, {'group_id': 'adrasec-78', 'mode': 'discussion'});
    expect(find.text('Groupe « ADRASEC 78 » créé : 2 appareils'), findsOneWidget);
  });
}
