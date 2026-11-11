// Card « Écrans TV : page plus directe (découverte en tête, moins de texte,
// ménage des anciens) », validated on 11 Nov 2026 (choices 1 to 4, 6 to 9).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/features/tv/tv_nearby.dart';
import 'package:sarcade_app/src/features/tv/tv_screens_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';

final now = DateTime.now().millisecondsSinceEpoch / 1000;
Map<String, dynamic> screen(String id, {bool active = true, bool revoked = false}) => {
  'id': id, 'name': 'TV $id', 'code': 'COD${id.toUpperCase()}00', 'active': active, 'revoked': revoked, 'mine': true,
  'theme': 'auto', 'messages': true, 'alert': false, 'can_clear_alert': true, 'last_seen': now, 'expires': now + 3600,
};

var calls = <String>[];

SarcadeApi api({List<Map<String, dynamic>> screens = const [], List<Map<String, String>> nearby = const []}) =>
    SarcadeApi(baseUrl: 'https://s', client: MockClient((r) async {
      if (r.url.path == '/api/v0.1/tv/nearby') return http.Response(jsonEncode(nearby), 200);
      if (r.method == 'GET') return http.Response(jsonEncode(screens), 200);
      calls.add('${r.method} ${r.url.path}');
      return http.Response('{}', r.method == 'DELETE' ? 204 : 200);
    }));

Future<void> pump(WidgetTester t, SarcadeApi a) async {
  t.view.physicalSize = const Size(400, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: TvScreensPanel(api: a, eventId: 'e')))));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    S.setLanguage('fr');
    calls = [];
    tvDiscovery.value = true;
    TvNearbyGate.reset();
  });

  testWidgets('choices 1 and 6: no « Mes écrans » when empty, one sentence, no copy button', (t) async {
    await pump(t, api());
    expect(find.text('Mes écrans'), findsNothing);
    expect(find.text('Aucun écran appairé'), findsNothing);
    expect(find.byKey(const ValueKey('tv-how-to')), findsOneWidget);
    expect(find.textContaining('Sur la TV, ouvrez tv.sarcade.org puis'), findsOneWidget);
    expect(find.textContaining('Scannez le QR code ou saisissez'), findsNothing, reason: 'step 2 removed');
    expect(find.byIcon(Icons.copy_outlined), findsNothing, reason: 'choice 4');
    expect(find.byType(CircleAvatar), findsNothing, reason: 'no numbered steps');
    expect(find.byKey(const ValueKey('tv-type')), findsOneWidget);
  });

  testWidgets('choice 2: the TVs found nearby first, « Connecter », discovery at the bottom', (t) async {
    await pump(t, api(screens: [screen('a')], nearby: [{'code': 'XYZ789', 'name': 'TV Samsung · 1920×1080'}]));
    final near = find.byKey(const ValueKey('tv-nearby-XYZ789'));
    expect(near, findsOneWidget);
    expect(find.text('À proximité'), findsOneWidget);
    expect(t.getTopLeft(near).dy, lessThan(t.getTopLeft(find.text('Mes écrans')).dy), reason: 'at the top of the page');
    expect(t.getTopLeft(find.byKey(const ValueKey('tv-discovery'))).dy,
        greaterThan(t.getTopLeft(find.byKey(const ValueKey('tv-type'))).dy), reason: 'setting at the bottom');
    await t.tap(find.descendant(of: near, matching: find.text('Connecter')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('tv-name')), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(calls, ['POST /api/v0.1/tv/approve']);
  });

  testWidgets('discovery off: no section « À proximité »', (t) async {
    tvDiscovery.value = false;
    await pump(t, api(nearby: [{'code': 'XYZ789', 'name': 'TV'}]));
    expect(find.text('À proximité'), findsNothing);
  });

  testWidgets('choices 7 and 9: only the active screens, each with « Révoquer »; no « Anciens écrans »', (t) async {
    await pump(t, api(screens: [screen('a'), screen('b', active: false, revoked: true), screen('c', active: false)]));
    expect(find.byKey(const ValueKey('tv-screen-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-screen-b')), findsNothing);
    expect(find.byKey(const ValueKey('tv-screen-c')), findsNothing);
    expect(find.textContaining('Anciens écrans'), findsNothing);
    expect(find.byKey(const ValueKey('tv-show-old')), findsNothing);
    await t.tap(find.byKey(const ValueKey('tv-revoke-a')));
    await t.pumpAndSettle();
    expect(calls, ['DELETE /api/v0.1/events/e/displays/a']);
  });
}
