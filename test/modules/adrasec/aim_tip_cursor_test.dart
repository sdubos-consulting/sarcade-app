// Relevé en modification : curseur en croix sur le bout de la flèche
// (validated 1 Nov 2026, 8 h 27).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/modules/adrasec/bearings/bearing_aim.dart';

void main(){
  testWidgets('the tip shows the precision cross, never the hand, and grows under the mouse',(t) async {
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:Center(child:SizedBox(width:44,height:44,
      child:AimTip(azimuthDeg:49,colour:Colors.blue))))));
    expect(aimTipCursor,SystemMouseCursors.precise);
    final region=t.widget<MouseRegion>(find.byKey(const ValueKey('aim-tip')));
    expect(region.cursor,SystemMouseCursors.precise);
    Size dot()=>t.getSize(find.descendant(of:find.byType(AimTip),matching:find.byType(Container)).last);
    expect(dot().width,8);
    final mouse=await t.createGesture(kind:PointerDeviceKind.mouse);
    await mouse.addPointer(location:Offset.zero);
    await mouse.moveTo(t.getCenter(find.byType(AimTip)));
    await t.pump();
    expect(dot().width,12);
    await mouse.moveTo(const Offset(5,5));
    await t.pump();
    expect(dot().width,8);
    await mouse.removePointer();
  });
}
