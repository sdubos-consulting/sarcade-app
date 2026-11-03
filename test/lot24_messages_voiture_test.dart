import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/settings/car_quick_messages_editor.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

// Card « Android Auto : messages types en un appui » (lot 24), choice 2:
// list set by the PCO in Paramètres › Événement.

void main(){
  setUp(()=>S.setLanguage('fr'));
  tearDown(()=>S.setLanguage('fr'));

  test('list of the settings, defaults for an older server',(){
    expect(carQuickMessagesOf({}).map((m)=>m.text),['Bien reçu','J\'arrive','Besoin d\'aide','Retard']);
    expect(carQuickMessagesOf({}).where((m)=>m.priority=='urgent').single.text,'Besoin d\'aide');
    expect(carQuickMessagesOf({'car_quick_messages':['OK',{'text':'Aide','priority':'urgent'}]}),
      [(text:'OK',priority:'routine'),(text:'Aide',priority:'urgent')]);
  });

  test('checks of the server: 1 to 4, not empty, 40 characters, no duplicate',(){
    expect(carQuickMessagesProblem(const [(text:'Bien reçu',priority:'routine')]),isNull);
    expect(carQuickMessagesProblem(const []),'eventSettings.quickCar.count');
    expect(carQuickMessagesProblem(const [(text:'  ',priority:'routine')]),'eventSettings.quickCar.empty');
    expect(carQuickMessagesProblem([(text:'x'*41,priority:'routine')]),'eventSettings.quickCar.tooLong');
    expect(carQuickMessagesProblem(const [(text:'Retard',priority:'routine'),(text:'retard ',priority:'urgent')]),'eventSettings.quickCar.twice');
    expect(carQuickMessagesJson(const [(text:' J\'arrive  bientôt ',priority:'urgent')]),[{'text':'J\'arrive bientôt','priority':'urgent'}]);
  });

  Future<void> open(WidgetTester t,List<CarQuickMessage> initial) async {
    await t.pumpWidget(MaterialApp(home:Builder(builder:(c)=>Scaffold(body:TextButton(child:const Text('open'),
      onPressed:()=>Navigator.of(c).push<CarQuickMessagesResult>(MaterialPageRoute(builder:(_)=>CarQuickMessagesEditor(initial:initial))))))));
    await t.tap(find.text('open'));await t.pumpAndSettle();
  }

  testWidgets('editor: 4 at most, urgent, saved',(t) async {
    CarQuickMessagesResult? result;
    await t.pumpWidget(MaterialApp(home:Builder(builder:(c)=>Scaffold(body:TextButton(child:const Text('open'),
      onPressed:() async {result=await Navigator.of(c).push<CarQuickMessagesResult>(MaterialPageRoute(builder:(_)=>const CarQuickMessagesEditor(initial:defaultCarQuickMessages)));})))));
    await t.tap(find.text('open'));await t.pumpAndSettle();
    expect(find.text('Bien reçu'),findsOneWidget);
    // Already 4: no more.
    expect(t.widget<ButtonStyleButton>(find.byKey(const ValueKey('car-quick-add'))).onPressed,isNull);
    await t.tap(find.byKey(const ValueKey('car-quick-urgent-0')));await t.pump();
    await t.enterText(find.byType(TextField).at(3),'En retard');await t.pump();
    await t.tap(find.byKey(const ValueKey('car-quick-save')));await t.pumpAndSettle();
    expect(result!.reset,isFalse);
    expect(result!.messages![0],(text:'Bien reçu',priority:'urgent'));
    expect(result!.messages![3].text,'En retard');
  });

  testWidgets('editor: duplicate refused, « Rétablir » gives the defaults',(t) async {
    await open(t,const [(text:'Retard',priority:'routine')]);
    await t.tap(find.byKey(const ValueKey('car-quick-add')));await t.pump();
    await t.enterText(find.byType(TextField).at(1),'retard');await t.pump();
    expect(find.text('Deux messages identiques'),findsOneWidget);
    expect(t.widget<TextButton>(find.byKey(const ValueKey('car-quick-save'))).onPressed,isNull);
    await t.tap(find.byKey(const ValueKey('car-quick-reset')));await t.pumpAndSettle();
    expect(find.byType(CarQuickMessagesEditor),findsNothing);
  });
}
