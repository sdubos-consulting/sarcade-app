import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/ui/setting_line.dart';

void main(){
  // 9 Nov 2026, capture iPhone: « Stations « anciennes » après » wrapped on
  // three lines beside « 2 h » because the value always took half the line.
  testWidgets('a short value leaves the title the rest of the line',(tester) async {
    tester.view.physicalSize=const Size(390,844); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Padding(padding:const EdgeInsets.all(16),
      child:SettingLine(title:'Stations « anciennes » après',value:'2 h',onTap:(){})))));
    final title=tester.getSize(find.text('Stations « anciennes » après'));
    final value=tester.getSize(find.text('2 h'));
    expect(value.width,lessThan(60));
    // The test font is wide: the title wraps anyway, but now over the whole
    // line (before: at most half, about 170 px).
    expect(title.width,greaterThan(250));
  });
}
