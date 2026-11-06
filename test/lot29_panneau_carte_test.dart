import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/basemaps/basemap_models.dart';
import 'package:sarcade_app/src/features/basemaps/basemap_sheet.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  setUp(()=>S.setLanguage('fr'));
  test('thumbnail tile around a point',(){
    final u=thumbTileUrl('https://tile.openstreetmap.org/{z}/{x}/{y}.png',48.8,2.13)!;
    expect(u,'https://tile.openstreetmap.org/14/8288/5640.png');
    expect(thumbTileUrl(null,48.8,2.13),isNull);
  });
  testWidgets('one panel « Carte »: thumbnails, no tabs, a touch chooses',(t) async {
    final chosen=<String>[];
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(c)=>TextButton(
      onPressed:()=>showBasemapSheet(c,catalog:builtInBasemaps,current:builtInBasemaps.first,eventDefault:'',preferOffline:false,
        onChoose:chosen.add,onPreferOffline:(_){}),
      child:const Text('open'))))));
    await t.tap(find.text('open')); await t.pumpAndSettle();
    expect(find.byType(TabBar),findsNothing);
    expect(find.text('Carte'),findsOneWidget);
    expect(find.text('Photos aériennes'),findsOneWidget);
    expect(find.text('Relief, sentiers, altitudes'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('basemap-topo'))); await t.pump();
    expect(chosen,['topo']);
    await t.tap(find.byKey(const ValueKey('basemap-close'))); await t.pumpAndSettle();
    expect(find.text('Photos aériennes'),findsNothing);
  });
}
