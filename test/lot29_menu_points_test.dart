import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/ui/menu_entry.dart';
import 'package:sarcade_app/src/ui/theme.dart';

void main(){
  test('« … » menus: round corners, under their button',(){
    final t=dayTheme().popupMenuTheme;
    expect(t.shape,isA<RoundedRectangleBorder>());
    expect(t.position,PopupMenuPosition.under);
  });
  testWidgets('an entry: round icon, label, detail',(t) async {
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(c)=>menuEntry(c,icon:Icons.shield_outlined,color:Colors.blue,
      title:'Canaux ADRASEC',detail:'Ajoute les groupes du modèle')))));
    expect(find.byType(CircleAvatar),findsOneWidget);
    expect(find.text('Ajoute les groupes du modèle'),findsOneWidget);
  });
}
