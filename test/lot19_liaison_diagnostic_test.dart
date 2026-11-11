import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/features/map/map_load_status.dart';
import 'package:sarcade_app/src/features/settings/diagnostics_panel.dart' show diagnosticProblems;
import 'package:sarcade_app/src/features/settings/link_diagnostics.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/offline/event_access.dart';
import 'package:sarcade_app/src/offline/local_store.dart';
import 'package:sarcade_app/src/offline/sync_service.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';

// Card « Windows : pastille de liaison grise alors que le Diagnostic dit
// « Tout fonctionne » » (lot 19, points 1 to 5 of the card, 4, 7 and 9).

class _Store extends LocalStore {
  @override List<Map<String,dynamic>> pending()=>[];
  @override List<Map<String,dynamic>> pendingUploads()=>[];
  @override String cursor(String eventId)=>'0';
  @override Future<void> setCursor(String eventId,String cursor) async {}
}

class _Api extends SarcadeApi {
  _Api(this.status):super(baseUrl:'https://app.sarcade.org',client:MockClient((_) async=>http.Response('',500)));
  int? status;
  @override Future<({List<Map<String,dynamic>> changes,String nextCursor})> changes(String eventId,int after) async {
    final s=status;
    if(s!=null)throw SarcadeHttpException('changes',s,'{"detail":"unknown_event"}');
    return (changes:<Map<String,dynamic>>[],nextCursor:'0');
  }
}

void main() {
  setUp(() => S.setLanguage('fr'));
  tearDown(() => S.setLanguage('fr'));
  final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);

  group('synchronisation refused for the event', () {
    test('404: not a successful synchronisation, event unknown', () async {
      final api = _Api(404);
      final sync = OfflineSyncService(api: api, store: _Store(), eventId: 'ev-1');
      await sync.syncNow();
      expect(sync.lastSyncOk, isFalse);
      expect(sync.lastServerContact, isNotNull, reason: 'the server answered');
      expect(sync.eventAccess, EventAccess.unknown);
      expect(sync.eventUnknown, isTrue);
      expect(sync.eventRefusedStatus, 404);
      expect(sync.serverDown, isFalse);
      api.status = null;
      await sync.syncNow();
      expect(sync.lastSyncOk, isTrue);
      expect(sync.eventAccess, EventAccess.ok);
      expect(sync.eventRefusedStatus, isNull);
    });

    test('other codes: access refused', () async {
      final sync = OfflineSyncService(api: _Api(403), store: _Store(), eventId: 'ev-1');
      await sync.syncNow();
      expect(sync.lastSyncOk, isFalse);
      expect(sync.eventAccess, EventAccess.refused);
      expect(eventAccessOf(404), EventAccess.unknown);
      expect(eventAccessOf(401), EventAccess.refused);
      expect(eventAccessOf(500), EventAccess.refused);
    });
  });

  group('initial loading of the map', () {
    test('the reason is kept and written once to the log', () {
      final lines = <String>[];
      final map = MapLoadStatus(log: lines.add);
      expect(map.phase, MapLoadPhase.waiting);
      map.begin();
      expect(map.phase, MapLoadPhase.loading);
      map.failed(const SarcadeHttpException('positions', 404, '{"detail":"unknown_event"}'));
      map.failed(const SarcadeHttpException('positions', 404, '{"detail":"unknown_event"}'));
      expect(map.phase, MapLoadPhase.failed);
      expect(map.reason, 'HTTP 404 : {"detail":"unknown_event"}');
      expect(map.failures, 2);
      expect(lines, ['carte : échec du chargement initial (HTTP 404 : {"detail":"unknown_event"})']);
      map.failed(StateError('box closed'));
      expect(lines, hasLength(2));
      map.succeeded();
      expect(map.reason, isNull);
      expect(lines.last, 'carte : chargement initial réussi après 3 échec(s)');
    });

    test('long reasons are cut', () {
      expect(loadFailureReason(Exception('x' * 400)).length, 301);
      expect(loadFailureReason('a\n  b'), 'a b');
    });
  });

  group('link dot', () {
    test('grey only for the first seconds', () {
      final d = mapLinkDot(started: false, map: MapLoadPhase.loading, access: EventAccess.ok, syncOk: true, realtime: false, scheme: scheme);
      expect(d.colour, scheme.outline);
      expect(d.label, 'Connexion…');
      expect(d.word, isNull);
    });

    test('map not loaded while the server answers: orange « Carte non chargée »', () {
      final d = mapLinkDot(started: false, map: MapLoadPhase.failed, access: EventAccess.ok, syncOk: true, realtime: false, scheme: scheme);
      expect(d.colour, Colors.orange);
      expect(d.word, 'Carte non chargée');
    });

    test('event refused: orange with its word', () {
      expect(mapLinkDot(started: false, map: MapLoadPhase.failed, access: EventAccess.unknown, syncOk: false, realtime: false, scheme: scheme).word, 'Événement inconnu');
      expect(mapLinkDot(started: true, map: MapLoadPhase.ok, access: EventAccess.refused, syncOk: false, realtime: true, scheme: scheme).word, 'Accès refusé');
    });

    test('offline: « Coupée », not grey', () {
      final d = mapLinkDot(started: false, map: MapLoadPhase.failed, access: EventAccess.ok, syncOk: false, realtime: false, scheme: scheme);
      expect(d.colour, scheme.error);
      expect(d.word, 'Coupée');
    });

    test('everything works: green, no word', () {
      final d = mapLinkDot(started: true, map: MapLoadPhase.ok, access: EventAccess.ok, syncOk: true, realtime: true, scheme: scheme);
      expect(d.colour, const Color(0xFF2E9D4B));
      expect(d.word, isNull);
    });

    test('English words', () {
      S.setLanguage('en');
      expect(linkIssueWord(LinkIssue.mapNotLoaded), 'Map not loaded');
      expect(linkIssueWord(LinkIssue.eventUnknown), 'Unknown event');
      expect(S.t('diag.chooseEvent'), 'Choose an event');
    });
  });

  group('Diagnostic', () {
    test('« Tout fonctionne » only when the map is loaded and the real time open', () {
      final map = MapLoadStatus(log: (_) {})..succeeded();
      final ok = liveLinkLines('Liaisons', access: EventAccess.ok, map: map, realtime: true);
      expect(diagnosticProblems(ok), isEmpty);
      expect(ok.map((l) => '${l.label} : ${l.value}'), ['Chargement de la carte : OK', 'Temps réel : connecté']);
      // Real time disconnected is a problem now (orange, « Réessayer »).
      final rt = liveLinkLines('Liaisons', access: EventAccess.ok, map: map, realtime: false);
      expect(diagnosticProblems(rt).single.state, 'orange');
      expect(linkDiagAction(diagnosticProblems(rt).single), 'retry');
      // Real time never opened (the map did not start).
      expect(liveLinkLines('Liaisons', access: EventAccess.ok, map: map).last.state, 'orange');
    });

    test('event unknown: orange with « Choisir un événement »', () {
      final lines = liveLinkLines('Liaisons', access: EventAccess.unknown, refusedStatus: 404, map: MapLoadStatus(log: (_) {}), realtime: false);
      final event = lines.first;
      expect('${event.label} : ${event.value}', 'Événement : inconnu de ce serveur');
      expect(event.state, 'orange');
      expect(linkDiagAction(event), 'chooseEvent');
      final refused = eventAccessDiagLine('Liaisons', EventAccess.refused, status: 403)!;
      expect(refused.value, 'accès refusé (HTTP 403)');
      expect(eventAccessDiagLine('Liaisons', EventAccess.ok), isNull);
    });

    test('failed load, then success after « Réessayer »', () {
      final map = MapLoadStatus(log: (_) {});
      map.onRetry = () { map.begin(); map.succeeded(); };
      map.begin();
      expect(mapLoadDiagLine('Liaisons', map).value, 'en cours');
      expect(linkDiagAction(mapLoadDiagLine('Liaisons', map)), isNull);
      map.failed(const SarcadeHttpException('pois', 403));
      final failed = mapLoadDiagLine('Liaisons', map);
      expect(failed.value, 'échec : HTTP 403');
      expect(failed.state, 'orange');
      expect(linkDiagAction(failed), 'retry');
      expect(mapLinkDot(started: false, map: map.phase, access: EventAccess.ok, syncOk: true, realtime: false, scheme: scheme).word, 'Carte non chargée');
      map.retry();
      expect(mapLoadDiagLine('Liaisons', map).value, 'OK');
      expect(mapLoadDiagLine('Liaisons', map).state, 'green');
    });
  });
}
