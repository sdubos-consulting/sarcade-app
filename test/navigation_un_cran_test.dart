// Card « Navigation : la flèche retour remonte d'un seul cran sur tous les
// écrans », validated on 11 Nov 2026 (choice 4): open a sub-page, go back
// (← and Android Back), check that the parent is shown, not further.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/config/app_config.dart';
import 'package:sarcade_app/src/features/basemaps/basemap_models.dart';
import 'package:sarcade_app/src/features/basemaps/basemap_sheet.dart';
import 'package:sarcade_app/src/features/files/files_page.dart';
import 'package:sarcade_app/src/features/map/tab_navigator.dart';
import 'package:sarcade_app/src/features/settings/settings_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/modules/adrasec/resection/resection.dart';
import 'package:sarcade_app/src/modules/adrasec/resection/resection_panel.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';

const config = AppConfig(serverUrl: 'https://example.org', eventId: 'active-event', deviceId: 'TEST',
  tileUrl: '', tileAttribution: '', language: 'fr');

final tab = GlobalKey<NavigatorState>();

Future<void> pumpTab(WidgetTester t, Widget root) async {
  t.view.physicalSize = const Size(400, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: TabNavigator(navigatorKey: tab, root: root))));
  await t.pumpAndSettle();
}

Future<bool> androidBack(WidgetTester t) async {
  final f = tab.maybeBack();
  await t.pumpAndSettle();
  return f;
}

void main() {
  setUp(() => S.setLanguage('fr'));

  testWidgets('Paramètres: a page → the list, then nothing more in the tab', (t) async {
    await pumpTab(t, SettingsPage(initial: config, onSave: (_) async {}));
    await t.tap(find.byKey(const ValueKey('settings-row-general')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-back')), findsOneWidget);
    expect(await androidBack(t), isTrue, reason: 'handled inside Paramètres');
    expect(find.byKey(const ValueKey('settings-back')), findsNothing);
    expect(find.byKey(const ValueKey('settings-row-general')), findsOneWidget, reason: 'back on the list');
    expect(await androidBack(t), isFalse, reason: 'the list: the map is shown by the caller');
  });

  testWidgets('Fichiers: a folder → its parent → the root → Outils', (t) async {
    final api = SarcadeApi(baseUrl: 'https://s', client: MockClient((r) async {
      if (r.url.path.endsWith('/files')) return http.Response(jsonEncode({'files': [], 'folders': ['Secteurs', 'Secteurs/Nord']}), 200);
      return http.Response('[]', 200);
    }));
    await pumpTab(t, Builder(builder: (c) => TextButton(onPressed: () => tab.open(() => FilesPage(api: api, eventId: 'e', actorId: 'me')),
        child: const Text('Outils'))));
    await t.tap(find.text('Outils'));
    await t.pumpAndSettle();
    await t.tap(find.text('Secteurs').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Nord').first);
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    // The ← of the bar: one folder up.
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text('Nord'), findsWidgets, reason: 'in Secteurs, Nord listed');
    expect(await androidBack(t), isTrue);
    expect(find.byIcon(Icons.arrow_upward), findsNothing, reason: 'at the root of Fichiers');
    expect(find.text('Outils'), findsNothing);
    expect(await androidBack(t), isTrue);
    expect(find.text('Outils'), findsOneWidget, reason: 'Fichiers closed, back to Outils');
  });

  testWidgets('Carte panel: « Fond de carte » → the panel with Android Back', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => TextButton(
      onPressed: () => showBasemapSheet(c, catalog: builtInBasemaps, current: builtInBasemaps.first, eventDefault: 'osm',
          preferOffline: false, onChoose: (_) {}, onPreferOffline: (_) {}),
      child: const Text('open'))))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('basemap-current')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('basemap-back')), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('basemap-back')), findsNothing);
    expect(find.byKey(const ValueKey('basemap-current')), findsOneWidget, reason: 'the panel is still open');
  });

  testWidgets('Résection full screen: ← at the top left, no ✕', (t) async {
    var closed = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ResectionPanel(controller: ResectionController(), sites: const [],
      backArrow: true, onClose: () => closed++, onPickOnMap: (_) {}, onFocus: (_) {}, onCreatePoint: (_) {}, onSendPosition: (_) {}, onCopy: (_) {}))));
    await t.pump();
    final back = find.byKey(const ValueKey('resection-back'));
    expect(t.getTopLeft(back).dx, lessThan(20));
    await t.tap(back);
    expect(closed, 1);
  });
}
