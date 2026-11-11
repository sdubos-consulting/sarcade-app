import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/config/app_config.dart';
import 'package:sarcade_app/src/features/basemaps/basemap_models.dart';
import 'package:sarcade_app/src/features/basemaps/basemap_sheet.dart';
import 'package:sarcade_app/src/features/settings/about_page.dart';
import 'package:sarcade_app/src/features/settings/diagnostics_panel.dart';
import 'package:sarcade_app/src/features/settings/settings_page.dart';
import 'package:sarcade_app/src/features/tools/tools_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/modules/adrasec/bearings/signal_defaults_tool.dart';
import 'package:sarcade_app/src/services/power_state.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';
import 'package:sarcade_app/src/ui/theme.dart';

const config = AppConfig(
  serverUrl: 'https://example.org', eventId: 'active-event', deviceId: 'TEST',
  tileUrl: '', tileAttribution: '', language: 'fr',
);

void main() {
  setUp(() => S.setLanguage('fr'));
  tearDown(() => S.setLanguage('fr'));

  testWidgets('diagnostics does not repeat Général', (tester) async {
    var saves = 0;
    await tester.pumpWidget(MaterialApp(home: SettingsPage(
      initial: config,
      onSave: (_) async { saves++; },
    )));
    // Paramètres is a list since 9 Nov 2026: « Cet appareil » (former
    // Général): server, event, device name.
    await tester.tap(find.byKey(const ValueKey('settings-row-general')));
    await tester.pumpAndSettle();
    expect(find.text('example.org'), findsOneWidget);
    expect(find.text('active-event'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-row-diagnostics')));
    await tester.pumpAndSettle();
    // Lot 19: Événement, Serveur, Terminal stay in Général; Main courante
    // is in Outils.
    expect(find.text('https://example.org'), findsNothing);
    expect(find.text('example.org'), findsNothing);
    expect(find.text('Main courante'), findsNothing);
    expect(find.text('active-event'), findsNothing);
    expect(saves, 0);
    await tester.tap(find.byKey(const ValueKey('settings-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-row-general')));
    await tester.pumpAndSettle();
    expect(find.text('active-event'), findsOneWidget);
    expect(saves, 0);
  });

  testWidgets('first setup offers About but no operational diagnostics', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SettingsPage(
      initial: config, firstRun: true, onSave: (_) async {},
    )));
    expect(find.text('Diagnostic'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
    await tester.tap(find.text('À propos'));
    await tester.pumpAndSettle();
    // Lot 29.4: « SDUBOS Consulting › » with its site under it.
    expect(find.text('SDUBOS Consulting'), findsOneWidget);
    expect(find.text('sdubos.com'), findsOneWidget);
  });

  testWidgets('theme: day, night or automatic, from « Fond et affichage » of the map', (tester) async {
    themeMode.value = ThemeMode.light;
    addTearDown(() => themeMode.value = ThemeMode.system);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => TextButton(
      onPressed: () => showBasemapSheet(c, catalog: builtInBasemaps, current: builtInBasemaps.first, eventDefault: '',
        preferOffline: false, onChoose: (_) {}, onPreferOffline: (_) {}),
      child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // One panel « Carte » (lot 29.2): base maps in thumbnails, then the
    // theme further down (built once scrolled to).
    await tester.scrollUntilVisible(find.byKey(const ValueKey('display-theme')), 300, scrollable: find.byType(Scrollable).last);
    expect(find.byKey(const ValueKey('display-theme')), findsOneWidget);
    await tester.ensureVisible(find.text('Nuit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuit'));
    await tester.pumpAndSettle();
    expect(themeMode.value, ThemeMode.dark);
    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    expect(themeMode.value, ThemeMode.system);
  });

  test('lot 19: no « Affichage » tab in Paramètres', () {
    expect(settingsTabs(firstRun: false, event: true), ['general', 'event', 'profile', 'notifications', 'diagnostics', 'help', 'about']);
    expect(settingsTabs(firstRun: false, event: false), ['general', 'profile', 'notifications', 'diagnostics', 'help', 'about']);
    expect(settingsTabs(firstRun: true, event: false), ['general', 'profile', 'about']);
  });

  testWidgets('no « Affichage » tab; power saving in Général', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SettingsPage(initial: config, onSave: (_) async {})));
    await tester.tap(find.byKey(const ValueKey('settings-row-general')));
    await tester.pumpAndSettle();
    expect(find.text('Affichage'), findsNothing);
    expect(find.text('Thème'), findsNothing);
    final saver = find.byKey(const ValueKey('power-saver'));
    await tester.ensureVisible(saver);
    await tester.pumpAndSettle();
    expect(find.text('Mode économie'), findsOneWidget);
    await tester.tap(saver);
    await tester.pumpAndSettle();
    expect(PowerState.instance.saver, isTrue);
    await PowerState.instance.setSaver(false);
  });

  testWidgets('language in Profil, applied at once (8 Nov 2026)', (tester) async {
    AppConfig? saved;
    await tester.pumpWidget(MaterialApp(home: SettingsPage(initial: config, onSave: (c) async { saved = c; })));
    // « Mon profil » opens from the header of the account (9 Nov 2026).
    await tester.tap(find.byKey(const ValueKey('settings-row-profile')));
    await tester.pumpAndSettle();
    final language = find.byKey(const ValueKey('settings-language'));
    await tester.ensureVisible(language);
    await tester.pumpAndSettle();
    expect(find.text('Langue de l’application'), findsOneWidget);
    await tester.tap(language);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    // No « Enregistrer »: the choice of the sheet is saved at once.
    expect(saved?.language, 'en');
  });

  testWidgets('first setup keeps the plain form, language in Profil', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SettingsPage(initial: config, firstRun: true, onSave: (_) async {})));
    expect(find.text('Affichage'), findsNothing);
    // Server, event, terminal: three plain fields.
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.byKey(const ValueKey('power-saver')), findsNothing);
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-language')), findsOneWidget);
  });

  test('copied report keeps Serveur and Terminal', () {
    final dev = S.t('diag.device'), lk = S.t('diag.links');
    final lines = reportLines([
      (block: dev, label: 'Version', value: '1', state: null),
      (block: lk, label: 'Temps réel', value: 'connecté', state: 'green'),
    ], server: 'https://example.org', device: 'TEST');
    expect(lines.map((l) => l.block).toList(), [dev, dev, dev, lk]);
    final text = diagnosticsReport(lines);
    expect(text, contains('Serveur : https://example.org'));
    expect(text, contains('Terminal : TEST'));
  });

  test('bearing frequencies in Outils (lot 29.5); Main courante no longer there (9 Nov 2026)', () {
    final api = SarcadeApi(baseUrl: 'https://example.org', client: MockClient((_) async => http.Response('{}', 200)));
    addTearDown(api.close);
    final opened = <String>[];
    void open(String id, Widget Function() _) => opened.add(id);
    // Porteur, 9 Nov 2026: Main courante in Paramètres › Diagnostic only.
    final map = File('lib/src/features/map/operational_map_page.dart').readAsStringSync();
    expect(map, isNot(contains('logbookToolItem(')));
    final diag = File('lib/src/features/settings/diagnostics_panel.dart').readAsStringSync();
    expect(diag, contains("ValueKey('diag-logbook-open')"));
    final signals = signalDefaultsToolItem(api: api, roles: {'admin'}, open: open)!;
    expect(signals.title, 'Fréquences du relevé');
    expect(signals.group, ToolGroup.module);
    expect(signalDefaultsToolItem(api: api, roles: {'pco'}, open: open), isNull);
    signals.onTap();
    expect(opened, ['signals']);
  });

  testWidgets('a refused field in a hidden tab is shown', (tester) async {
    var saves = 0;
    await tester.pumpWidget(MaterialApp(home: SettingsPage(
      initial: config, onSave: (_) async { saves++; },
    )));
    // Général has no field any more (card « onglet compact »): a wrong
    // callsign in Profil, saved from Général, shows Profil.
    await tester.tap(find.byKey(const ValueKey('settings-row-profile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'F4 ABC!');
    await tester.tap(find.byKey(const ValueKey('settings-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-row-general')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Indicatif invalide (ex. F4ABC ou F4ABC-7)'), findsOneWidget);
    expect(saves, 0);
  });

  testWidgets('About is translated and readable on a narrow screen with large text', (tester) async {
    S.setLanguage('en');
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: const SarcadeAboutPage(),
    ));
    expect(find.text('About SARCADE'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Component credits'), 300, scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });
}
