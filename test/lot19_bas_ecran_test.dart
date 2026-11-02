import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/link_weather_pill.dart';
import 'package:sarcade_app/src/features/map/map_bottom_line.dart';
import 'package:sarcade_app/src/features/map/sos_placement.dart';

// Lot 19, card « Téléphone : boutons du bas de la carte cachés par la barre
// de navigation »: ⓘ above the tab bar, scale on the line of « Suivi de
// position », bottom of the SOS disc level with it.

/// The phone map above the tab bar: the bottom line and the right column
/// (« Fond et affichage », position, SOS in its 56 box).
Widget _phone({required double badgeWidth})=>MaterialApp(home:Scaffold(body:Stack(children:[
  phoneBottomLine(badge:SizedBox(key:const ValueKey('badge'),width:badgeWidth,height:pillHeight),
    scale:const SizedBox(key:ValueKey('scale'),width:110,height:26)),
  mapColumnPlacement(compact:true,taking:false,card:false,bottom:mapColumnBottom(compact:true),
    child:const Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.end,children:[
      SizedBox(key:ValueKey('layers'),width:48,height:48),SizedBox(height:10),
      SizedBox(key:ValueKey('me'),width:48,height:48),SizedBox(height:16),
      SizedBox(key:ValueKey('sos'),width:56,height:56),
    ])),
])));

void main() {
  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('phone $width: scale on the right of « Suivi de position », SOS level with it', (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_phone(badgeWidth: 150));
      final badge = tester.getRect(find.byKey(const ValueKey('badge')));
      final scale = tester.getRect(find.byKey(const ValueKey('scale')));
      final sos = tester.getRect(find.byKey(const ValueKey('sos')));
      final layers = tester.getRect(find.byKey(const ValueKey('layers')));
      expect(badge.bottom, 700 - phoneBottomGap);
      expect(scale.left, greaterThanOrEqualTo(badge.right), reason: 'the scale does not cover « Suivi de position »');
      expect(scale.center.dy, closeTo(badge.center.dy, 0.5), reason: 'same line');
      expect(sos.bottom - sosDiscInset, closeTo(badge.bottom, 0.5), reason: 'bottom of the SOS disc on the line');
      expect(scale.right, lessThanOrEqualTo(sos.left), reason: 'the scale stays clear of the column');
      expect(layers.right, sos.right);
    });
  }

  testWidgets('narrow phone: a long « Suivi actif » shrinks, nothing overlaps', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_phone(badgeWidth: 260));
    expect(tester.takeException(), isNull);
    final badge = tester.getRect(find.byKey(const ValueKey('badge')));
    final scale = tester.getRect(find.byKey(const ValueKey('scale')));
    final sos = tester.getRect(find.byKey(const ValueKey('sos')));
    expect(scale.left, greaterThanOrEqualTo(badge.right));
    expect(scale.right, lessThanOrEqualTo(sos.left));
  });

  test('ⓘ above the tab bar and above « Suivi de position »', () {
    // Full screen: the map goes under the bar, the ⓘ is lifted by its height.
    expect(mapAttributionBottom(compact: true, fullBleed: true),
      phoneTabBarExtent + phoneBottomGap + pillHeight + 4);
    // A banner above the map: the map stops at the top of the bar.
    expect(mapAttributionBottom(compact: true, fullBleed: false), phoneBottomGap + pillHeight + 4);
    // Computer and tablet: unchanged.
    expect(mapAttributionBottom(compact: false, fullBleed: false), 0);
    expect(mapScaleBottom(compact: false), 44);
    expect(mapColumnBottom(compact: false), 24);
  });
}
