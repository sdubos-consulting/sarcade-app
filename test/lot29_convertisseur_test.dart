import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/measure/coordinate_rows.dart';
import 'package:sarcade_app/src/features/tools/coordinate_converter_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  setUp(()=>S.setLanguage('fr'));
  testWidgets('one field, « En clair » first, actions on one row',(t) async {
    await t.binding.setSurfaceSize(const Size(390,1400));
    final asked=<LatLng>[];
    await t.pumpWidget(MaterialApp(home:CoordinateConverterPage(initial:const LatLng(48.8,2.13),
      describe:(p) async {asked.add(p);return '850 m au nord-est de Marnes-la-Coquette';},
      actions:ConverterActions(message:(_){},show:(_){}))));
    expect(find.text('Coordonnées'),findsOneWidget);
    expect(find.byKey(const ValueKey('converter-input')),findsOneWidget);
    expect(find.byKey(const ValueKey('converter-paste')),findsNothing);
    expect(find.text('…'),findsOneWidget,reason:'« En clair » waits 0.5 s');
    await t.pump(plainDelay); await t.pump();
    expect(find.text('850 m au nord-est de Marnes-la-Coquette'),findsOneWidget);
    expect(asked.length,1);
    expect(find.text('Tout copier'),findsOneWidget);
    expect(find.byIcon(Icons.record_voice_over_outlined),findsNothing,reason:'one ⋮ per row instead of icons');
    await t.binding.setSurfaceSize(null);
  });
  testWidgets('a format row: one line, the ⋮ menu',(t) async {
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:InfoRow(label:'DMS',value:'48°48\'00" N 2°07\'48" E',spell:true))));
    expect(find.byIcon(Icons.more_vert),findsOneWidget);
    expect(t.widget<Text>(find.textContaining('48°48')).maxLines,1);
  });
}
