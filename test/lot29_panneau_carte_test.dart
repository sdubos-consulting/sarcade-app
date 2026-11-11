import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/basemaps/basemap_models.dart';
import 'package:sarcade_app/src/features/basemaps/basemap_sheet.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  setUp(()=>S.setLanguage('fr'));
  // 9 Nov 2026: four tiles at zoom 13 around the point (one tile at 14
  // showed a field), with the identification of the app.
  test('thumbnail: four tiles at zoom 13 around a point',(){
    final u=thumbTileUrls('https://tile.openstreetmap.org/{z}/{x}/{y}.png',48.8,2.13)!;
    expect(u,['https://tile.openstreetmap.org/13/4143/2819.png','https://tile.openstreetmap.org/13/4144/2819.png',
      'https://tile.openstreetmap.org/13/4143/2820.png','https://tile.openstreetmap.org/13/4144/2820.png']);
    expect(thumbTileUrls(null,48.8,2.13),isNull);
    expect(thumbHeaders['User-Agent'],'flutter_map (org.sarcade.app)');
  });
  testWidgets('panel « Carte »: only the base map in use; its line opens the page of the base maps',(t) async {
    final chosen=<String>[];
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(c)=>TextButton(
      onPressed:()=>showBasemapSheet(c,catalog:builtInBasemaps,current:builtInBasemaps.first,eventDefault:'',preferOffline:false,
        onChoose:chosen.add,onPreferOffline:(_){}),
      child:const Text('open'))))));
    await t.tap(find.text('open')); await t.pumpAndSettle();
    expect(find.byType(TabBar),findsNothing);
    expect(find.text('Carte'),findsOneWidget);
    // Only the base map in use (OpenStreetMap), with « Changer de fond ».
    expect(find.text('OpenStreetMap'),findsOneWidget);
    expect(find.text('Photos aériennes'),findsNothing);
    expect(find.text('Changer de fond'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('basemap-current'))); await t.pumpAndSettle();
    // The page of the base maps: four lines, the chosen one with ✓.
    expect(find.text('Fond de carte'),findsOneWidget);
    expect(find.text('Photos aériennes'),findsOneWidget);
    expect(find.text('Relief, courbes de niveau, sentiers'),findsOneWidget);
    expect(find.byIcon(Icons.check),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('basemap-topo'))); await t.pumpAndSettle();
    expect(chosen,['topo']);
    // 9 Nov 2026: the panel is closed, back to the map.
    expect(find.text('Fond de carte'),findsNothing);
    expect(find.text('Carte'),findsNothing);
    expect(find.text('open'),findsOneWidget);
  });

  testWidgets('the base map already chosen closes the panel without changing anything; ← keeps it open',(t) async {
    final chosen=<String>[];
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(c)=>TextButton(
      onPressed:()=>showBasemapSheet(c,catalog:builtInBasemaps,current:builtInBasemaps.first,eventDefault:'',preferOffline:false,
        onChoose:chosen.add,onPreferOffline:(_){}),
      child:const Text('open'))))));
    await t.tap(find.text('open')); await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('basemap-current'))); await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('basemap-back'))); await t.pumpAndSettle();
    expect(find.text('Changer de fond'),findsOneWidget, reason:'← back to the panel, still open');
    await t.tap(find.byKey(const ValueKey('basemap-current'))); await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('basemap-${builtInBasemaps.first.id}'))); await t.pumpAndSettle();
    expect(chosen,isEmpty);
    expect(find.text('Fond de carte'),findsNothing);
  });
}
