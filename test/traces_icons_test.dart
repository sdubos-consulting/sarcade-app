// Traces as on aprs.fi and operator icons (1 Nov 2026).
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/operator_icons.dart';
import 'package:sarcade_app/src/features/map/traces_layer.dart';
import 'package:sarcade_app/src/models/position.dart';

SarcadePosition pos(String id, int min) => SarcadePosition(id: '$id-$min', eventId: 'e', deviceId: id, lat: 48.8 + min / 1000, lon: 2.1,
    time: DateTime.now().toUtc().subtract(Duration(minutes: 30 - min)));

void main() {
  test('icon chosen in SARCADE wins over the APRS one, linked by callsign', () {
    final devices = {
      'TEL-01': {'icon': 'car', 'callsign': 'F4XYZ'},
      'TEL-02': {'icon': 'rocket'},
    };
    expect(chosenIcon(devices, deviceId: 'TEL-01'), 'car');
    expect(chosenIcon(devices, callsign: 'F4XYZ-9'), 'car');
    expect(chosenIcon(devices, deviceId: 'TEL-02'), isNull);
    expect(chosenIcon(devices, callsign: 'F5SLR-9'), isNull);
    expect(operatorIconIds.every((i) => operatorIcon(i) != null), isTrue);
  });

  test('one dot per position, none when zoomed out', () async {
    final store = TracesStore(load: (id) async => [pos(id, 1), pos(id, 2), pos(id, 3)], onChanged: () {});
    await store.ensure(['TEL-01']);
    expect(traceDots(store, ['TEL-01'], windowMin: 60, zoom: 15).length, 3);
    expect(traceDots(store, ['TEL-01'], windowMin: 60, zoom: 10), isEmpty);
    final lines = store.polylines(['TEL-01'], windowMin: 60);
    expect(lines.first.strokeWidth, 5);
  });
}
