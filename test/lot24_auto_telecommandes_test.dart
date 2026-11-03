// Android Auto, lot 24, card « Android Auto : télécommandes de relais depuis
// la voiture »: the remotes declared in the application (lot 21, unchanged)
// sent to the car with their relays and the questions of the confirmation;
// a command confirmed in the car goes through the same remote; the answer
// of the box (or its absence) is read aloud.
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/car/car_field.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_chat.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_protocol.dart';
import 'package:sarcade_app/src/features/remotes/remote.dart';
import 'package:sarcade_app/src/features/remotes/remote_meshcore.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

const boxKey='b0b1b2b3b4b5b6b7b8b9';
final now=DateTime.utc(2026,11,3,9,0);

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>S.setLanguage('fr'));

  late Remotes remotes;
  late List<String> codes;
  late bool fail;
  late DateTime clock;
  setUp(() async {
    codes=[]; fail=false; clock=now;
    remotes=Remotes()..autoExpire=false..actor=(()=>'TEL-1');
    remotes.links[RemoteTransport.meshcore]=meshCoreRemoteLink(ready:()=>true,send:(key,name,text) async {
      if(fail)throw StateError('no module');
      codes.add(text);
      return MeshCoreChatMessage(id:'${codes.length}',text:text,mine:true,at:clock,state:MeshCoreMsgState.sent);
    });
    await remotes.put(Remote(id:'rc-1',name:'Maurepas',target:boxKey,relays:[RemoteRelay.numbered(1),RemoteRelay.numbered(2)]));
  });

  CarField field()=>CarField(baseUrl:'https://s',eventId:'e',me:'TEL-1',remotes:remotes,clock:()=>clock,
    client:()=>throw StateError('no HTTP'),
    queue:({required String objectId,required String objectType,required Map<String,dynamic> payload,String action='create'}) async {});
  CarScreenInput input(CarField f)=>CarScreenInput(me:'TEL-1',eventId:'e',now:clock,field:f);
  final act=CarScreenActions(order:(o,s) async {},ack:(a,m) async {},send:(m) async {},sos:() async {},sosEnd:() async {});

  test('the remotes declared, their relays, the questions of the confirmation',(){
    final r=(carSnapshot(input(field()))['remotes'] as List).single as Map;
    expect(r['id'],'rc-1');
    expect(r['title'],'Maurepas');
    expect(r['ready'],isTrue);
    expect(r['text'],'2 relais · MeshCore connecté');
    final relay=(r['relays'] as List).first as Map;
    expect(relay['name'],'Relais 1');
    expect(relay['state'],'Inconnu');
    expect(relay['ask.on'],'Allumer Relais 1 de Maurepas ?');
    expect(relay['ask.off'],'Éteindre Relais 1 de Maurepas ?');
    // Nothing declared: an empty list, no row in the car.
    expect(carSnapshot(input(CarField(baseUrl:'s',eventId:'e',me:'TEL-1',remotes:Remotes(),
      queue:({required String objectId,required String objectType,required Map<String,dynamic> payload,String action='create'}) async {})))['remotes'],isEmpty);
  });

  test('a command confirmed in the car goes to the box; its answer read aloud',() async {
    final f=field();
    await applyCarAction(const CarAction('remote',{'id':'rc-1','relay':0,'on':true}),input(f),act);
    expect(codes,['1111#']);
    expect(f.said,isNull,reason:'answer awaited');
    clock=now.add(const Duration(seconds:4));
    remotes.onIncoming(RemoteTransport.meshcore,meshCorePrefix(boxKey),'Relais 1 activé',now:clock);
    await carFieldTick(input(f));
    expect(f.said!.text,'Maurepas : Relais 1 allumé · confirmé. Réponse du boîtier : Relais 1 activé.');
    final snap=carSnapshot(input(f));
    expect((snap['say'] as Map)['text'],f.said!.text);
    expect(carUrgentKey(snap),contains(f.said!.id));
    // A minute later, no longer sent to the car.
    clock=now.add(const Duration(minutes:2));
    expect(carSnapshot(input(f)).containsKey('say'),isFalse);
  });

  test('no answer in 30 s, or the module refused it: said too',() async {
    final f=field();
    await applyCarAction(const CarAction('remote',{'id':'rc-1','relay':1,'on':false}),input(f),act);
    expect(codes,['4444#']);
    clock=now.add(const Duration(seconds:31));
    remotes.expire(clock);
    await carFieldTick(input(f));
    expect(f.said!.text,'Maurepas : Relais 2 éteindre · pas de confirmation.');
    fail=true;
    await applyCarAction(const CarAction('remote',{'id':'rc-1','relay':0,'on':true}),input(f),act);
    expect(f.said!.text,'Maurepas : Relais 1 allumer · échec.');
  });

  test('unknown remote or relay, damaged action: nothing sent',() async {
    final f=field();
    await applyCarAction(const CarAction('remote',{'id':'rc-9','relay':0,'on':true}),input(f),act);
    await applyCarAction(const CarAction('remote',{'id':'rc-1','relay':5,'on':true}),input(f),act);
    await applyCarAction(const CarAction('remote',{'id':'rc-1','relay':0}),input(f),act);
    expect(codes,isEmpty);
  });
}
