import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/ui/bottom_menu.dart';

void main(){
  testWidgets('the safe area plus 16 px under the last row',(t) async {
    late double m;
    await t.pumpWidget(MediaQuery(data:const MediaQueryData(viewPadding:EdgeInsets.only(bottom:34)),
      child:Builder(builder:(c){m=bottomMenuMargin(c);return const SizedBox();})));
    expect(m,50);
  });
}
