import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/map_bottom_line.dart';
import 'package:sarcade_app/src/features/map/map_right_column.dart';
import 'package:sarcade_app/src/features/map/sos_placement.dart';

// Lot 25, card « Carte : aligner verticalement les boutons de la colonne de
// droite (réglages, position, SOS) »: centres on one axis (less than 1 px),
// regular gaps, SOS disc ending on the line of « Suivi de position » on
// every platform (point 7).

Widget _square(String key)=>SizedBox(key:ValueKey(key),width:48,height:48);

/// Same composition as `_mapButtons` of operational_map_page.dart.
Widget _column({required bool north,required bool label,required bool screens})=>Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.end,children:[
  mapColumnSlot(_square('layers')),
  const SizedBox(height:mapColumnGap),
  if(north)...[mapColumnSlot(_square('north')),const SizedBox(height:mapColumnGap)],
  // LocateButton: its short label (« Suivi »…) on the left of the button.
  Row(mainAxisSize:MainAxisSize.min,children:[
    if(label)const SizedBox(width:90,height:30),
    mapColumnSlot(_square('me')),
  ]),
  if(screens)Padding(padding:const EdgeInsets.only(top:mapColumnGap),child:mapColumnSlot(_square('screens'))),
  const SizedBox(height:mapColumnSosGap),
  const SizedBox(key:ValueKey('sos'),width:56,height:56),
]);

Widget _map({required bool compact,bool north=false,bool label=false,bool screens=false})=>MaterialApp(home:Scaffold(body:Stack(children:[
  mapColumnPlacement(compact:compact,taking:false,card:false,bottom:mapColumnBottom,
    child:_column(north:north,label:label,screens:screens)),
])));

void main() {
  final sizes = <(String, Size, bool)>[
    ('phone', const Size(390, 844), true),
    ('tablet', const Size(820, 1180), false),
    ('computer', const Size(1440, 900), false),
  ];
  for (final (name, size, compact) in sizes) {
    for (final extra in [false, true]) {
      testWidgets('$name${extra ? ', north, label and Écrans' : ''}: centres aligned, regular gaps, SOS on the bottom line', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_map(compact: compact, north: extra, label: extra, screens: extra));
        Rect r(String k) => tester.getRect(find.byKey(ValueKey(k)));
        final keys = ['layers', if (extra) 'north', 'me', if (extra) 'screens'];
        final sos = r('sos');
        // 1. Same vertical axis.
        for (final k in keys) {
          expect((r(k).center.dx - sos.center.dx).abs(), lessThan(1), reason: '$k centred on SOS');
        }
        // 2. Right margin of the widest button (SOS).
        expect(sos.right, size.width - 12);
        // 4. Same visible gap everywhere (the disc is 5 inside its box).
        for (var i = 1; i < keys.length; i++) {
          expect(r(keys[i]).top - r(keys[i - 1]).bottom, closeTo(mapColumnGap, 0.01), reason: '${keys[i - 1]} › ${keys[i]}');
        }
        expect((sos.top + sosDiscInset) - r(keys.last).bottom, closeTo(mapColumnGap, 0.01), reason: 'gap above the SOS disc');
        // 7. Bottom of the disc on the line of « Suivi de position ».
        expect(sos.bottom - sosDiscInset, closeTo(size.height - phoneBottomGap, 0.5));
      });
    }
  }

  test('one bottom for every platform', () {
    expect(mapColumnBottom, phoneBottomGap - sosDiscInset);
    expect(mapColumnSosGap, mapColumnGap - sosDiscInset);
  });
}
