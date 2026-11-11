import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/config/app_config.dart';
import 'package:sarcade_app/src/features/help/help_page.dart';
import 'package:sarcade_app/src/features/help/markdown_lite.dart';
import 'package:sarcade_app/src/features/settings/settings_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/modules/registry.dart';

// Card « Paramètres : menu « Aide » (aide du Core, et une page d'aide par
// module actif) », validated on 10 Nov 2026, choice 7: « Aide » just above
// « À propos »; ADRASEC off, its line goes; each declared help file exists
// and opens.
const config = AppConfig(serverUrl: 'https://example.org', eventId: 'active-event', deviceId: 'PCO-iphone',
  callsign: 'F4ABC-7', tileUrl: 'https://tiles.example.org/{z}/{x}/{y}.png', tileAttribution: '© OpenStreetMap');

Future<void> size(WidgetTester t, double w, double h) async {
  t.view.physicalSize = Size(w, h); t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// The help is read from the bundle (real input/output): wait for it.
Future<void> loaded(WidgetTester t) async {
  for (var i = 0; i < 100 && find.byKey(const ValueKey('help-topic-premiers-pas')).evaluate().isEmpty; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
}

Widget page(Map<String, dynamic>? settings) =>
  MaterialApp(home: Scaffold(body: ListView(children: [HelpContent(eventSettings: settings)])));

void main() {
  setUp(() => S.setLanguage('fr'));

  test('« Aide » is the line just above « À propos »', () {
    for (final tabs in [settingsTabs(firstRun: false, event: true, admin: true), settingsTabs(firstRun: false, event: false)]) {
      expect(tabs.indexOf('help'), tabs.indexOf('about') - 1);
      expect(tabs.indexOf('diagnostics'), tabs.indexOf('help') - 1);
    }
  });

  testWidgets('iPhone: « Aide » between Diagnostic and À propos, with its summary', (t) async {
    await size(t, 390, 844);
    await t.pumpWidget(MaterialApp(home: SettingsPage(initial: config, onSave: (_) async {})));
    await t.pumpAndSettle();
    expect(find.text('Aide'), findsOneWidget);
    expect(find.text('Mode d’emploi, modules'), findsOneWidget);
    final diag = t.getRect(find.byKey(const ValueKey('settings-row-diagnostics')));
    final help = t.getRect(find.byKey(const ValueKey('settings-row-help')));
    final about = t.getRect(find.byKey(const ValueKey('settings-row-about')));
    expect(help.top, moreOrLessEquals(diag.bottom));
    expect(about.top, moreOrLessEquals(help.bottom));
    expect(about.bottom, lessThan(844));
    await t.tap(find.byKey(const ValueKey('settings-row-help')));
    await t.pumpAndSettle();
    await loaded(t);
    expect(find.byKey(const ValueKey('help-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('help-topic-carte')), findsOneWidget);
  });

  test('modules of the help: on for the event and allowed by the rights', () {
    expect(helpModules({'modules': ['adrasec']}, allows: (_) => true).map((m) => m.id), ['adrasec']);
    expect(helpModules({'modules': <String>[]}, allows: (_) => true), isEmpty);
    expect(helpModules({'modules': ['adrasec']}, allows: (_) => false), isEmpty);
  });

  testWidgets('ADRASEC on: its line opens its topics', (t) async {
    await size(t, 800, 4000);
    await t.pumpWidget(page({'modules': ['adrasec']}));
    await t.pumpAndSettle();
    await loaded(t);
    expect(find.byKey(const ValueKey('help-modules')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('help-module-adrasec')));
    await t.pumpAndSettle();
    expect(find.text('Aide ADRASEC'), findsOneWidget);
    final adrasec = appModules.firstWhere((m) => m.id == 'adrasec');
    for (final topic in adrasec.helpTopics) {
      expect(find.byKey(ValueKey('help-topic-$topic')), findsOneWidget, reason: topic);
    }
    await t.tap(find.byKey(ValueKey('help-topic-${adrasec.helpTopics.first}')));
    await t.pumpAndSettle();
    expect(find.byKey(ValueKey('help-page-${adrasec.helpTopics.first}')), findsOneWidget);
  });

  testWidgets('ADRASEC off: no « Modules » section, no ADRASEC line', (t) async {
    await t.pumpWidget(page({'modules': <String>[]}));
    await t.pumpAndSettle();
    await loaded(t);
    expect(find.byKey(const ValueKey('help-topic-premiers-pas')), findsOneWidget);
    expect(find.byKey(const ValueKey('help-modules')), findsNothing);
    expect(find.byKey(const ValueKey('help-module-adrasec')), findsNothing);
  });

  testWidgets('each topic of the Core opens on its page', (t) async {
    await size(t, 800, 4000);
    await t.pumpWidget(page({'modules': <String>[]}));
    await t.pumpAndSettle();
    await loaded(t);
    for (final topic in coreHelpTopics) {
      await t.tap(find.byKey(ValueKey('help-topic-$topic')));
      await t.pumpAndSettle();
      expect(find.byKey(ValueKey('help-page-$topic')), findsOneWidget, reason: topic);
      await t.pageBack();
      await t.pumpAndSettle();
    }
  });

  testWidgets('search: titles and texts, accents ignored; nothing found is said', (t) async {
    await t.pumpWidget(page({'modules': ['adrasec']}));
    await t.pumpAndSettle();
    await loaded(t);
    await t.enterText(find.byKey(const ValueKey('help-search')), 'resection');
    await t.pump();
    expect(find.byKey(const ValueKey('help-result-assets/help/adrasec/releves-resection.md')), findsOneWidget);
    expect(find.byKey(const ValueKey('help-topic-carte')), findsNothing);
    await t.enterText(find.byKey(const ValueKey('help-search')), 'zzqqxx');
    await t.pump();
    expect(find.byKey(const ValueKey('help-no-result')), findsOneWidget);
  });

  test('every declared help file exists, is declared in pubspec.yaml, has a title; no file left out', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = allHelpAssets();
    expect(declared.toSet().length, declared.length);
    for (final a in declared) {
      expect(File(a).existsSync(), isTrue, reason: a);
      expect(pubspec.contains('- ${a.substring(0, a.lastIndexOf('/') + 1)}'), isTrue, reason: a);
      final text = await rootBundle.loadString(a);
      expect(markdownTitle(text), isNotNull, reason: a);
      expect(parseMarkdownLite(text).length, greaterThan(2), reason: a);
    }
    final onDisk = Directory('assets/help').listSync(recursive: true).whereType<File>()
      .map((f) => f.path.replaceAll('\\', '/')).where((p) => p.endsWith('.md')).toSet();
    expect(onDisk, declared.toSet());
  });

  test('help texts of the Core name no outside organisation', () {
    for (final t in coreHelpTopics) {
      final text = File(helpAsset(coreHelpFolder, t)).readAsStringSync().toUpperCase();
      for (final word in ['ADRASEC', 'FNRASEC']) {
        expect(text.contains(word), isFalse, reason: '$t: $word');
      }
    }
  });

  test('Markdown reader: titles, paragraphs, lists, bold', () {
    final b = parseMarkdownLite('# Titre\n\nUne ligne\nsuite.\n\n## Sous-titre\n- un **gras**\n  suite\n1. premier\n2) second\n');
    expect(b.map((x) => x.kind), [MdKind.heading, MdKind.paragraph, MdKind.heading, MdKind.bullet, MdKind.numbered, MdKind.numbered]);
    expect(b[1].text, 'Une ligne suite.');
    expect(b[2].level, 2);
    expect(b[3].text, 'un **gras** suite');
    expect(b[5].level, 2);
    expect(markdownTitle('# Carte\ntexte'), 'Carte');
    expect(markdownPlain('un **gras**'), 'un gras');
    expect(markdownSpans('a **b** c', const TextStyle()).length, 3);
    expect(foldForSearch('Événement Œuvre'), 'evenement ouvre');
  });
}
