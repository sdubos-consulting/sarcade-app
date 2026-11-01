// TV, application side (1 Nov 2026): the screens of the « Écrans » button
// are read again when something changes elsewhere in the application.
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/tv/tv_screens_button.dart';

void main() {
  test('a pairing elsewhere bumps the notifier the button listens to', () {
    var calls = 0;
    void l() => calls++;
    tvScreensChanged.addListener(l);
    tvScreensChanged.value++;
    tvScreensChanged.removeListener(l);
    expect(calls, 1);
  });
  test('only active screens, mine unless PCO, by name', () {
    final all = [
      {'id': 'b', 'name': 'Salon', 'active': true, 'mine': true},
      {'id': 'a', 'name': 'atelier', 'active': true, 'mine': false},
      {'id': 'c', 'name': 'Vieille', 'active': false, 'mine': true},
    ];
    expect(tvButtonScreens(all, pco: false).map((d) => d['id']), ['b']);
    expect(tvButtonScreens(all, pco: true).map((d) => d['id']), ['a', 'b']);
  });
}
