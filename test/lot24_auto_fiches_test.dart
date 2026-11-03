// Android Auto, lot 24: cards of the tabs.
// - card « Android Auto, onglet Équipe : fiche d'un opérateur avec
//   actions »: name and role, distance and direction, age of the position,
//   battery when known, last message received from him; « Écrire »
//   (dictated message to him);
// - card « Android Auto : fiches dans les onglets Points et Ordres »: card of
//   a point (type, distance and direction, altitude, author), « Je suis sur
//   place » and « Écrire au PCO » (to the PCO channel).
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/comm_group.dart';
import 'package:sarcade_app/src/models/message.dart';
import 'package:sarcade_app/src/models/poi.dart';
import 'package:sarcade_app/src/models/position.dart';

final now=DateTime.utc(2026,11,3,9,0);
const here=LatLng(48.80,1.95);

SarcadePosition pos(String device,{Duration age=const Duration(minutes:2),double lat=48.83})=>SarcadePosition(
  id:'p-$device',eventId:'e',deviceId:device,lat:lat,lon:1.95,time:now.subtract(age));

SarcadeMessage msg(String id,String from,List<String> to,String body,{int min=0,String priority='routine'})=>SarcadeMessage(
  id:id,eventId:'e',senderId:from,recipientIds:to,priority:priority,body:body,createdAt:now.subtract(Duration(minutes:min)));

final pcoChannel=CommGroup(id:'g-pco',eventId:'e',name:'PCO',kind:'default',createdBy:'PCO',updatedBy:'PCO',updatedAt:now);
final team1=CommGroup(id:'t1',eventId:'e',name:'Équipe 1',kind:'team',createdBy:'PCO',updatedBy:'PCO',updatedAt:now,members:const ['TEL-2']);

CarScreenInput input({List<SarcadeMessage> messages=const [],Map<String,Map<String,dynamic>> devices=const {},
    Map<String,CommGroup>? groups,LatLng? at=here})=>CarScreenInput(
  me:'TEL-1',eventId:'e',now:now,here:at,groups:groups??{'t1':team1,'g-pco':pcoChannel},messages:messages,devices:devices,
  pois:[SarcadePoi(id:'poi1',eventId:'e',kind:'designated',label:'P2',icon:'gathering',lat:48.83,lon:1.95,createdAt:now,createdBy:'PCO-Web')],
  references:const [(id:'h1',name:'Butte',relay:false,lat:48.80,lon:1.99,mhz:null,altM:412.4)],
  positions:[pos('TEL-2'),pos('PCO-Web',age:const Duration(minutes:20),lat:48.80)]);

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>S.setLanguage('fr'));

  group('card of an operator',(){
    test('role, distance and direction, age, battery, last message',(){
      final t=carTeam(input(
        devices:{'TEL-2':{'callsign':'F4ABC','battery_pct':80}},
        messages:[
          msg('m1','TEL-2',const [],'Je pars',min:30),
          msg('m2','TEL-2',const ['user:TEL-1'],'J’arrive',min:4,priority:'urgent'),
          msg('m3','TEL-2',const ['user:TEL-9'],'Pas pour moi',min:1),
          msg('m4','TEL-3',const [],'Autre',min:0),
        ]));
      final mate=t.firstWhere((x)=>x['id']=='TEL-2');
      expect(mate['role'],'Équipe 1 · F4ABC');
      expect(mate['away'],'3,5 km au nord');
      expect(mate['seen'],'vu il y a moins de 5 min');
      expect(mate['battery'],'Batterie 80 %');
      expect(mate['last'],'${_hm(now.subtract(const Duration(minutes:4)))} · URGENT · J’arrive');
    });

    test('PCO, nothing unknown',(){
      final pco=carTeam(input()).firstWhere((x)=>x['id']=='PCO-Web');
      expect(pco['role'],'PCO');
      expect(pco.containsKey('battery'),isFalse);
      expect(pco.containsKey('last'),isFalse);
      expect(pco['seen'],startsWith('position de'));
    });

    test('texts of the card, French and English',(){
      expect(carLabels()['write'],'Écrire');
      expect(carLabels()['writeTo'],'Message à {who}');
      S.setLanguage('en');
      expect(carLabels()['write'],'Write');
      expect(carLabels()['noPosition'],'Position unknown');
    });
  });

  group('card of a point',(){
    test('type, distance and direction, author; altitude of a high point',(){
      final p=carPoints(input());
      final poi=p.firstWhere((x)=>x['id']=='poi1'), high=p.firstWhere((x)=>x['id']=='h1');
      expect(poi['type'],'Rassemblement');
      expect(poi['away'],'3,5 km au nord');
      expect(poi['by'],'Créé par PCO-Web');
      expect(high['type'],'Point haut');
      expect(high['alt'],'Altitude 412 m');
      expect(high.containsKey('by'),isFalse);
    });
  });

  group('« Écrire »',(){
    late List<String> sent;
    late CarScreenActions act;
    setUp((){
      sent=[];
      act=CarScreenActions(order:(o,s) async {},ack:(a,m) async {},
        send:(m) async=>sent.add('${m.recipientIds.join(',')} ${m.priority} ${m.body} ${m.replyTo}'),
        sos:() async {},sosEnd:() async {});
    });

    test('a direct routine message to the operator',() async {
      await applyCarAction(const CarAction('write',{'to':'TEL-2','text':' Je vous rejoins '}),input(),act);
      await applyCarAction(const CarAction('write',{'to':'TEL-2','text':''}),input(),act);
      await applyCarAction(const CarAction('write',{'to':'TEL-1','text':'à moi'}),input(),act);
      expect(sent,['user:TEL-2 routine Je vous rejoins null']);
    });

    test('« Écrire au PCO »: to the PCO channel, else the PCO terminals',() async {
      await applyCarAction(const CarAction('writePco',{'order':'o1','text':'Route coupée'}),input(),act);
      await applyCarAction(const CarAction('writePco',{'order':'o1','text':'Route coupée'}),
        input(groups:{'t1':team1},devices:{'PCO-Web':{},'TEL-3':{}}),act);
      await applyCarAction(const CarAction('writePco',{'order':'o1','text':''}),input(),act);
      expect(sent,['group:g-pco routine Route coupée null','user:PCO-Web routine Route coupée null']);
    });

    test('« Je suis sur place »: the point and my position, to the PCO',() async {
      await applyCarAction(const CarAction('onSite',{'id':'poi1'}),input(),act);
      await applyCarAction(const CarAction('onSite',{'id':'poi1'}),input(at:null),act);
      await applyCarAction(const CarAction('onSite',{'id':'gone'}),input(),act);
      expect(sent,['group:g-pco routine Je suis sur place : P2 (48.80000, 1.95000) null','group:g-pco routine Je suis sur place : P2 null']);
    });
  });
}

String _hm(DateTime t){final l=t.toLocal();String two(int v)=>v.toString().padLeft(2,'0');return '${two(l.hour)}:${two(l.minute)}';}
