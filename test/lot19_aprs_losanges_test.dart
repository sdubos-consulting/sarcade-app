import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/aprs_gateway.dart';
import 'package:sarcade_app/src/features/map/stations.dart';

// Lot 19, card « APRS : vrais symboles des stations sur la carte »,
// decision of 1 Nov 2026, 22 h 13: SARCADE icons kept, gateways (code `&`)
// as a diamond, red for LoRa, black for the others, white letter.

Future<void> _pump(WidgetTester tester, Widget? icon) =>
  tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: icon ?? const SizedBox()))));

void main() {
  test('gateways: red L, black I, black without a letter', () {
    expect(aprsGateway('L&'), (color: gatewayLoraRed, letter: 'L'));
    expect(aprsGateway('I&'), (color: gatewayBlack, letter: 'I'));
    expect(aprsGateway('R&'), (color: gatewayBlack, letter: 'R'));
    expect(aprsGateway(r'\&'), (color: gatewayBlack, letter: null));
    expect(aprsGateway('/&'), (color: gatewayBlack, letter: null));
  });

  test('not a gateway: the SARCADE icon stays', () {
    expect(aprsGateway('/>'), isNull);
    expect(aprsSymbol('/>').icon, Icons.directions_car);
    expect(gatewayStationIcon(symbol: '/>', isAprs: true, hasChosenIcon: false, size: 34), isNull);
    // Unknown symbol and no symbol: generic SARCADE antenna.
    expect(aprsGateway('/§'), isNull);
    expect(gatewayStationIcon(symbol: '/§', isAprs: true, hasChosenIcon: false, size: 34), isNull);
    expect(aprsSymbol('/§').icon, Icons.settings_input_antenna);
    expect(gatewayStationIcon(symbol: null, isAprs: true, hasChosenIcon: false, size: 34), isNull);
    expect(gatewayStationIcon(symbol: '&', isAprs: true, hasChosenIcon: false, size: 34), isNull);
  });

  test('an icon chosen in SARCADE wins; operators of the app are not APRS', () {
    expect(gatewayStationIcon(symbol: 'L&', isAprs: true, hasChosenIcon: true, size: 34), isNull);
    expect(gatewayStationIcon(symbol: 'L&', isAprs: false, hasChosenIcon: false, size: 34), isNull);
  });

  test('gateways readable with a finger: at least 30 px', () {
    expect(stationIconSize('L&', 20), gatewayMinSize);
    expect(stationIconSize('I&', 40), 40);
    expect(stationIconSize('/>', 20), 20);
  });

  testWidgets('L& : red diamond with a white L', (tester) async {
    await _pump(tester, gatewayStationIcon(symbol: 'L&', isAprs: true, hasChosenIcon: false, size: 34));
    final d = tester.widget<AprsGatewayDiamond>(find.byType(AprsGatewayDiamond));
    expect(d.color, gatewayLoraRed);
    expect(tester.getSize(find.byType(AprsGatewayDiamond)), const Size(34, 34));
    final paint = tester.widget<CustomPaint>(find.descendant(of: find.byType(AprsGatewayDiamond), matching: find.byType(CustomPaint)));
    expect((paint.painter! as AprsDiamondPainter).color, gatewayLoraRed);
    expect(tester.widget<Text>(find.text('L')).style!.color, Colors.white);
  });

  testWidgets('I& : black diamond with a white I', (tester) async {
    await _pump(tester, gatewayStationIcon(symbol: 'I&', isAprs: true, hasChosenIcon: false, size: 40));
    expect(tester.widget<AprsGatewayDiamond>(find.byType(AprsGatewayDiamond)).color, gatewayBlack);
    expect(tester.widget<Text>(find.text('I')).style!.color, Colors.white);
  });

  testWidgets(r'\& : black diamond without a letter', (tester) async {
    await _pump(tester, gatewayStationIcon(symbol: r'\&', isAprs: true, hasChosenIcon: false, size: 32));
    expect(tester.widget<AprsGatewayDiamond>(find.byType(AprsGatewayDiamond)).color, gatewayBlack);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('the diamond follows the opacity of the APRS layer', (tester) async {
    await _pump(tester, Opacity(opacity: 0.3, child: gatewayStationIcon(symbol: 'L&', isAprs: true, hasChosenIcon: false, size: 34)));
    final o = tester.widget<Opacity>(find.ancestor(of: find.byType(AprsGatewayDiamond), matching: find.byType(Opacity)).first);
    expect(o.opacity, 0.3);
  });
}
