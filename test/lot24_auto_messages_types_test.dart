// Android Auto, lot 24, card « Android Auto : messages types en un appui »:
// « Bien reçu », « J'arrive », « Besoin d'aide » (urgent), « Retard » by
// default; the list of the event set by the PCO (4 at most); in a
// conversation to whom « Répondre » answers, in the card of an order to the
// PCO.
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/comm_group.dart';
import 'package:sarcade_app/src/models/message.dart';

final now=DateTime.utc(2026,11,3,9,0);
final pcoChannel=CommGroup(id:'g-pco',eventId:'e',name:'PCO',kind:'default',createdBy:'PCO',updatedBy:'PCO',updatedAt:now);

CarScreenInput input({Map<String,dynamic> settings=const {}})=>CarScreenInput(me:'TEL-1',eventId:'e',now:now,settings:settings,
  groups:{'g-pco':pcoChannel},
  messages:[SarcadeMessage(id:'m1',eventId:'e',senderId:'PCO-Web',recipientIds:const ['user:TEL-1'],priority:'routine',
    body:'Allez au P2',createdAt:now.subtract(const Duration(minutes:2)))]);

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>S.setLanguage('fr'));

  test('defaults: Bien reçu, J’arrive, Besoin d’aide urgent, Retard',(){
    final q=carSnapshot(input())['quick'] as List;
    expect(q.map((x)=>(x as Map)['text']),['Bien reçu','J’arrive','Besoin d’aide','Retard']);
    expect(q.map((x)=>(x as Map)['priority']),['routine','routine','urgent','routine']);
    expect((q[2] as Map)['prioLabel'],'URGENT');
    S.setLanguage('en');
    expect(carQuickDefaults().map((x)=>x.text),['Received','On my way','Need help','Delayed']);
  });

  test('list of the event, 4 at most, damaged entries skipped',(){
    expect(carQuickMessages({'car_quick_messages':[
      {'text':'Sur zone','priority':'routine'},{'text':'','priority':'routine'},{'text':'Panne','priority':'distress'},
      {'text':'Renfort','priority':'urgent'},{'text':'A'},{'text':'B'},{'text':'C'},
    ]}).map((x)=>'${x.text} ${x.priority}'),['Sur zone routine','Renfort urgent','A routine','B routine']);
    expect(carQuickMessages({'car_quick_messages':null}).length,4);
    expect(carQuickMessages({'car_quick_messages':[]}).first.text,'Bien reçu');
  });

  test('sent in the conversation to the sender, from an order to the PCO, with its priority',() async {
    final sent=<String>[];
    final act=CarScreenActions(order:(o,s) async {},ack:(a,m) async {},sos:() async {},sosEnd:() async {},
      send:(m) async=>sent.add('${m.recipientIds.join(',')} ${m.priority} ${m.body}'));
    final conversation=carConversations(input()).keys.single;
    await applyCarAction(CarAction('quick',{'text':'Besoin d’aide','priority':'urgent','conversation':conversation}),input(),act);
    await applyCarAction(const CarAction('quick',{'text':'J’arrive','priority':'routine','order':'o1'}),input(),act);
    await applyCarAction(const CarAction('quick',{'text':'SOS','priority':'distress','order':'o1'}),input(),act);
    await applyCarAction(const CarAction('quick',{'text':'Bien reçu','conversation':'u:nobody'}),input(),act);
    expect(sent,['user:PCO-Web urgent Besoin d’aide','group:g-pco routine J’arrive']);
  });
}
