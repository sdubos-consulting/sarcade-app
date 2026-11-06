import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/ui/theme.dart';

void main(){
  test('headers: background of the screen, no tint on scroll, thin line',(){
    for(final t in [dayTheme(),nightTheme()]){
      expect(t.appBarTheme.backgroundColor,t.scaffoldBackgroundColor);
      expect(t.appBarTheme.surfaceTintColor,Colors.transparent);
      expect(t.appBarTheme.scrolledUnderElevation,0);
      expect(t.appBarTheme.shape,isA<Border>());
    }
  });
}
