import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/side_panels.dart';

// Lot 25, card « PC : le panneau Opérateurs se ferme au clic sur la carte ».

void main() {
  test('a touch on the map closes the panels on a phone only', () {
    expect(mapTapClosesSidePanels(compact: true), isTrue);
    expect(mapTapClosesSidePanels(compact: false), isFalse);
  });

  test('open or closed, kept from one start to the next on a wide screen', () {
    for (final p in SidePanel.values) {
      expect(sidePanelAtStart(sidePanelSaved(p), screenWidth: 1280), p);
      expect(sidePanelAtStart(sidePanelSaved(p), screenWidth: 900), p, reason: 'tablet in landscape');
    }
    expect(sidePanelSaved(null), isNull);
    expect(sidePanelAtStart(null, screenWidth: 1280), isNull, reason: 'closed by default');
    expect(sidePanelAtStart('unknown', screenWidth: 1280), isNull);
  });

  test('phone unchanged: the map first at start', () {
    expect(sidePanelAtStart('teams', screenWidth: 390), isNull);
    expect(sidePanelAtStart('messages', screenWidth: 599), isNull);
  });

  test('Messages beside the map: the map keeps room, two columns when possible', () {
    // Computer 1440 (rail of 80): the two-column layout of Messages.
    expect(messagesPanelWidth(1440 - 80), 900);
    // Window of 1280: still two columns, 300 left to the map.
    expect(messagesPanelWidth(1280 - 80), 900);
    // Tablet in portrait: a list, the map beside it.
    expect(messagesPanelWidth(820 - 80), 460);
    expect(820 - 80 - messagesPanelWidth(820 - 80), mapMinBesideMessages);
    // Very narrow: never under the width of a conversation panel.
    expect(messagesPanelWidth(600 - 80), 420);
  });
}
