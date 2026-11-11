// Card « Météo : limiter les appels à Météo-France (et aux autres sources
// météo) », validated on 10 Nov 2026: « Département suivi pour la
// vigilance » in Paramètres › Événement (choices 9 to 11) and the lines
// « Météo-France » of Diagnostic › Serveur (choices 4 and 5).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/features/settings/diagnostics_levels.dart';
import 'package:sarcade_app/src/features/settings/event_settings_section.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';

Map<String, dynamic> sources({String radar = 'ok', String vigilance = 'ok', String forecast = 'ok', bool key = true}) => {
  'weather_sources': {
    'day': '2026-11-10', 'key': key, 'active_events': 1,
    'sources': {
      'radar': {'state': radar, 'calls_today': 12, 'last_call_at': '2026-11-10T08:05:00Z', 'paused_until': radar == 'refused' ? '2026-11-10T14:05:00Z' : null},
      'vigilance': {'state': vigilance, 'calls_today': 288, 'last_call_at': '2026-11-10T08:10:00Z',
        'paused_until': vigilance == 'refused' || vigilance == 'rate_limited' ? '2026-11-10T14:10:00Z' : null, 'last_error': vigilance == 'refused' ? 'HTTP 403' : null},
      'forecast': {'state': forecast, 'calls_today': 24, 'last_error': forecast == 'error' ? 'HTTP 500' : null},
    },
  },
};

void main() {
  setUp(() => S.setLanguage('fr'));

  group('choice 10: department typed by the PCO', () {
    test('as the server checks it', () {
      expect(cleanDepartment(' 78 '), '78');
      expect(cleanDepartment('2a'), '2A');
      expect(cleanDepartment('974'), '974');
      expect(cleanDepartment('7'), isNull);
      expect(cleanDepartment('Yvelines'), isNull);
      expect(cleanDepartment(''), isNull);
    });

    test('value of the line: set, automatic with the departments followed, server default', () {
      expect(departmentValue({'department': '91'}, {'departments': ['78'], 'source': 'auto'}), '91');
      expect(departmentValue({}, {'departments': ['78', '92'], 'source': 'auto'}), 'Automatique (78, 92)');
      expect(departmentValue({'department': null}, {'departments': ['78'], 'source': 'server'}), 'Par défaut du serveur (78)');
      expect(departmentValue({}, {'departments': [], 'source': 'none'}), 'Automatique');
      expect(departmentValue({}, null), 'Automatique', reason: 'older server');
      S.setLanguage('en');
      expect(departmentValue({}, {'departments': ['78'], 'source': 'auto'}), 'Automatic (78)');
    });
  });

  group('choices 4 and 5: Météo-France in Diagnostic › Serveur', () {
    test('nothing with an older server', () {
      expect(weatherSourceLines({'level': 'admin'}), isEmpty);
    });

    test('radar active, vigilance refused, counters of the day', () {
      final lines = weatherSourceLines(sources(vigilance: 'refused'));
      expect(lines.map((l) => l.label), ['Météo-France', 'Prévisions (Open-Meteo)', 'Appels météo du jour']);
      expect(lines[0].value, startsWith('radar actif, vigilance refusée (clé non abonnée), reprise à '));
      expect(lines[0].value, contains('dernier appel à '));
      expect(lines[0].state, 'red');
      expect(lines[1].value, 'reçues');
      expect(lines[1].state, 'green');
      expect(lines[2].value, 'radar 12 · vigilance 288 · prévisions 24 · 1 événement actif');
      expect(lines[2].state, isNull);
    });

    test('card of 11 Nov 2026, choice 4: the API to subscribe on the portal', () {
      final d = sources(vigilance: 'refused');
      ((d['weather_sources'] as Map)['sources'] as Map)['vigilance']['refused_reason'] = 'not_subscribed';
      final lines = weatherSourceLines(d);
      expect(lines[0].value, startsWith('radar actif, API Vigilance non souscrite sur le portail Météo-France, nouvel essai à '));
      ((d['weather_sources'] as Map)['sources'] as Map)['vigilance']['refused_reason'] = 'key_refused';
      expect(weatherSourceLines(d)[0].value, contains('vigilance refusée (clé non abonnée)'));
      S.setLanguage('en');
      ((d['weather_sources'] as Map)['sources'] as Map)['vigilance']['refused_reason'] = 'not_subscribed';
      expect(weatherSourceLines(d)[0].value, contains('Vigilance API not subscribed on the Météo-France portal'));
    });

    test('limit reached, error, idle, no key', () {
      expect(weatherSourceLines(sources(vigilance: 'rate_limited'))[0].state, 'orange');
      expect(weatherSourceLines(sources(vigilance: 'rate_limited'))[0].value, contains('vigilance en pause (limite atteinte)'));
      expect(weatherSourceLines(sources(forecast: 'error'))[1].value, 'en erreur (HTTP 500)');
      expect(weatherSourceLines(sources(forecast: 'error'))[1].state, 'orange');
      final idle = weatherSourceLines(sources(radar: 'idle', vigilance: 'idle', forecast: 'idle'));
      expect(idle[0].value, startsWith('radar en veille (calque non affiché), vigilance non demandée (aucun événement actif)'));
      expect(idle[0].state, isNull);
      final noKey = weatherSourceLines(sources(key: false));
      expect(noKey[0].value, 'Clé absente');
      expect(noKey[0].state, 'off');
    });
  });

  testWidgets('choice 10: the PCO sets the department, then goes back to automatic', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var settings = <String, dynamic>{'department': null, 'modules': <String>[]};
    final patches = <Map<String, dynamic>>[];
    final client = MockClient((r) async {
      final p = r.url.path;
      if (p == '/api/v0.1/events/e1' && r.method == 'GET') {
        return http.Response(jsonEncode({'id': 'e1', 'name': 'Test NAS 1', 'settings': settings}), 200);
      }
      if (p == '/api/v0.1/events/e1/weather') {
        final d = settings['department'];
        return http.Response(jsonEncode({'forecast': null, 'vigilance': null,
          'vigilance_departments': d == null ? {'departments': ['78', '92'], 'source': 'auto'} : {'departments': [d], 'source': 'event'}}), 200);
      }
      if (p == '/api/v0.1/events/e1/settings' && r.method == 'PATCH') {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        patches.add(Map<String, dynamic>.from(body['settings'] as Map));
        settings = {...settings, ...patches.last};
        return http.Response(jsonEncode({'id': 'e1', 'name': 'Test NAS 1', 'settings': settings}), 200);
      }
      return http.Response('{}', 404);
    });
    final api = SarcadeApi(baseUrl: 'https://nas.example.org', client: client);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: EventSettingsSection(api: api, eventId: 'e1', actorId: 'PCO')))));
    await tester.pumpAndSettle();
    expect(find.text('Département suivi pour la vigilance'), findsOneWidget);
    expect(find.text('Automatique (78, 92)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('event-department')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('event-department-field')), 'Yv');
    await tester.tap(find.byKey(const ValueKey('event-department-apply')));
    await tester.pumpAndSettle();
    expect(find.text('2 ou 3 caractères : chiffres, ou 2A, 2B'), findsOneWidget);
    expect(patches, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('event-department-field')), '91');
    await tester.tap(find.byKey(const ValueKey('event-department-apply')));
    await tester.pumpAndSettle();
    expect(patches, [{'department': '91'}]);
    expect(find.text('91'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('event-department')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('event-department-auto')));
    await tester.pumpAndSettle();
    expect(patches.last, {'department': null});
    expect(find.text('Automatique (78, 92)'), findsOneWidget);
  });
}
