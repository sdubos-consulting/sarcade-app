import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/aprs_gateway.dart';
import 'package:sarcade_app/src/features/map/aprs_symbol_view.dart';
import 'package:sarcade_app/src/features/map/stations.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

// Lot 25, card « APRS : symbole avec surcharge dessiné comme une simple
// lettre dans un carré » (F4HKS « oppo-reno »).

void main() {
  tearDown(() => S.setLanguage('fr'));

  test('the icon of the symbol is kept, the overlay goes to the badge', () {
    final car = aprsSymbol('L>');
    expect(car.icon, Icons.directions_car);
    expect(car.overlay, 'L');
    // Unknown symbol: antenna with the badge.
    final unknown = aprsSymbol('L~');
    expect(unknown.icon, Icons.settings_input_antenna);
    expect(unknown.overlay, 'L');
    // Primary and alternate tables: no badge.
    expect(aprsSymbol('/>').overlay, isNull);
    expect(aprsSymbol(r'\>').overlay, isNull);
  });

  test('gateways keep their diamond', () {
    expect(aprsGateway('L&')?.color, gatewayLoraRed);
    expect(aprsGateway('I&')?.color, gatewayBlack);
    expect(aprsGateway('L>'), isNull, reason: 'a car with an overlay is not a gateway');
  });

  test('the sheet says the symbol received in plain words', () {
    S.setLanguage('fr');
    expect(aprsSymbolLine('L>'), 'Symbole APRS : voiture, surcharge L');
    expect(aprsSymbolLine('/['), 'Symbole APRS : personne');
    expect(aprsSymbolLine(r'L~'), 'Symbole APRS : inconnu (L~), surcharge L');
    expect(aprsSymbolLine(null), isNull);
    expect(aprsSymbolLine('L'), isNull);
    S.setLanguage('en');
    expect(aprsSymbolLine('L>'), 'APRS symbol: car, overlay L');
  });

  test('every kind of symbol has a name in French and in English', () {
    const codes = r'>kuvj<b[afs^' "'" r'XO-_#&ryRU=';
    for (final lang in ['fr', 'en']) {
      S.setLanguage(lang);
      for (final c in codes.split('')) {
        final kind = aprsSymbol('/$c').kind;
        expect(S.t('aprs.symbol.kind.$kind'), isNot('aprs.symbol.kind.$kind'), reason: '$lang: $kind');
      }
    }
  });

  testWidgets('badge in the top right corner, inside the size of the icon', (tester) async {
    const size = 34.0;
    await tester.pumpWidget(MaterialApp(home: Center(child: Stack(clipBehavior: Clip.none, children: [
      const SizedBox(key: ValueKey('icon'), width: size, height: size, child: Icon(Icons.directions_car)),
      aprsOverlayCorner('L', size: size, color: Colors.blue, background: Colors.white),
    ]))));
    expect(find.byIcon(Icons.directions_car), findsOneWidget, reason: 'the icon is drawn');
    expect(find.text('L'), findsOneWidget);
    final icon = tester.getRect(find.byKey(const ValueKey('icon')));
    final badge = tester.getRect(find.byKey(const ValueKey('aprs-overlay-badge')));
    expect(badge.width, closeTo(aprsOverlayBadgeSize(size), 0.01));
    expect(badge.center.dx, greaterThan(icon.center.dx));
    expect(badge.center.dy, lessThan(icon.center.dy));
  });
}
