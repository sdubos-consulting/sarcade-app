import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/tv/tv_screen_buttons.dart';
import 'package:sarcade_app/src/features/tv/tv_screens_button.dart';
import 'package:sarcade_app/src/features/tv/tv_screens_page.dart';
import 'package:sarcade_app/src/features/tv/tv_view.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';

// Card « Afficher sur une TV : boutons directs au lieu du menu ⋮ » (lot 19):
// each button does what the entry of the menu does (choice 6).

Map<String, dynamic> screen({bool alert = false}) => {
  'id': 'a', 'name': 'TV PCO', 'code': 'ABC123', 'active': true, 'mine': true, 'theme': 'auto', 'messages': true,
  'alert': alert, 'can_clear_alert': true, 'last_seen': DateTime.now().millisecondsSinceEpoch / 1000,
};

/// Calls other than the list of the screens: « METHOD path body ».
var calls = <String>[];

SarcadeApi fakeApi({bool alert = false}) => SarcadeApi(baseUrl: 'https://s', client: MockClient((r) async {
  if (r.method == 'GET') return http.Response(jsonEncode([screen(alert: alert)]), 200);
  calls.add('${r.method} ${r.url.path} ${r.body}');
  return http.Response('{}', r.method == 'DELETE' ? 204 : 200);
}));

Future<void> setWidth(WidgetTester t, double width) async {
  t.view.physicalSize = Size(width, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> pumpPanel(WidgetTester t, double width, {bool alert = false}) async {
  await setWidth(t, width);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
    child: TvScreensPanel(api: fakeApi(alert: alert), eventId: 'e')))));
  await t.pumpAndSettle();
}

/// The call made by [act] on the panel at [width].
Future<String> panelCall(WidgetTester t, double width, Future<void> Function() act, {bool alert = false}) async {
  calls = [];
  await pumpPanel(t, width, alert: alert);
  await act();
  await t.pumpAndSettle();
  await t.pump(const Duration(seconds: 5));
  expect(calls, hasLength(1));
  return calls.single;
}

Future<void> tapMenu(WidgetTester t, String key, String entry) async {
  await t.tap(find.byKey(ValueKey(key)));
  await t.pumpAndSettle();
  await t.tap(find.text(entry).last);
  await t.pumpAndSettle();
}

const wide = 1000.0, phone = 400.0;

void main() {
  setUp(() => S.setLanguage('fr'));
  tearDown(() => currentMapView = null);

  test('mode of the screen: Jour → Nuit → Auto → Jour', () {
    expect(nextTvTheme('day'), 'night');
    expect(nextTvTheme('night'), 'auto');
    expect(nextTvTheme('auto'), 'day');
    expect(nextTvTheme('?'), 'day');
    expect(tvShowsSosButton({'alert': true}), isTrue);
    expect(tvShowsSosButton({'alert': true, 'can_clear_alert': false}), isFalse);
    expect(tvShowsSosButton({'alert': false}), isFalse);
    expect(tvMessagesShown({'messages': false}), isFalse);
    expect(tvMessagesShown({}), isTrue);
  });

  testWidgets('computer: the buttons on the line, the rare actions in ⋮', (t) async {
    await pumpPanel(t, wide);
    for (final k in ['tvb-view-a', 'tvb-identify-a', 'tvb-theme-a', 'tvb-messages-a']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    // No SOS: no red button.
    expect(find.byKey(const ValueKey('tvb-sos-a')), findsNothing);
    await t.tap(find.byKey(const ValueKey('tv-menu-a')));
    await t.pumpAndSettle();
    expect(find.text('Renommer'), findsOneWidget);
    expect(find.text('Revenir à la vue par défaut'), findsOneWidget);
    expect(find.text('Révoquer'), findsOneWidget);
    expect(find.text('Messages : masquer'), findsNothing);
    expect(find.text('Retirer le bandeau SOS'), findsNothing);
  });

  testWidgets('phone: only « Envoyer ma vue » leaves the menu', (t) async {
    await pumpPanel(t, phone, alert: true);
    expect(find.byKey(const ValueKey('tvb-view-a')), findsOneWidget);
    for (final k in ['tvb-identify-a', 'tvb-theme-a', 'tvb-messages-a', 'tvb-sos-a']) {
      expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
    }
  });

  testWidgets('Identifier: button = menu', (t) async {
    final button = await panelCall(t, wide, () => t.tap(find.byKey(const ValueKey('tvb-identify-a'))));
    final menu = await panelCall(t, phone, () => tapMenu(t, 'tv-menu-a', 'Identifier'));
    expect(button, 'POST /api/v0.1/events/e/displays/a/identify ');
    expect(menu, button);
  });

  testWidgets('mode: the button goes to the next one, as chosen in the menu', (t) async {
    final button = await panelCall(t, wide, () => t.tap(find.byKey(const ValueKey('tvb-theme-a'))));
    final menu = await panelCall(t, phone, () async {
      await tapMenu(t, 'tv-menu-a', 'Mode de l’écran');
      await t.tap(find.byKey(const ValueKey('tv-theme-day')));
    });
    expect(button, 'PUT /api/v0.1/events/e/displays/a/theme {"theme":"day"}');
    expect(menu, button);
  });

  testWidgets('Messages: button = menu', (t) async {
    final button = await panelCall(t, wide, () => t.tap(find.byKey(const ValueKey('tvb-messages-a'))));
    final menu = await panelCall(t, phone, () => tapMenu(t, 'tv-menu-a', 'Messages : masquer'));
    expect(button, 'PUT /api/v0.1/events/e/displays/a/messages {"messages":false}');
    expect(menu, button);
  });

  testWidgets('Retirer le bandeau SOS: red button during an SOS = menu', (t) async {
    final button = await panelCall(t, wide, () => t.tap(find.byKey(const ValueKey('tvb-sos-a'))), alert: true);
    final menu = await panelCall(t, phone, () => tapMenu(t, 'tv-menu-a', 'Retirer le bandeau SOS'), alert: true);
    expect(button, 'POST /api/v0.1/events/e/displays/a/alert/clear ');
    expect(menu, button);
  });

  testWidgets('Envoyer ma vue: the same summary then the view, on a computer and a phone', (t) async {
    currentMapView = () => (center: const LatLng(48.8, 2.1), zoom: 12.0, basemapId: 'osm', tileUrl: null, attribution: '', basemapName: 'OSM');
    for (final width in [wide, phone]) {
      final call = await panelCall(t, width, () async {
        await t.tap(find.byKey(const ValueKey('tvb-view-a')));
        await t.pumpAndSettle();
        await t.tap(find.text('Envoyer'));
      });
      expect(call, startsWith('PUT /api/v0.1/events/e/displays/a/view '));
    }
  });

  testWidgets('« Écrans » of the map: same buttons, same calls as its menu', (t) async {
    Future<String> sheetCall(double width, Future<void> Function() act, {List<String>? sent}) async {
      calls = [];
      await setWidth(t, width);
      final c = TvScreensController(api: fakeApi(alert: true), eventId: 'e');
      await t.runAsync(() => c.refresh(pco: true));
      await t.pumpWidget(MaterialApp(home: Scaffold(body: TvScreensSheet(controller: c,
        onSend: (to) async { sent?.addAll([for (final d in to) '${d['id']}']); }, onManage: () {}))));
      await t.pumpAndSettle();
      await act();
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 5));
      await t.pumpWidget(const SizedBox());
      c.dispose();
      return calls.join('\n');
    }

    expect(await sheetCall(wide, () => t.tap(find.byKey(const ValueKey('tvb-identify-a')))),
      await sheetCall(phone, () => tapMenu(t, 'tvb-menu-a', 'Identifier')));
    expect(await sheetCall(wide, () => t.tap(find.byKey(const ValueKey('tvb-messages-a')))),
      await sheetCall(phone, () => tapMenu(t, 'tvb-menu-a', 'Messages : masquer')));
    expect(await sheetCall(wide, () => t.tap(find.byKey(const ValueKey('tvb-sos-a')))),
      await sheetCall(phone, () => tapMenu(t, 'tvb-menu-a', 'Retirer le bandeau SOS')));
    expect(await sheetCall(wide, () => t.tap(find.byKey(const ValueKey('tvb-theme-a')))),
      'PUT /api/v0.1/events/e/displays/a/theme {"theme":"day"}');
    final sent = <String>[];
    await sheetCall(phone, () => t.tap(find.byKey(const ValueKey('tvb-view-a'))), sent: sent);
    expect(sent, ['a']);
  });
}
