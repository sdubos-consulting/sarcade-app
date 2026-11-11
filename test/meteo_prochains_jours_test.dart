// Card « Météo, Prochains jours : « Aujourd'hui » coupé, dernier jour
// incomplet, nuage jaune » (validated on 9 Nov 2026, choices 1 to 4).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/weather/weather_models.dart';
import 'package:sarcade_app/src/features/weather/weather_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

WeatherHour _h(DateTime t, double c, int code) => WeatherHour(time: t, temperatureC: c, weatherCode: code);

void main() {
  setUp(() => S.setLanguage('fr'));

  test('a later day covered for less than 12 h is left out, today always kept', () {
    final now = DateTime(2026, 11, 9, 23);
    final hours = [
      _h(DateTime(2026, 11, 9, 23), 6, 3),
      for (var h = 0; h < 24; h++) _h(DateTime(2026, 11, 10, h), 8.0 + h % 6, 3),
      _h(DateTime(2026, 11, 11, 0), 4, 2),
    ];
    final days = dailySummaries(hours, now);
    expect([for (final d in days) d.day.day], [9, 10]);
    expect(days.any((d) => d.min == d.max && d.day.day != 9), isFalse);
  });

  testWidgets('« Aujourd’hui » on one line, text twice as large', (t) async {
    final now = DateTime(2026, 11, 9, 10);
    final labels = [for (var i = 0; i < 5; i++) dayShort(DateTime(2026, 11, 9 + i), now)];
    await t.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size: Size(390, 800), textScaler: TextScaler.linear(2)),
      child: Scaffold(body: SizedBox(width: 360, child: LayoutBuilder(builder: (ctx, box) {
        final w = dayColumnWidth(ctx, labels, box.maxWidth);
        return Column(children: [
          for (final l in labels)
            Row(children: [
              SizedBox(width: w, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                  child: Text(l, maxLines: 1, softWrap: false))),
              const Expanded(child: SizedBox(height: 10)),
            ]),
        ]);
      }))),
    )));
    final today = find.text('Aujourd’hui');
    expect(today, findsOneWidget);
    final one = t.getSize(find.text('Demain')).height;
    expect(t.getSize(today).height, one, reason: 'one line, not « Aujourd’h / ui »');
    expect(t.takeException(), isNull);
  });

  testWidgets('« éclaircies »: a sun with a cloud; the cloud alone for « couvert »', (t) async {
    await t.pumpWidget(const MaterialApp(home: Row(children: [
      WeatherIcon('partly', size: 20),
      WeatherIcon('overcast', size: 20),
      WeatherIcon('partly', night: true, size: 20),
    ])));
    expect(find.byKey(const ValueKey('weather-partly')), findsOneWidget);
    expect(find.byIcon(Icons.wb_sunny), findsOneWidget);
    expect(find.byIcon(Icons.cloud), findsNWidgets(2));
    expect(find.byIcon(Icons.wb_cloudy), findsNothing);
    final sun = t.widget<Icon>(find.byIcon(Icons.wb_sunny));
    expect(sun.color, weatherColor('clear'));
  });
}
