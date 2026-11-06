import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/ui/chevron_row.dart';

void main(){
  testWidgets('a whole line touchable, value before « › »',(t) async {
    var n=0;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:ChevronRow(icon:Icons.event_outlined,title:'Période de transition',
      value:'Sans date de fin',onTap:()=>n++))));
    expect(find.byIcon(Icons.chevron_right),findsOneWidget);
    expect(find.byType(OutlinedButton),findsNothing);
    await t.tap(find.text('Période de transition'));
    expect(n,1);
    final v=t.getRect(find.text('Sans date de fin')), c=t.getRect(find.byIcon(Icons.chevron_right));
    expect(v.right,lessThanOrEqualTo(c.left));
  });
}
