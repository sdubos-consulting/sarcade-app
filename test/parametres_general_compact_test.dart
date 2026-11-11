// Card « Paramètres › Général : onglet compact » (validated on 5 Nov 2026,
// 19 h 27): sections Connexion, Cet appareil, Batterie; one line per
// setting with its value and « › »; help lines instead of ⓘ; « Nom de
// l'appareil »; each setting applied at once (server and event confirmed),
// no « Enregistrer ». Criterion: on an iPhone the tab fits on one screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/config/app_config.dart';
import 'package:sarcade_app/src/config/saved_servers.dart';
import 'package:sarcade_app/src/features/settings/settings_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/offline/local_store.dart';

const config = AppConfig(
  serverUrl: 'https://app.sarcade.org', eventId: 'e1', deviceId: 'PCO-Web',
  tileUrl: '', tileAttribution: '', language: 'fr',
);

class _Store extends LocalStore {
  final prefs = <String, String>{};
  @override String? preference(String key) => prefs[key];
  @override Future<void> setPreference(String key, String? v) async { if (v == null) { prefs.remove(key); } else { prefs[key] = v; } }
  @override Map<String, dynamic>? eventSettings(String eventId) => null;
}

final events = [
  {'id': 'e1', 'name': 'Test NAS 1', 'status': 'draft', 'created_at': '2026-11-02T10:00:00Z'},
  {'id': 'e2', 'name': 'Exercice départemental de recherche de balise', 'status': 'active', 'created_at': '2026-11-05T10:00:00Z'},
];

const servers = [
  SavedServer(url: 'https://app.sarcade.org', label: 'SARCADE · app.sarcade.org', lastEvent: 'e1'),
  SavedServer(url: 'http://192.168.0.110:8000', label: 'Club'),
];

Future<void> phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// Paramètres is a list since 9 Nov 2026 (option B): these tests open
// « Cet appareil » (former Général) directly.
Widget page({required List<AppConfig> saved, LocalStore? store, List<Map<String, dynamic>> Function(String)? load}) =>
  MaterialApp(home: (){settingsRequestedTab = 'general'; return SettingsPage(
    initial: config, store: store,
    onSave: (c) async => saved.add(c),
    loadEvents: (server) async => (load ?? (_) => events)(server),
    cachedEvents: (_) => events,
    readServers: () => servers, saveServers: (_) async {},
  );}());

void main() {
  setUp(() => S.setLanguage('fr'));
  tearDown(() => S.setLanguage('fr'));

  testWidgets('iPhone: sections, values on the right, no ⓘ nor « Enregistrer », on one screen', (tester) async {
    await phone(tester);
    final saved = <AppConfig>[];
    await tester.pumpWidget(page(saved: saved, store: _Store()));
    await tester.pumpAndSettle();
    for (final t in ['Connexion', 'Cet appareil', 'Batterie', 'Serveur', 'Événement suivi', 'Nom de l’appareil',
      'Vu par les autres participants', 'Application de navigation', 'Mode économie']) {
      // Inside the page « Cet appareil » (its title has the same words).
      expect(find.descendant(of: find.byKey(const ValueKey('settings-page-general')), matching: find.text(t)), findsOneWidget, reason: t);
    }
    expect(find.byKey(const ValueKey('settings-page-title')), findsOneWidget);
    expect(find.text('app.sarcade.org'), findsOneWidget);
    expect(find.text('Test NAS 1'), findsOneWidget);
    expect(find.text('Brouillon'), findsOneWidget);
    expect(find.text('PCO-Web'), findsOneWidget);
    expect(find.text('Demander à chaque fois'), findsOneWidget);
    expect(find.text('Terminal'), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsNothing);
    expect(find.text('Enregistrer'), findsNothing);
    expect(find.text('Annuler'), findsNothing);
    // Fits on the screen: the last line (power saving) is fully visible.
    final bottom = tester.getBottomLeft(find.byKey(const ValueKey('power-saver'))).dy;
    expect(bottom, lessThan(844));
    // Switch on the line of « Mode économie ».
    final sw = tester.getCenter(find.byKey(const ValueKey('power-saver'))).dy;
    expect(sw, greaterThan(tester.getTopLeft(find.text('Mode économie')).dy));
    expect(sw, lessThan(tester.getBottomLeft(find.textContaining('Suivi de position')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('event: list with states, confirmation, applied at once', (tester) async {
    await phone(tester);
    final saved = <AppConfig>[];
    await tester.pumpWidget(page(saved: saved));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('general-event')));
    await tester.pumpAndSettle();
    expect(find.text('Actif'), findsOneWidget);
    expect(find.text('Brouillon'), findsOneWidget);
    expect(find.text('Tirez la liste vers le bas pour la mettre à jour'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('event-item-e2')));
    await tester.pumpAndSettle();
    expect(find.text('Changer d’événement ?'), findsOneWidget);
    // Cancelled: nothing changes.
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.text('Test NAS 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('general-event')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('event-item-e2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('general-switch-ok')));
    await tester.pumpAndSettle();
    expect(saved.single.eventId, 'e2');
    expect(saved.single.serverUrl, 'https://app.sarcade.org');
    // Long name never cut.
    expect(find.text('Exercice départemental de recherche de balise'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server: list of servers, confirmation, then the event of that server', (tester) async {
    await phone(tester);
    final saved = <AppConfig>[];
    await tester.pumpWidget(page(saved: saved, load: (server) => server.contains('192.168')
      ? [{'id': 'c1', 'name': 'Club', 'status': 'active'}, {'id': 'c2', 'name': 'Club 2', 'status': 'draft'}]
      : events));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('general-server')));
    await tester.pumpAndSettle();
    expect(find.text('Serveurs mémorisés'), findsOneWidget);
    expect(find.byKey(const ValueKey('server-add')), findsOneWidget);
    expect(find.text('Club · 192.168.0.110:8000'), findsOneWidget);
    await tester.tap(find.text('Club · 192.168.0.110:8000'));
    await tester.pumpAndSettle();
    expect(find.text('Changer de serveur ?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('general-switch-ok')));
    await tester.pumpAndSettle();
    // No event known there: chosen in its list.
    await tester.tap(find.byKey(const ValueKey('event-item-c2')));
    await tester.pumpAndSettle();
    expect(saved.single.serverUrl, 'http://192.168.0.110:8000');
    expect(saved.single.eventId, 'c2');
  });

  testWidgets('« Nom de l’appareil » typed in a window, applied at once', (tester) async {
    await phone(tester);
    final saved = <AppConfig>[];
    await tester.pumpWidget(page(saved: saved));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('general-device')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('general-device-field')), 'PCO-Windows');
    await tester.tap(find.byKey(const ValueKey('general-device-ok')));
    await tester.pumpAndSettle();
    expect(saved.single.deviceId, 'PCO-Windows');
    expect(saved.single.eventId, 'e1');
  });

  testWidgets('navigation app chosen in a list, kept on the device without saving', (tester) async {
    await phone(tester);
    final saved = <AppConfig>[];
    final store = _Store();
    await tester.pumpWidget(page(saved: saved, store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-nav-app')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-app-waze')));
    await tester.pumpAndSettle();
    expect(store.prefs.values, contains('waze'));
    expect(find.text('Waze'), findsOneWidget);
    expect(saved, isEmpty);
  });

  test('no save bar on Général with nothing changed elsewhere', () {
    expect(settingsShowsSaveBar(tab: 'general', firstRun: false, dirty: false), isFalse);
    expect(settingsShowsSaveBar(tab: 'general', firstRun: true, dirty: false), isTrue);
    expect(settingsShowsSaveBar(tab: 'profile', firstRun: false, dirty: true), isTrue);
  });
}
