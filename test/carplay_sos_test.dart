// Card « CarPlay : le bouton SOS n'apparaît pas » (validated on 9 Nov 2026):
// labels given to the car for the SOS row, « Mon statut » and « 1 non lu ».
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main() {
  setUp(() => S.setLanguage('fr'));

  test('« 1 non lu », « 3 non lus »', () {
    final l = carLabels();
    expect(l['unreadOne']!.replaceAll('{n}', '1'), '1 non lu');
    expect(l['unreadCount']!.replaceAll('{n}', '3'), '3 non lus');
  });

  test('labels of the SOS row and of « Mon statut » are given', () {
    final l = carLabels();
    for (final k in ['sos', 'sosEnd', 'sosAsk', 'sosSend', 'myStatus', 'myStatusLine', 'statusNone', 'noStatus',
      'statusCurrent', 'status.disponible', 'empty.team']) {
      expect(l[k], isNotNull, reason: k);
    }
  });

  test('CarPlay: SOS on top of every tab, « Mon statut » in Équipe, no navigation bar button', () {
    final swift = File('third_party/sarcade_car/ios/Classes/SarcadeCarPlaySceneDelegate.swift').readAsStringSync();
    expect(swift, contains('items.insert(sosItem(s), at: 0)'));
    expect(swift, contains('myStatusItem(s)'));
    expect(swift, isNot(contains('trailingNavigationBarButtons')), reason: 'not shown in a tab bar');
    expect(swift, contains('"type": "status"'));
  });
}
