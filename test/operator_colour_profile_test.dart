// Card « Carte : la trace d'un opérateur dans la couleur choisie dans son
// profil » (validated on 10 Nov 2026, choices 1 to 8): the trace, the dot on
// the map and the line of Équipes follow the colour of the profile, on this
// device and on a second one; red refused; without a colour, the palette.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/features/map/stations.dart';
import 'package:sarcade_app/src/features/map/traces_layer.dart';
import 'package:sarcade_app/src/features/messages/conversations.dart' show authorColor;
import 'package:sarcade_app/src/features/messages/operator_avatar.dart';
import 'package:sarcade_app/src/features/poi/poi_sheet.dart' show poiFallbackColor;
import 'package:sarcade_app/src/features/profile/profile_photo.dart';
import 'package:sarcade_app/src/models/position.dart';
import 'package:sarcade_app/src/offline/local_store.dart';
import 'package:sarcade_app/src/offline/sync_service.dart';
import 'package:sarcade_app/src/operations/operations_service.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';
import 'package:sarcade_app/src/ui/operator_color.dart';

const green = 0xFF43A047, pink = 0xFFD81B60, red = 0xFFE53935;

SarcadePosition pos(String id, int min, {String source = 'device'}) => SarcadePosition(id: '$id-$min', eventId: 'e', deviceId: id,
    lat: 48.8 + min / 1000, lon: 2.1, time: DateTime.now().toUtc().subtract(Duration(minutes: 30 - min)), source: source);

/// Former formula, before the card: the colour of a device sharing none.
int formerPalette(String id) {
  const palette = [0xFFE53935, 0xFFFB8C00, 0xFF43A047, 0xFF1E88E5, 0xFF8E24AA, 0xFF00897B, 0xFFD81B60, 0xFF6D4C41, 0xFF3949AB, 0xFF7CB342];
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0x7FFFFFFF;
  }
  return palette[h % palette.length];
}

class _Store extends LocalStore {
  @override List<Map<String, dynamic>> pending() => [];
  @override Map<String, dynamic>? eventSettings(String eventId) => null;
  @override Future<void> saveEventSettings(String eventId, Map<String, dynamic> v) async {}
}

class _Api extends SarcadeApi {
  _Api() : super(baseUrl: 'https://app.sarcade.org', client: MockClient((_) async => http.Response('', 500)));
  final bodies = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> heartbeat(String eventId, String deviceId, Map<String, dynamic> body) async {
    bodies.add(body);
    return {};
  }
}

void main() {
  setUp(() => OperatorColors.instance.clear());
  tearDown(() => OperatorColors.instance.clear());

  test('without a colour shared, the former palette (choice 6)', () {
    for (final id in ['F4JPO', 'TEL-2', 'PC', 'aprs:F4ABC-9']) {
      expect(operatorColor(id), formerPalette(id));
      expect(authorColor(id), formerPalette(id));
    }
  });

  test('the trace takes the colour of the profile, and a change recolours it (choices 1 and 7)', () async {
    final traces = TracesStore(load: (id) async => [pos(id, 1), pos(id, 2), pos(id, 3)], onChanged: () {});
    await traces.ensure(['F4JPO']);
    OperatorColors.instance.learn('F4JPO', green);
    expect(traces.polylines(['F4JPO'], windowMin: 60).map((l) => l.color.withValues(alpha: 1).toARGB32()).toSet(), {green});
    OperatorColors.instance.learn('F4JPO', pink);
    expect(traces.polylines(['F4JPO'], windowMin: 60).map((l) => l.color.withValues(alpha: 1).toARGB32()).toSet(), {pink});
  });

  test('colour received from a second device: trace, dot and Équipes the same (choices 2 and 3)', () {
    // As brought by the list of the devices, device.updated or a position.
    OperatorColors.instance.learnAll([
      {'device_id': 'TEL-2', 'color': green},
      {'device_id': 'OLD'}, // former server: no key, nothing learned
    ]);
    expect(operatorColor('TEL-2'), green);
    expect(stationFillColor(pos('TEL-2', 3), aprs: Colors.amber).toARGB32(), green);
    expect(authorColor('TEL-2'), green);
    expect(operatorColor('OLD'), formerPalette('OLD'));
    // An APRS station keeps the APRS colour.
    expect(stationFillColor(pos('aprs:F4ABC', 3, source: 'aprs'), aprs: Colors.amber), Colors.amber);
    // Colour removed (null from the server): back to the palette.
    OperatorColors.instance.learnAll([{'device_id': 'TEL-2', 'color': null}]);
    expect(operatorColor('TEL-2'), formerPalette('TEL-2'));
  });

  test('the red stays for the SOS: a red profile gives the fallback (choice 4)', () {
    expect(isReservedRed(red), isTrue);
    expect(sharedOperatorColor(red), reservedRedFallback);
    expect(reservedRedFallback, poiFallbackColor);
    expect(sharedOperatorColor(green), green);
    expect(sharedOperatorColor(0x0043A047), green, reason: 'always opaque');
    OperatorColors.instance.learn('F4JPO', red);
    expect(operatorColor('F4JPO'), reservedRedFallback);
    expect(isReservedRed(operatorColor('F4JPO')), isFalse);
  });

  test('two operators may share a colour (choice 5)', () {
    OperatorColors.instance.learnAll([{'device_id': 'A', 'color': green}, {'device_id': 'B', 'color': green}]);
    expect(operatorColor('A'), operatorColor('B'));
    expect(operatorInitials('A'), isNot(operatorInitials('B')));
  });

  test('a position from the server carries the colour, kept in the cache', () {
    final p = SarcadePosition.fromJson({'id': 'p', 'event_id': 'e', 'device_id': 'TEL-2', 'lat': 48.8, 'lon': 2.1,
      'time': '2026-11-10T09:00:00Z', 'color': green});
    expect(p.color, green);
    expect(p.toJson()['color'], green);
    final former = SarcadePosition.fromJson({'id': 'p', 'event_id': 'e', 'device_id': 'TEL-2', 'lat': 48.8, 'lon': 2.1,
      'time': '2026-11-10T09:00:00Z'});
    expect(former.color, isNull);
    expect(former.toJson().containsKey('color'), isFalse);
  });

  test('learning notifies only on a change', () {
    var n = 0;
    void count() => n++;
    OperatorColors.instance.addListener(count);
    expect(OperatorColors.instance.learn('F4JPO', green), isTrue);
    expect(OperatorColors.instance.learn('F4JPO', green), isFalse);
    expect(OperatorColors.instance.learn('F4JPO', 'vert'), isTrue, reason: 'not a colour: forgotten');
    expect(OperatorColors.instance.of('F4JPO'), isNull);
    OperatorColors.instance.removeListener(count);
    expect(n, 2);
  });

  test('the heartbeat shares the colour of the profile (choice 2)', () async {
    final api = _Api(); final store = _Store();
    int? colour = green;
    final ops = OperationsService(api: api, store: store, sync: OfflineSyncService(api: api, store: store, eventId: 'e'),
      eventId: 'e', deviceId: 'F4JPO', platform: 'ios',
      tracking: () => (enabled: false, intervalS: 30),
      operator: () => (callsign: 'F4JPO', aprsTxConsent: false, icon: '', color: colour));
    await ops.beat();
    expect(api.bodies.last['color'], green);
    colour = null; // not known yet: nothing sent, the server keeps its value
    await ops.beat();
    expect(api.bodies.last.containsKey('color'), isFalse);
    ops.dispose();
  });

  testWidgets('the line of Équipes takes the colour of the operator (choice 3)', (t) async {
    ProfilePhotos.instance.value = {};
    OperatorColors.instance.learn('TEL-2', pink);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: operatorAvatar('TEL-2'))));
    final avatar = t.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundColor!.toARGB32(), pink);
  });
}
