// Lot 28 · Diagnostic: three levels computed by the server, test of Brevo,
// « Échéances », versions, and every line readable at 320 px (cards
// « Téléphone : Diagnostic, ligne Cloudflare Access écrite une lettre par
// ligne », « Diagnostic : trois niveaux », « Diagnostic administrateur :
// Échéances », « Consolidation : version de référence »).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/access/access_session.dart';
import 'package:sarcade_app/src/account/rights.dart';
import 'package:sarcade_app/src/admin/admin_api.dart';
import 'package:sarcade_app/src/admin/admin_section.dart';
import 'package:sarcade_app/src/admin/deadlines_page.dart';
import 'package:sarcade_app/src/config/version.dart';
import 'package:sarcade_app/src/features/settings/diagnostics_levels.dart';
import 'package:sarcade_app/src/features/settings/diagnostics_panel.dart';
import 'package:sarcade_app/src/features/settings/settings_page.dart' show settingsRowLayout;
import 'package:sarcade_app/src/l10n/strings.dart';

const server = 'https://app.example.org';

final adminDiag = <String, dynamic>{
  'level': 'admin', 'status': 'degraded', 'version': '0.1.0', 'reference': 'main@0123456', 'uptime_s': 93784,
  'components': {'database': 'green', 'realtime': 'green', 'tunnel': 'orange', 'wakeup': 'green', 'aprs': 'off', 'weather': 'green'},
  'resources': {'cpu_pct': 12.5, 'memory': {'pct': 81.2, 'used_mb': 6500, 'total_mb': 8000}, 'disk': {'pct': 40.0, 'used_gb': 40.1, 'total_gb': 100.0}},
  'last_update': {'version': '0.1.0', 'at': '2026-11-04T06:00:00Z', 'status': 'succeeded'},
  'last_backup': {'at': '2026-11-04T06:00:00Z', 'file': '/var/backups/x.sql.gz'},
  'build': {'commit_short': '0123456', 'web_sha256': 'sha256:${'ab' * 32}', 'sbom_sha256': null},
  'addresses': ['172.18.0.5', '192.168.0.110'],
  'mail': {'delivery': 'smtp', 'host': 'smtp-relay.brevo.com', 'port': 587, 'sender': 'no-reply@sarcade.org',
    'probe': {'ok': false, 'error': 'SMTPAuthenticationError 535 5.7.8 Authentication failed', 'at': '2026-11-04T19:00:00Z'},
    'last_success_at': '2026-11-03T22:17:00Z', 'last_failure_at': '2026-11-04T18:00:00Z',
    'last_failure': 'SMTPAuthenticationError 535 5.7.8 Authentication failed'},
  'deadlines': {'items': [
    {'id': 'mail-inactivity', 'name': 'Clé SMTP Brevo : 90 jours sans envoi', 'date': '2026-11-09', 'days_left': 5, 'level': 'red'},
    {'id': 'apple-developer', 'name': 'Adhésion Apple Developer', 'date': '2027-10-22', 'days_left': 352, 'level': 'green'},
    {'id': 'old', 'name': 'Certificat de signature Windows', 'date': '2026-11-01', 'days_left': -3, 'level': 'expired'},
    {'id': 'domain', 'name': 'Domaine sarcade.org', 'date': null, 'days_left': null, 'level': 'unknown'},
  ], 'summary': {'worst': 'expired', 'alerts': 2}},
};

String jwt(String email, DateTime exp) {
  String part(Map<String, Object> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'RS256'})}.${part({'email': email, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

/// No text squeezed into a column of letters (4 Nov 2026, iPhone).
void expectReadable(WidgetTester tester) {
  void check(Finder f, String text) {
    if (text.trim().length <= 4) return;
    expect(tester.getSize(f).width, greaterThan(30), reason: '« $text » is squeezed');
  }
  for (final e in find.byType(RichText).evaluate()) {
    final w = e.widget as RichText;
    check(find.byWidget(w), w.text.toPlainText());
  }
  for (final e in find.byType(SelectableText).evaluate()) {
    final w = e.widget as SelectableText;
    check(find.byWidget(w), w.data ?? '');
  }
}

void main() {
  setUp(() => S.setLanguage('fr'));

  test('level computed by the server; older servers keep the view of before', () {
    expect(diagLevel({'level': 'user'}), 'user');
    expect(diagLevel({'level': 'organizer'}), 'organizer');
    expect(diagLevel({'level': 'admin'}), 'admin');
    expect(diagLevel({'level': 'transition'}), 'transition');
    expect(diagLevel({'status': 'ok'}), 'legacy');
    expect(diagLevel(null), 'legacy');
    expect([for (final l in ['user', 'organizer', 'admin', 'transition', 'legacy']) diagFullView(l)], [false, false, true, true, true]);
    expect(diagShowsServices('user'), isFalse);
    expect(diagShowsServices('organizer'), isTrue);
  });

  test('user: the server only when it is down, in clear words', () {
    expect(serverDownLine('Liaisons', {'level': 'user', 'status': 'ok'}), isNull);
    expect(serverDownLine('Liaisons', {'level': 'user', 'status': 'degraded'}), isNull);
    final l = serverDownLine('Liaisons', {'level': 'user', 'status': 'down'})!;
    expect(l.value, 'Serveur en panne : prévenez le PCO');
    expect(l.state, 'red');
  });

  test('PCO: services of the event and devices connected', () {
    final lines = eventServiceLines({'services': {'aprs': 'green', 'weather': 'orange', 'wakeup': 'green', 'routes': 'red'}, 'devices_connected': 7});
    expect(lines.map((l) => l.label).toList(),
        [S.t('diag.comp.aprs'), S.t('diag.comp.weather'), 'Notifications', 'Calcul d’itinéraire', 'Appareils connectés']);
    expect(lines.last.value, '7');
    expect(lines[3].state, 'red');
  });

  test('administrator: Brevo, connection test and last sendings', () {
    final lines = mailLines(Map<String, dynamic>.from(adminDiag['mail'] as Map));
    expect(lines[0].value, 'SMTP smtp-relay.brevo.com:587 · no-reply@sarcade.org');
    expect(lines[1].state, 'red');
    expect(lines[1].value, startsWith('SMTPAuthenticationError 535'));
    expect(lines[3].state, 'red'); // the failure is the last event
    final simulated = mailLines({'delivery': 'simulated', 'probe': null});
    expect(simulated[0].state, 'orange');
    expect(simulated[1].value, '—');
    expect(simulated[2].value, 'Jamais');
    expect(simulated[3].value, 'Aucun');
  });

  test('deadlines: colour, days left, most urgent first, banner', () {
    final d = Map<String, dynamic>.from(adminDiag['deadlines'] as Map);
    final lines = deadlineLines(d);
    expect(lines.first.value, '09/11/2026 · dans 5 j');
    expect(lines[2].value, 'Expirée le 01/11/2026 (il y a 3 j)');
    expect(lines[2].state, 'expired');
    expect(lines.last.value, 'Date à saisir');
    expect(lines.last.state, isNull);
    expect(deadlineValue({'date': '2026-11-04', 'days_left': 0}), 'Aujourd’hui (04/11/2026)');
    expect(deadlineAlerts(d).map((x) => x['id']), ['mail-inactivity', 'old']);
    expect(S.t('deadline.banner', {'n': 2}), '2 échéances à surveiller');
    expect(stateColor('expired'), expiredRed);
  });

  test('red dot on Paramètres from /me for the administrators', () {
    final r = MyRights.fromMe({'email': 'a@b.fr', 'deadlines': {'worst': 'red', 'alerts': 2}});
    expect(r.deadlineAlerts, 2);
    expect(r.deadlineWorst, 'red');
    expect(MyRights.fromMe({'email': 'a@b.fr'}).deadlineAlerts, 0);
    RightsState.instance.apply(server, {'email': 'a@b.fr', 'deadlines': {'worst': 'orange', 'alerts': 1}});
    expect(deadlinesAlert(), isTrue);
    expect(diagnosticsAlert(), isTrue);
    expect(unsentAlert(), isFalse);
    RightsState.instance.apply(server, {'email': 'a@b.fr'});
    expect(deadlinesAlert(), isFalse);
  });

  test('versions: same reference, different, or development builds', () {
    expect(appReference(tag: 'v0.1.0-exercice1', build: 'main@1a2b3c4'), 'v0.1.0-exercice1');
    expect(appReference(tag: '', build: 'v0.1.0-exercice1@1a2b3c4'), 'v0.1.0-exercice1');
    expect(appReference(tag: '', build: 'main@1a2b3c4'), 'main@1a2b3c4');
    expect(appReference(tag: '', build: ''), 'dev');
    expect(referenceMatch('v0.1.0-exercice1', 'v0.1.0-exercice1'), 'same');
    expect(referenceMatch('v0.1.0-exercice1', 'main@0123456'), 'different');
    expect(referenceMatch('main@1a2b3c4', 'main@0123456'), 'none');
    expect(referenceMatch('main@1a2b3c4', null), 'unknown');
    final same = versionLines('Cet appareil', {'version': '0.1.0-exercice1', 'reference': 'v0.1.0-exercice1'}, app: 'v0.1.0-exercice1');
    expect(same.first.value, '0.1.0-exercice1 · v0.1.0-exercice1');
    expect(same.last.value, 'Appli et serveur : v0.1.0-exercice1');
    expect(same.last.state, 'green');
    final diff = versionLines('Cet appareil', {'version': '0.1.0', 'reference': 'main@0123456'}, app: 'v0.1.0-exercice1');
    expect(diff.last.state, 'orange');
    expect(diff.last.value, 'Versions différentes : appli v0.1.0-exercice1, serveur main@0123456');
    expect(versionLines('Cet appareil', null, app: 'main@1').single.value, 'Appli main@1');
    expect(shortDigest('sha256:${'ab' * 32}'), 'sha256:abababababab…');
    expect(shortDigest(null), '—');
  });

  testWidgets('every line of the Diagnostic readable at 320 px, value under the label, button under it', (tester) async {
    tester.view.physicalSize = const Size(320, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = AccessSession.fromToken(jwt('stephane.dubos.tres.long@gmail.com', DateTime.now().toUtc().add(const Duration(days: 19))))!;
    final lines = <DiagLine>[
      (block: 'Cet appareil', label: 'Version', value: 'SARCADE 0.1.0+977 · claude/l28-diag-app@1a2b3c4', state: null),
      ...versionLines('Cet appareil', adminDiag, app: 'v0.1.0-exercice1'),
      (block: 'Cet appareil', label: 'GPS', value: 'Activé · Autorisé pendant l’utilisation · ± 12 m', state: 'green'),
      (block: 'Cet appareil', label: 'Adresse IP locale', value: '192.168.0.42, fe80::1c2d:3e4f:5a6b:7c8d', state: null),
      accessDiagLine('Liaisons', web: false, session: session, client: {'email': 'x', 'via_cloudflare': true}),
      ?adsbDiagLine('Liaisons', {'enabled': true, 'connected': false, 'detail': 'HTTP 429 Too Many Requests', 'requests_today': 3990}, DateTime.now()),
      ...serverLines(adminDiag),
      ...adminBuildLines(adminDiag),
      ...eventServiceLines({'services': {'aprs': 'green', 'weather': 'green', 'wakeup': 'red', 'routes': 'green'}, 'devices_connected': 12}),
      ...mailLines(Map<String, dynamic>.from(adminDiag['mail'] as Map)),
      ...deadlineLines(Map<String, dynamic>.from(adminDiag['deadlines'] as Map)),
    ];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
      Card(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final l in lines) DiagLineRow(line: l, action: l.label == S.t('diag.access')
            ? TextButton(onPressed: () {}, child: Text(S.t('profile.renewAccess'))) : null),
      ])),
    ]))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('diag-line-narrow')), findsNWidgets(lines.length));
    expect(find.text('Renouveler l’accès'), findsOneWidget);
    // The value of the Cloudflare line under its label, the button under the value.
    final label = tester.getRect(find.text(S.t('diag.access')));
    final value = tester.getRect(find.byWidgetPredicate((w) => w is SelectableText && (w.data ?? '').contains('stephane.dubos')));
    final button = tester.getRect(find.text('Renouveler l’accès'));
    expect(value.top, greaterThanOrEqualTo(label.bottom));
    expect(button.top, greaterThanOrEqualTo(value.bottom));
    expect(value.width, greaterThan(150));
    expectReadable(tester);
  });

  testWidgets('wide screen: one line, value on the right', (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
      DiagLineRow(line: (block: 'b', label: 'Cloudflare Access', value: 'connecté · sdubos@gmail.com', state: 'green'),
          action: TextButton(onPressed: () {}, child: const Text('Renouveler'))),
    ]))));
    expect(find.byKey(const ValueKey('diag-line-narrow')), findsNothing);
    final label = tester.getRect(find.text('Cloudflare Access'));
    final value = tester.getRect(find.byType(SelectableText));
    expect(value.left, greaterThan(label.right));
    expect((value.top - label.top).abs(), lessThan(8));
  });

  testWidgets('Paramètres › Administration readable at 320 px', (tester) async {
    tester.view.physicalSize = const Size(320, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = AdminApi(server, client: MockClient((r) async {
      final p = r.url.path.replaceFirst('/api/v0.1', '');
      final body = switch (p) {
        '/transition' => {'active': true, 'until': '2026-12-31T23:00:00Z'},
        '/admin/mail' => {'delivery': 'simulated', 'host': null, 'port': null, 'sender': null,
          'missing': ['SARCADE_SMTP_HOST', 'SARCADE_SMTP_USER', 'SARCADE_SMTP_PASSWORD', 'SARCADE_SMTP_FROM']},
        _ => <String, dynamic>{},
      };
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
    }));
    const rights = MyRights(isServerAdmin: true, canAdminister: true, modulesKnown: true,
        adminRights: [{'right': 'server_admin', 'scope_group_id': null, 'scope_name': null},
          {'right': 'group_admin', 'scope_group_id': 'adrasec-78', 'scope_name': 'ADRASEC 78 Yvelines'}]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
      Builder(builder: (c) => AdminSection(server: server, rights: rights, api: api,
          row: (label, {help, required child}) => settingsRowLayout(c, label, help: help, child: child))),
    ]))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('admin-transition')), findsOneWidget);
    expectReadable(tester);
  });

  testWidgets('Échéances typed by the administrator, readable at 320 px', (tester) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, dynamic>? saved;
    final api = AdminApi(server, client: MockClient((r) async {
      if (r.method == 'PUT') saved = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
      final manual = saved?['items'] ?? [
        {'id': 'brevo-smtp', 'name': 'Clé SMTP Brevo', 'date': '2027-11-03', 'url': 'https://app.brevo.com/settings/keys/smtp', 'note': 'Expire aussi après 90 jours sans envoi'},
        {'id': 'domain', 'name': 'Domaine sarcade.org', 'date': null, 'url': null, 'note': null},
      ];
      return http.Response.bytes(utf8.encode(jsonEncode({'items': [], 'summary': {'worst': 'green', 'alerts': 0}, 'manual': manual})), 200,
          headers: {'content-type': 'application/json'});
    }));
    await tester.pumpWidget(MaterialApp(home: DeadlinesPage(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Clé SMTP Brevo'), findsOneWidget);
    expect(find.text('03/11/2027 · Expire aussi après 90 jours sans envoi'), findsOneWidget);
    expect(find.text('Date à saisir'), findsOneWidget);
    expectReadable(tester);
    await tester.tap(find.byKey(const ValueKey('deadline-item-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('deadline-note')), 'Chez le registraire');
    await tester.tap(find.byKey(const ValueKey('deadline-ok')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deadline-save')));
    await tester.pumpAndSettle();
    final items = (saved!['items'] as List).cast<Map>();
    expect(items[1]['note'], 'Chez le registraire');
    expect(items[1]['id'], 'domain');
    expect(find.text('Échéances enregistrées'), findsOneWidget);
  });
}
