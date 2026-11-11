import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/locate_button.dart';
import 'package:sarcade_app/src/features/map/locate_cycle.dart';

void main(){
  test('north is up within 2 degrees',(){
    expect(northUp(0),isTrue); expect(northUp(1.9),isTrue); expect(northUp(358.5),isTrue); expect(northUp(-1),isTrue);
    expect(northUp(3),isFalse); expect(northUp(90),isFalse);
  });
  testWidgets('a turned map shows « N » on the position button',(t) async {
    Widget app(double? north)=>MaterialApp(home:Scaffold(body:LocateButton(mode:LocateMode.follow,north:north,northTooltip:'Nord',
      fab:(tip,icon,active)=>Tooltip(message:tip,child:icon))));
    await t.pumpWidget(app(45));
    expect(find.byType(NorthNeedle),findsOneWidget); expect(find.text('N'),findsOneWidget);
    await t.pumpWidget(app(null)); await t.pumpAndSettle();
    expect(find.byType(NorthNeedle),findsNothing);
  });
  testWidgets('compass mode: « N » shown, still blue; a turn by hand: « N » grey (8 Nov 2026)',(t) async {
    bool? blue;
    Widget app(LocateMode mode,double? north)=>MaterialApp(home:Scaffold(body:LocateButton(mode:mode,north:north,northTooltip:'Nord',
      fab:(tip,icon,active){blue=active;return Tooltip(message:tip,child:icon);})));
    await t.pumpWidget(app(LocateMode.compass,120));
    expect(find.byType(NorthNeedle),findsOneWidget); expect(blue,isTrue);
    await t.pumpWidget(app(LocateMode.course,30));
    expect(find.byType(NorthNeedle),findsOneWidget); expect(blue,isTrue);
    await t.pumpWidget(app(LocateMode.idle,45));
    expect(find.byType(NorthNeedle),findsOneWidget); expect(blue,isFalse);
  });
}
