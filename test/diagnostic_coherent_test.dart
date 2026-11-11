// Card « Diagnostic : messages contradictoires quand le serveur n'est pas
// joint » (validated on 10 Nov 2026, choices 1 to 10): server cut, delay
// passed and Cloudflare access expired each give one clear message, the
// consequences in grey and not counted, no green dot that contradicts it,
// then « rétabli à … » without any action.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/access/access_manager.dart';
import 'package:sarcade_app/src/access/access_session.dart';
import 'package:sarcade_app/src/features/map/map_load_status.dart';
import 'package:sarcade_app/src/features/map/stations.dart' show ServerLink, serverLink;
import 'package:sarcade_app/src/features/settings/diagnostics_panel.dart' show DiagnosticsPanel, accessDiagLine;
import 'package:sarcade_app/src/features/settings/diagnostics_reach.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/offline/event_access.dart';
import 'package:sarcade_app/src/offline/local_store.dart';
import 'package:sarcade_app/src/offline/sync_service.dart';
import 'package:sarcade_app/src/services/power_state.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';
import 'package:sarcade_app/src/services/server_reach.dart';

const server = 'https://sarcade.example.org';
final at0923 = DateTime(2026, 11, 10, 9, 23);
final at0925 = DateTime(2026, 11, 10, 9, 25);
final at0927 = DateTime(2026, 11, 10, 9, 27);
final now = DateTime(2026, 11, 10, 9, 28);

class _Store extends LocalStore {
  @override List<Map<String, dynamic>> pending() => [];
  @override List<Map<String, dynamic>> pendingUploads() => [];
  @override String cursor(String eventId) => '0';
  @override Future<void> setCursor(String eventId, String cursor) async {}
}

/// Lines of the 10 Nov 2026 screenshots, server not reached.
List<ReachLine> screenshotLines(ServerReachState reach, AccessSession? session) {
  final lk = S.t('diag.links'), dev = S.t('diag.device');
  return [
    (block: dev, label: S.t('diag.gps'), value: 'activé', state: 'green'),
    (block: lk, label: S.t('diag.pending'), value: '0', state: 'green'),
    (block: lk, label: S.t('diag.realtime'), value: S.t('diag.connected'), state: 'green'),
    syncDiagLine(lk, okAt: at0923, failedAt: at0925, failure: reach.failure, now: now),
    responseDiagLine(lk, reach: reach, now: now),
    accessDiagLine(lk, web: false, session: session, client: null, failure: reach.failure),
    routingDiagLine(lk, reached: false, engine: false, device: true),
    (block: lk, label: 'MeshCore', value: 'reconnexion…', state: 'orange'),
    serverWaitingLine(S.t('diag.server'), reach, now: now),
  ];
}

ServerReachState failed(ServerFailure f) {
  ServerReach.instance.reset();
  ServerReach.instance.ok(server, at: DateTime(2026, 11, 10, 9, 20));
  ServerReach.instance.fail(server, f, at: at0923);
  ServerReach.instance.fail(server, f, at: at0925);
  return ServerReach.instance.of(server);
}

void main() {
  setUp(() {
    S.setLanguage('fr');
    ServerReach.instance.reset();
  });
  tearDown(() => ServerReach.instance.reset());

  group('exact reason of a failed call', () {
    test('delay, Cloudflare, refused, no connection, no network', () {
      String why(Object e, {bool online = true}) => serverFailureText(classifyServerError(e, online: online));
      expect(why(TimeoutException('x')), 'Délai dépassé (6 s)');
      expect(why(const AccessRequiredException(server)), 'Accès Cloudflare à renouveler');
      expect(why(const SarcadeHttpException('diagnostics', 502, 'Bad gateway')), 'Refusé par le serveur (HTTP 502)');
      expect(why(const SarcadeHttpException('diagnostics', 403, '<a href="https://team.cloudflareaccess.com/cdn-cgi/access/login">')),
        'Accès Cloudflare à renouveler');
      expect(why(const FormatException('Unexpected character', '<html>https://team.cloudflareaccess.com/login</html>')),
        'Accès Cloudflare à renouveler');
      expect(why(const FormatException('Unexpected character', '<html>other</html>')), 'Réponse inattendue du serveur');
      expect(why(http.ClientException('Connection refused')), 'Serveur injoignable (pas de connexion)');
      expect(why(http.ClientException('Failed host lookup'), online: false), 'Pas de réseau');
      S.setLanguage('en');
      expect(why(TimeoutException('x')), 'Timed out (6 s)');
    });
  });

  group('every call of the application tells whether the server answered', () {
    test('server cut: failing, then back at the next answer', () async {
      var down = true;
      final api = SarcadeApi(baseUrl: server, client: AccessHttpClient(inner: MockClient((r) async {
        if (down) throw http.ClientException('Connection refused', r.url);
        return http.Response('{"ip":"203.0.113.7"}', 200);
      })));
      await expectLater(api.clientDiagnostics(), throwsA(isA<http.ClientException>()));
      expect(ServerReach.instance.of(server).failure, const ServerFailure(ServerFailureKind.unreachable));
      expect(ServerReach.instance.of(server).failingSince, isNotNull);
      down = false;
      expect((await api.clientDiagnostics())?['ip'], '203.0.113.7');
      final back = ServerReach.instance.of(server);
      expect(back.failing, isFalse);
      expect(back.recoveredAt, isNotNull, reason: '« rétabli à … » without any action');
    });

    test('Cloudflare access expired: 302 to the sign-in page, not « injoignable »', () async {
      final api = SarcadeApi(baseUrl: server, client: AccessHttpClient(inner: MockClient((r) async =>
        http.Response('', 302, headers: {'location': 'https://team.cloudflareaccess.com/cdn-cgi/access/login/sarcade.example.org'}))));
      Object? error;
      try { await api.clientDiagnostics(); } catch (e) { error = e; }
      expect(error, isA<AccessRequiredException>());
      expect(ServerReach.instance.of(server).failure?.kind, ServerFailureKind.access);
      expect(serverFailureText(classifyServerError(error!)), 'Accès Cloudflare à renouveler');
    });

    test('Cloudflare sign-in page in HTML instead of the JSON', () async {
      final api = SarcadeApi(baseUrl: server, client: MockClient((r) async =>
        http.Response('<html><form action="https://team.cloudflareaccess.com/cdn-cgi/access/login"></form></html>', 200)));
      Object? error;
      try { await api.clientDiagnostics(); } catch (e) { error = e; }
      expect(classifyServerError(error!).kind, ServerFailureKind.access);
    });

    test('server error 502 behind Cloudflare: refused, with its code', () async {
      final api = SarcadeApi(baseUrl: server, client: AccessHttpClient(inner: MockClient((r) async => http.Response('Bad gateway', 502))));
      Object? error;
      try { await api.clientDiagnostics(); } catch (e) { error = e; }
      expect(serverFailureText(classifyServerError(error!)), 'Refusé par le serveur (HTTP 502)');
      expect(ServerReach.instance.of(server).failure, const ServerFailure(ServerFailureKind.http, 502));
    });
  });

  group('one cause at the top of « À vérifier »', () {
    for (final (name, f, text) in [
      ('server cut', const ServerFailure(ServerFailureKind.unreachable), 'Serveur injoignable (pas de connexion)'),
      ('delay passed', const ServerFailure(ServerFailureKind.timeout, 6), 'Délai dépassé (6 s)'),
      ('Cloudflare access expired', const ServerFailure(ServerFailureKind.access), 'Accès Cloudflare à renouveler'),
    ]) {
      test('$name: one clear message, consequences in grey, not counted', () {
        final reach = failed(f);
        final session = AccessSession.fromToken(_jwt());
        final all = screenshotLines(reach, session)
          ..removeWhere((l) => l.label == 'MeshCore');
        final cause = serverCauseLine(S.t('diag.links'), reach, now: now)!;
        expect(cause.value, '$text · depuis 09:23 · nouvel essai toutes les 30 s');
        final split = summaryProblems(all, cause: cause, accessCause: f.kind == ServerFailureKind.access);
        expect(split.problems, [cause], reason: 'a single message');
        expect(S.t('diag.problems', {'n': split.problems.length}), 'À vérifier (1)');
        expect(split.waiting.every((l) => l.state == 'off' && l.value == 'en attente du serveur'), isTrue);
        final waiting = split.waiting.map((l) => l.label).toList();
        expect(waiting, containsAll([S.t('diag.lastSync'), S.t('diag.routing'), S.t('diag.server')]));
        expect(waiting.contains(S.t('diag.response')), isFalse, reason: 'the cause says it');
        expect(waiting.contains(S.t('diag.access')), f.kind != ServerFailureKind.access);
        // No green line left about the server in Liaisons.
        final access = all.firstWhere((l) => l.label == S.t('diag.access'));
        expect(access.state, 'orange');
        if (f.kind == ServerFailureKind.access) expect(access.value, 'Accès Cloudflare à renouveler');
      });
    }

    test('« À vérifier (4) » of the screenshot becomes 2: the cause and MeshCore', () {
      final reach = failed(const ServerFailure(ServerFailureKind.timeout, 6));
      final all = screenshotLines(reach, null);
      final cause = serverCauseLine(S.t('diag.links'), reach, now: now)!;
      final split = summaryProblems(all, cause: cause);
      expect(split.problems.map((l) => l.label), [S.t('diag.server'), 'MeshCore']);
    });

    test('server reached: the problems as before, no cause', () {
      final lines = <ReachLine>[(block: 'L', label: 'MeshCore', value: 'x', state: 'orange'), (block: 'L', label: 'GPS', value: 'y', state: 'green')];
      expect(serverCauseLine('L', ServerReach.instance.of(server)), isNull);
      final split = summaryProblems(lines);
      expect(split.problems.map((l) => l.label), ['MeshCore']);
      expect(split.waiting, isEmpty);
    });
  });

  group('lines that follow from the server', () {
    test('response time: reason, then « rétabli à 09:27 »', () {
      final reach = failed(const ServerFailure(ServerFailureKind.timeout, 6));
      final l = responseDiagLine('L', reach: reach, now: now);
      expect(l.value, 'Non joint : Délai dépassé (6 s)');
      expect(l.state, 'red');
      ServerReach.instance.ok(server, at: at0927);
      final back = responseDiagLine('L', reach: ServerReach.instance.of(server), ms: 63, now: now);
      expect(back.value, '63 ms · rétabli à 09:27');
      expect(back.state, 'green');
      expect(showsRecovered(ServerReach.instance.of(server), now: at0927.add(const Duration(minutes: 61))), isFalse);
      expect(S.t('diag.serverRecovered', {'t': diagClock(at0927, now: now)}), 'Serveur rétabli à 09:27');
    });

    test('last synchronisation: success, or failure with its reason and the last success', () {
      expect(syncDiagLine('L', okAt: at0923, now: now).value, 'réussie à 09:23');
      expect(syncDiagLine('L', okAt: at0923, now: now).state, 'green');
      final f = syncDiagLine('L', okAt: at0923, failedAt: at0925, failure: const ServerFailure(ServerFailureKind.timeout, 6), now: now);
      expect(f.value, 'échec à 09:25 : délai dépassé (6 s) · dernière réussite à 09:23');
      expect(f.state, 'orange');
      expect(syncDiagLine('L', okAt: at0927, failedAt: at0925, now: now).value, 'réussie à 09:27');
      expect(diagClock(DateTime(2026, 11, 9, 22, 5), now: now), '09/11 22:05');
    });

    test('itinerary: grey while the server is not reached, orange only without engine', () {
      final off = routingDiagLine('L', reached: false, engine: false, device: true);
      expect(off.value, 'Sur l’appareil (serveur non joint)');
      expect(off.state, 'off');
      expect(routingDiagLine('L', reached: true, engine: false, device: true).state, 'orange');
      expect(routingDiagLine('L', reached: true, engine: true, device: true).state, 'green');
    });

    test('block « Serveur » and public address', () {
      final reach = failed(const ServerFailure(ServerFailureKind.unreachable));
      final l = serverWaitingLine(S.t('diag.server'), reach, now: now);
      expect(l.value, 'Non joint depuis 09:23');
      expect(l.state, 'off');
      expect(publicIpValue(null, reached: false), 'inconnue (serveur non joint)');
      expect(publicIpValue({'ip': '203.0.113.7'}, reached: true), '203.0.113.7');
    });

    test('Cloudflare line: green only while the calls succeed', () {
      final s = AccessSession.fromToken(_jwt());
      final ok = accessDiagLine('L', web: false, session: s, client: {'via_cloudflare': true, 'email': 'x'});
      expect(ok.state, 'green');
      final failing = accessDiagLine('L', web: false, session: s, client: null, failure: const ServerFailure(ServerFailureKind.timeout, 6));
      expect(failing.state, 'orange');
      expect(failing.value, endsWith('appels au serveur en échec'));
      final renew = accessDiagLine('L', web: false, session: s, client: null, refused: true);
      expect(renew.value, 'Accès Cloudflare à renouveler');
    });
  });

  group('link dot: orange as soon as a call fails, even with the real time open', () {
    test('serverLink', () {
      expect(serverLink(syncOk: true, realtime: true), ServerLink.direct);
      expect(serverLink(syncOk: true, realtime: true, callsFailing: true), ServerLink.slowed);
      expect(serverLink(syncOk: false, realtime: true, callsFailing: true), ServerLink.cut);
    });

    test('map dot', () {
      final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
      final d = mapLinkDot(started: true, map: MapLoadPhase.ok, access: EventAccess.ok, syncOk: true, realtime: true, scheme: scheme, callsFailing: true);
      expect(d.colour, Colors.orange);
      expect(d.word, 'Ralentie');
    });
  });

  group('synchronisation keeps the reason of its failure', () {
    test('server cut then back', () async {
      var down = true;
      final api = SarcadeApi(baseUrl: server, client: AccessHttpClient(inner: MockClient((r) async {
        if (down) throw http.ClientException('Connection refused', r.url);
        return http.Response('{"changes":[],"next_cursor":"0"}', 200);
      })));
      final sync = OfflineSyncService(api: api, store: _Store(), eventId: 'ev-1');
      await sync.syncNow();
      expect(sync.lastSyncOk, isFalse);
      expect(sync.lastSyncFailure, const ServerFailure(ServerFailureKind.unreachable));
      expect(sync.lastSyncFailedAt, isNotNull);
      expect(syncDiagLine('L', okAt: sync.lastSyncAt, failedAt: sync.lastSyncFailedAt, failure: sync.lastSyncFailure).state, 'orange');
      down = false;
      await sync.syncNow();
      expect(sync.lastSyncOk, isTrue);
      expect(syncDiagLine('L', okAt: sync.lastSyncAt, failedAt: sync.lastSyncFailedAt, failure: sync.lastSyncFailure).state, 'green');
      expect(ServerReach.instance.of(server).recoveredAt, isNotNull);
    });
  });

  testWidgets('Diagnostic, server cut: « À vérifier (1) », one cause with « Réessayer », then « rétabli à »', (tester) async {
    var down = true;
    final api = SarcadeApi(baseUrl: server, client: AccessHttpClient(inner: MockClient((r) async {
      if (down) throw http.ClientException('Connection refused', r.url);
      if (r.url.path.endsWith('/diagnostics/client')) return http.Response('{"ip":"203.0.113.7"}', 200);
      return http.Response('{}', 404);
    })));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: DiagnosticsPanel(api: api, server: server, eventId: 'ev-1')))));
    for (var i = 0; i < 20 && find.text('À vérifier (1)').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.text('À vérifier (1)'), findsOneWidget);
    expect(find.textContaining('Serveur injoignable (pas de connexion) · depuis'), findsOneWidget);
    expect(find.byKey(const ValueKey('diag-cause-retry')), findsOneWidget);
    // The server comes back: the next try (here « Réessayer ») says it.
    down = false;
    await tester.tap(find.byKey(const ValueKey('diag-cause-retry')));
    for (var i = 0; i < 20 && find.byKey(const ValueKey('diag-recovered')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('diag-all-good')), findsOneWidget);
    expect(find.textContaining('Serveur rétabli à'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('« Suivi de position arrêté » does not contradict « GPS activé » (choice 8)', () {
    expect(consumptionLine(trackingS: null, moving: true, reduced: false, compass: false, saver: false, t: S.t),
      'Suivi de position arrêté · boussole arrêtée');
    expect(S.t('version.upToDateLine'), 'Version à jour');
  });
}

String _jwt() {
  String part(Map<String, Object> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'RS256'})}.${part({'email': 'f1abc@example.org', 'exp': DateTime(2099).millisecondsSinceEpoch ~/ 1000})}.sig';
}
