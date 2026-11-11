import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/orders/move_orders.dart';
import 'package:sarcade_app/src/features/poi/poi_icons.dart';
import 'package:sarcade_app/src/features/routes/routes_panel.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/ui/text_fields_dialog.dart';

// Card « Appliquer la correction des fenêtres de saisie (contrôleur détruit
// pendant la fermeture, assertion `_dependents.isEmpty`) » (lot 20): the
// windows own their text controllers, freed once the window is really gone.

/// Opens the window from a button; its answers go to [out].
Future<void> _open<T>(WidgetTester t,List<T?> out,Future<T?> Function(BuildContext) show) async {
  await t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(c)=>TextButton(
    onPressed:() async {out.add(await show(c));},child:const Text('go'))))));
  await t.tap(find.text('go'));
  await t.pumpAndSettle();
}

bool _alive(TextEditingController c){
  try{return ChangeNotifier.debugAssertNotDisposed(c);}on FlutterError{return false;}
}

/// Taps [button], checks the field keeps its controller during the closing
/// animation and that it is freed afterwards, without any error.
Future<void> _closeWith(WidgetTester t,Finder button) async {
  final ctl=t.widget<TextField>(find.byType(TextField).first).controller!;
  await t.tap(button);
  await t.pump();
  await t.pump(const Duration(milliseconds:40));
  expect(find.byType(TextField),findsWidgets,reason:'window still closing');
  expect(_alive(ctl),isTrue,reason:'controller kept while the window closes');
  await t.pumpAndSettle();
  expect(find.byType(AlertDialog),findsNothing);
  expect(_alive(ctl),isFalse,reason:'controller freed with the window');
  expect(t.takeException(),isNull);
}

void main(){
  setUp(()=>S.setLanguage('fr'));

  group('window owning its fields',(){
    testWidgets('OK gives the texts back, fields freed after the animation',(t) async {
      final out=<(String,String)?>[];
      await _open(t,out,(c)=>showTextFieldsDialog<(String,String)>(c,initial:const ['Pont','D30'],builder:(c,f,_)=>AlertDialog(
        content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:f[0]),TextField(controller:f[1])]),
        actions:[FilledButton(onPressed:()=>Navigator.pop(c,(f[0].text,f[1].text)),child:const Text('OK'))])));
      await t.enterText(find.byType(TextField).at(1),'D30 inondé');
      await _closeWith(t,find.text('OK'));
      expect(out,[('Pont','D30 inondé')]);
    });

    testWidgets('tap outside: null, no error',(t) async {
      final out=<String?>[];
      await _open(t,out,(c)=>showTextFieldsDialog<String>(c,initial:const ['x'],builder:(c,f,_)=>AlertDialog(content:TextField(controller:f[0]))));
      final ctl=t.widget<TextField>(find.byType(TextField)).controller!;
      await t.tapAt(const Offset(5,5));
      await t.pump(const Duration(milliseconds:40));
      expect(_alive(ctl),isTrue);
      await t.pumpAndSettle();
      expect(out,[null]);
      expect(_alive(ctl),isFalse);
      expect(t.takeException(),isNull);
    });
  });

  group('windows of the app',(){
    testWidgets('routes panel: label of a road closure',(t) async {
      final out=<String?>[];
      await _open(t,out,askClosureLabel);
      await t.enterText(find.byType(TextField),'Pont de la D30 inondé');
      await _closeWith(t,find.text('OK'));
      expect(out,['Pont de la D30 inondé']);
    });

    testWidgets('routes panel: closure cancelled',(t) async {
      final out=<String?>[];
      await _open(t,out,askClosureLabel);
      await _closeWith(t,find.text('Annuler'));
      expect(out,[null]);
    });

    testWidgets('point of interest created',(t) async {
      final out=<PoiDraft?>[];
      await _open(t,out,(c)=>showPoiDialog(c,pinColor:0xFF1E88E5,name:'Point 10:00'));
      await t.enterText(find.byKey(const ValueKey('poi-create-name')),'Gué');
      await _closeWith(t,find.byKey(const ValueKey('poi-create-ok')));
      expect(out.single?.name,'Gué');
    });

    testWidgets('move order: place and instruction',(t) async {
      final out=<MoveOrderDraft?>[];
      await _open(t,out,(c)=>showMoveOrderDialog(c,const [(id:'T1',label:'F4ABC',age:null)]));
      await t.enterText(find.byType(TextField).at(0),'Carrefour');
      await t.enterText(find.byType(TextField).at(1),'Attendre');
      await t.tap(find.byType(CheckboxListTile));
      await t.pump();
      await _closeWith(t,find.text('Envoyer l’ordre'));
      expect(out.single?.targets,['T1']);
      expect(out.single?.label,'Carrefour');
      expect(out.single?.note,'Attendre');
    });
  });
}
