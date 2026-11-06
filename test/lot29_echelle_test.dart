import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/map_scale.dart';

double _opacity(WidgetTester t)=>t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

void main(){
  test('only a real change of zoom shows the scale',(){
    expect(zoomChanged(null,12),isFalse); expect(zoomChanged(12,12.0001),isFalse); expect(zoomChanged(12,12.5),isTrue);
  });
  testWidgets('hidden, shown on zoom, gone 2 s later',(t) async {
    Widget app(double z,{bool always=false})=>MaterialApp(home:Scaffold(body:Center(child:FadingScale(zoom:z,latitude:48.8,always:always))));
    await t.pumpWidget(app(14)); expect(_opacity(t),0);
    await t.pumpWidget(app(15)); expect(_opacity(t),1);
    expect(find.textContaining(' m'),findsOneWidget);
    await t.pump(const Duration(seconds:2)); await t.pump(); expect(_opacity(t),0);
    await t.pumpWidget(app(15,always:true)); expect(_opacity(t),1);
  });
}
