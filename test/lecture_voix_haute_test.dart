// Card « Messages : lecture à voix haute sur le téléphone » (validated on
// 5 Nov 2026, default choices; done on 9 Nov 2026).
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/read_aloud.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/message.dart';

void main() {
  setUp(() => S.setLanguage('fr'));

  test('never, in the car, always; Urgent and above by default', () {
    bool read(String mode, String prio, {bool car = false, bool routine = false}) =>
        shouldReadAloud(mode: mode, routineToo: routine, priority: prio, inCar: car);
    expect(read('never', 'distress', car: true), isFalse);
    expect(read('car', 'urgent'), isFalse, reason: 'not in a car');
    expect(read('car', 'urgent', car: true), isTrue);
    expect(read('car', 'routine', car: true), isFalse, reason: 'Routine only when asked');
    expect(read('car', 'routine', car: true, routine: true), isTrue);
    expect(read('always', 'immediate'), isTrue);
    expect(readAloudDefault, 'car');
  });

  test('in the car: a car screen, or faster than 20 km/h for 2 minutes', () {
    final r = ReadAloud.instance..carSession = false;
    final t = DateTime(2026, 11, 9, 22);
    r.noteSpeed(25 / 3.6, at: t);
    expect(r.inCar(now: t.add(const Duration(seconds: 30))), isTrue);
    expect(r.inCar(now: t.add(const Duration(minutes: 3))), isFalse, reason: 'speed too old');
    r.noteSpeed(10 / 3.6, at: t);
    expect(r.inCar(now: t), isFalse);
    r.carSession = true;
    expect(r.inCar(now: t), isTrue);
    r.carSession = false;
  });

  test('same sentence as Android Auto', () {
    final m = SarcadeMessage(id: 'm', eventId: 'e', senderId: 'android-demo', recipientIds: const ['user:x'],
        priority: 'urgent', body: 'Rejoignez P2.', createdAt: DateTime.utc(2026, 11, 9));
    expect(readAloudText(m), 'Urgent. android-demo : Rejoignez P2.', reason: 'one final dot, not two');
  });
}
