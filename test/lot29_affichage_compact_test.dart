import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/layer_row.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  setUp((){S.setLanguage('fr');layerOpen.value=null;});
  testWidgets('no slider until the name is touched, one row open at a time',(t) async {
    await t.pumpWidget(MaterialApp(home:Scaffold(body:ListView(children:[
      LayerRow(label:'Opérateurs',on:true,onShown:(_){},opacity:1,onOpacity:(_){},icon:Icons.groups_outlined),
      LayerRow(label:'Dessins',on:true,onShown:(_){},opacity:0.5,onOpacity:(_){}),
    ]))));
    expect(find.byType(Slider),findsNothing);
    await t.tap(find.text('Opérateurs')); await t.pump();
    expect(find.byKey(const ValueKey('layer-slider-Opérateurs')),findsOneWidget);
    await t.tap(find.text('Dessins')); await t.pump();
    expect(find.byKey(const ValueKey('layer-slider-Opérateurs')),findsNothing);
    expect(find.byKey(const ValueKey('layer-slider-Dessins')),findsOneWidget);
    await t.tap(find.text('Dessins')); await t.pump();
    expect(find.byType(Slider),findsNothing);
  });
  testWidgets('a hidden layer has no slider; the detail opens with the name',(t) async {
    await t.pumpWidget(MaterialApp(home:Scaffold(body:ListView(children:[
      LayerRow(label:'Stations APRS',on:false,onShown:(_){},opacity:1,onOpacity:(_){},detail:const Text('radio')),
    ]))));
    await t.tap(find.text('Stations APRS')); await t.pump();
    expect(find.byType(Slider),findsNothing);
    expect(find.text('radio'),findsOneWidget);
  });
  testWidgets('long names are never cut',(t) async {
    await t.binding.setSurfaceSize(const Size(320,600));
    await t.pumpWidget(MaterialApp(home:Scaffold(body:ListView(children:[
      LayerRow(label:'Stations reçues par radio seulement, très long nom',on:true,onShown:(_){}),
    ]))));
    final text=t.widget<Text>(find.textContaining('Stations reçues'));
    expect(text.overflow,isNot(TextOverflow.ellipsis));
    await t.binding.setSurfaceSize(null);
  });
}
