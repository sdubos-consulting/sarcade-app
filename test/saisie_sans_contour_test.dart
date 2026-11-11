// Card « Saisie : zones de saisie sur fond coloré, sans contour, dans toute
// l'application » (validated on 10 Nov 2026, choices 1 to 8): one style in
// the theme, a coloured background, no line; no field draws its own border.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/ui/theme.dart';

Color _fill(ThemeData t,Set<WidgetState> states)=>WidgetStateProperty.resolveAs(t.inputDecorationTheme.fillColor!,states);

void main(){
  test('choice 8: no OutlineInputBorder outside theme.dart',(){
    final bad=<String>[];
    for(final f in Directory('lib').listSync(recursive:true).whereType<File>().where((f)=>f.path.endsWith('.dart'))){
      final path=f.path.replaceAll('\\','/');
      if(path=='lib/src/ui/theme.dart')continue;
      final lines=f.readAsLinesSync();
      for(var i=0;i<lines.length;i++){
        if(lines[i].contains('OutlineInputBorder')||lines[i].contains('UnderlineInputBorder'))bad.add('$path:${i+1}');
      }
    }
    expect(bad,isEmpty,reason:'Fields follow the theme (inputBorder, searchInputBorder):\n${bad.join('\n')}');
  });

  test('choices 1 to 3: filled, no line, corners 12, values of the simulation',(){
    for(final t in [dayTheme(),nightTheme()]){
      final d=t.inputDecorationTheme;
      expect(d.filled,isTrue);
      final b=d.border! as OutlineInputBorder;
      expect(b.borderSide,BorderSide.none);
      expect(b.borderRadius,BorderRadius.circular(12));
      // Enabled, focused, error… fall back on [border]: none set apart.
      expect([d.enabledBorder,d.focusedBorder,d.errorBorder,d.focusedErrorBorder,d.disabledBorder],everyElement(isNull));
    }
    final day=dayTheme(),night=nightTheme();
    expect(_fill(day,{}),const Color(0xFFDDE3EA));
    expect(_fill(night,{}),const Color(0xFF16212B));
    expect(_fill(day,{WidgetState.focused}),const Color(0xFFD3E3FD));
    expect(_fill(night,{WidgetState.focused}),const Color(0xFF0D2630));
    expect(_fill(day,{WidgetState.error}),const Color(0xFFFCE8E6));
    expect(_fill(night,{WidgetState.error,WidgetState.focused}),const Color(0xFF3A0E15));
    expect((searchInputBorder as OutlineInputBorder).borderSide,BorderSide.none);
  });

  testWidgets('a plain field is drawn with no line, label in the primary colour when focused',(tester)async{
    final focus=FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(theme:dayTheme(),home:Scaffold(body:TextField(focusNode:focus,decoration:const InputDecoration(labelText:'Indicatif')))));
    final deco=tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;
    expect(deco.border,inputBorder,reason:'the theme border, with no line');
    expect(deco.filled,isTrue);
    focus.requestFocus();
    await tester.pumpAndSettle();
    final label=tester.widget<Text>(find.text('Indicatif'));
    final style=DefaultTextStyle.of(tester.element(find.text('Indicatif'))).style.merge(label.style);
    expect(style.color,dayTheme().colorScheme.primary);
  });
}
