// Lot 29 (5 Nov 2026): a touch outside a text field closes the keyboard on
// phones too.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/ui/keyboard.dart';

void main(){
  testWidgets('a touch outside the field closes the keyboard (Android)',(t) async {
    debugDefaultTargetPlatformOverride=TargetPlatform.android;
    final focus=FocusNode();
    await t.pumpWidget(MaterialApp(builder:(c,child)=>closeKeyboardOnTapOutside(child!),
      home:Scaffold(body:Column(children:[
        TextField(focusNode:focus),
        const SizedBox(key:Key('outside'),width:300,height:300),
      ]))));
    await t.tap(find.byType(TextField));
    await t.pump();
    expect(focus.hasFocus,isTrue);
    await t.tapAt(t.getCenter(find.byKey(const Key('outside'))));
    await t.pump();
    expect(focus.hasFocus,isFalse);
    expect(touchKeyboard,isTrue);
    debugDefaultTargetPlatformOverride=null;
    focus.dispose();
  });
}
