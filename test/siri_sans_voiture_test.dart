// Card « CarPlay : demande d'autorisation « Communication » à Apple… »,
// choice 5a (9 Nov 2026): Siri works on the iPhone without CarPlay, so the
// car data are written even with no car session.
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/features/car/car_screen_channel.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => S.setLanguage('fr'));
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> updates;
  var active = false;

  setUp(() {
    updates = [];
    active = false;
    messenger.setMockMethodCallHandler(carScreenChannel, (call) async {
      if (call.method == 'update') updates.add(call.arguments as String);
      if (call.method == 'takeActions') return '[]';
      if (call.method == 'state') return active;
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(carScreenChannel, null));

  CarScreenBridge bridge({required bool siri}) => CarScreenBridge(enabled: true, siri: siri,
      read: () => CarScreenInput(me: 'TEL-1', eventId: 'e', now: DateTime.utc(2026, 11, 9, 12)),
      actions: CarScreenActions(order: (o, s) async {}, ack: (a, m) async {}, send: (m) async {},
          sos: () async {}, sosEnd: () async {}));

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('iPhone: written at start without a car, for Siri', () async {
    final b = bridge(siri: true)..start();
    await settle();
    expect(updates, hasLength(1));
    expect(b.active, isFalse);
    b.dispose();
  });

  test('Android: nothing written without Android Auto (unchanged)', () async {
    final b = bridge(siri: false)..start();
    await settle();
    expect(updates, isEmpty);
    b.dispose();
  });

  test('iPhone in the car: written at once, then the car pace', () async {
    active = true;
    final b = bridge(siri: true)..start();
    await settle();
    expect(b.active, isTrue);
    expect(updates, isNotEmpty);
    b.dispose();
  });
}
