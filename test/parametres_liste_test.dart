import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/config/app_config.dart';
import 'package:sarcade_app/src/features/settings/settings_list.dart';
import 'package:sarcade_app/src/features/settings/settings_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

// Card « Paramètres : moins d'onglets », option B (validated on 9 Nov 2026):
// a list, the header of the account opens « Mon profil », Diagnostic and
// À propos on two lines; computer: the list on the left, the page on the right.
const config = AppConfig(serverUrl: 'https://example.org', eventId: 'active-event', deviceId: 'PCO-iphone',
  callsign: 'F4ABC-7', tileUrl: 'https://tiles.example.org/{z}/{x}/{y}.png', tileAttribution: '© OpenStreetMap');

Future<void> size(WidgetTester t, double w, double h) async {
  t.view.physicalSize = Size(w, h); t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  setUp(() => S.setLanguage('fr'));

  testWidgets('iPhone: no tabs, the account then one line per section, all on one screen', (t) async {
    await size(t, 390, 844);
    await t.pumpWidget(MaterialApp(home: SettingsPage(initial: config, onSave: (_) async {})));
    await t.pumpAndSettle();
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('PCO-iphone · F4ABC-7'), findsOneWidget);
    for (final r in ['Cet appareil', 'Notifications', 'Diagnostic', 'À propos']) {
      expect(find.text(r), findsOneWidget, reason: r);
    }
    // No « Mon profil » line: the header opens it.
    expect(find.text('Mon profil'), findsNothing);
    expect(find.text('Enregistrer'), findsNothing);
    final last = t.getRect(find.byKey(const ValueKey('settings-row-about')));
    expect(last.bottom, lessThan(844));
  });

  testWidgets('a line opens its page with ←, ← comes back to the list', (t) async {
    await size(t, 390, 844);
    await t.pumpWidget(MaterialApp(home: SettingsPage(initial: config, onSave: (_) async {})));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('settings-row-general')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-page-title')), findsOneWidget);
    expect(find.text('example.org'), findsOneWidget);
    expect(find.text('Paramètres'), findsNothing);
    await t.tap(find.byKey(const ValueKey('settings-back')));
    await t.pumpAndSettle();
    expect(find.text('Paramètres'), findsOneWidget);
    expect(find.text('example.org'), findsNothing);
    await t.tap(find.byKey(const ValueKey('settings-row-profile')));
    await t.pumpAndSettle();
    expect(find.text('Mon profil'), findsOneWidget);
    expect(find.text('Sur la carte'), findsOneWidget);
  });

  testWidgets('computer: the list on the left, the page on the right', (t) async {
    await size(t, 1280, 800);
    await t.pumpWidget(MaterialApp(home: SettingsPage(initial: config, onSave: (_) async {})));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-list')), findsOneWidget);
    expect(find.text('example.org'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-back')), findsNothing);
    await t.tap(find.byKey(const ValueKey('settings-row-about')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-list')), findsOneWidget);
    expect(find.text('SDUBOS Consulting'), findsOneWidget);
  });

  test('title of the account: device and callsign, the device alone without one', () {
    expect(settingsAccountTitle('PCO', 'F4ABC-7'), 'PCO · F4ABC-7');
    expect(settingsAccountTitle('PCO', ' '), 'PCO');
  });
}
