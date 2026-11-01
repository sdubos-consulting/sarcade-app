// Android Auto screen with tabs (lot 17, card « Voiture : vraie interface
// SARCADE avec onglets »): data written to the car, actions of the driver,
// channel with the plugin third_party/sarcade_car.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/features/car/car_screen_channel.dart';
import 'package:sarcade_app/src/features/orders/move_orders.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/comm_group.dart';
import 'package:sarcade_app/src/models/message.dart';
import 'package:sarcade_app/src/models/poi.dart';
import 'package:sarcade_app/src/models/position.dart';
import 'package:sarcade_app/src/modules/adrasec/reference/reference_site.dart';
import 'package:sarcade_app/src/ui/operator_color.dart';

final now=DateTime.utc(2026,11,1,10,0);
const here=LatLng(48.80,1.95);

SarcadeMessage msg(String id,String from,List<String> to,String body,{String priority='routine',int min=0})=>SarcadeMessage(
  id:id,eventId:'e',senderId:from,recipientIds:to,priority:priority,body:body,createdAt:now.subtract(Duration(minutes:60-min)));

MoveOrder order(String id,String status,{String target='TEL-1',double lat=48.83,String updated='2026-11-01T09:50:00Z'})=>MoveOrder({
  'id':id,'target_id':target,'created_by':'PCO','status':status,'note':'Prendre la radio',
  'destination':{'lat':lat,'lon':1.95,'label':'P2'},'updated_at':updated});

SarcadePosition pos(String device,double lat,{String source='device'})=>SarcadePosition(id:'p-$device',eventId:'e',deviceId:device,
  lat:lat,lon:1.95,time:now.subtract(const Duration(minutes:2)),source:source);

ReferenceSite ref(String id,String category,double lat)=>ReferenceSite(id:id,category:category,name:'Site $id',lat:lat,lon:1.95,
  source:'test',sourceLayer:'test',status:'active',txMhz:category=='RELAY'?145.6125:null,altM:category=='HIGH_POINT'?180:null);

final team=CommGroup(id:'g1',eventId:'e',name:'Équipe 2',createdBy:'PCO',updatedBy:'PCO',updatedAt:now,color:0xFF43A047);

CarScreenInput input({List<SarcadeMessage>? messages,List<SarcadeAck> acks=const [],List<MoveOrder> orders=const [],
    List<ReferenceSite> references=const [],bool inDistress=false,LatLng? at=here})=>CarScreenInput(
  me:'TEL-1',eventId:'e',now:now,here:at,inDistress:inDistress,acks:acks,orders:orders,references:references,
  groups:{'g1':team},
  messages:messages??[
    msg('m1','PCO',const [],'Point de situation',min:1),
    msg('m2','F4JPO',['user:TEL-1'],'Rendez-vous au point haut.',priority:'urgent',min:5),
    msg('m3','TEL-1',['user:F4JPO'],'Bien reçu',min:6),
    msg('m4','TEL-2',['group:g1'],'Signal entendu',priority:'immediate',min:7),
  ],
  pois:[SarcadePoi(id:'poi1',eventId:'e',kind:'designated',lat:48.79,lon:1.95,createdAt:now,label:'Point de regroupement',icon:'gathering',createdBy:'PCO')],
  positions:[pos('TEL-1',48.80),pos('TEL-3',48.90),pos('TEL-2',48.81),pos('aprs:F4XYZ',48.80,source:'aprs')],
  devices:{'TEL-2':{'device_id':'TEL-2','icon':'car'}});

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>S.setLanguage('fr'));

  test('distance and direction from the phone, nothing without position',(){
    expect(carAway(here,const LatLng(48.83,1.95)),'3,34 km au nord');
    expect(carAway(here,const LatLng(48.77,1.91)),contains('au sud-ouest'));
    expect(carAway(null,const LatLng(48.83,1.95)),'');
    expect(carAway(here,here),'Ici');
  });

  test('Messages: conversations, latest first, unread, priority, tile, reading aloud',(){
    final s=carSnapshot(input());
    final c=(s['messages'] as List).cast<Map<String,Object?>>();
    expect(c.map((x)=>x['id']),['g:g1','u:F4JPO','all']);
    final channel=c[0], direct=c[1], all=c[2];
    expect(channel['title'],'Équipe 2'); expect(channel['color'],0xFF43A047); expect(channel['icon'],'channel');
    expect(channel['prio'],'immediate'); expect(channel['prioLabel'],'IMMÉDIAT');
    expect(channel['replyTo'],'TEL-2'); expect(channel['canReply'],isTrue);
    expect(direct['title'],'F4JPO'); expect(direct['color'],operatorColor('F4JPO'));
    expect(direct['text'],'Vous : Bien reçu'); expect(direct['prioLabel'],'');
    expect(direct['unread'],1);
    expect(direct['body'],contains('URGENT · F4JPO : Rendez-vous au point haut.'));
    expect(direct['speak'],'Urgent. F4JPO : Rendez-vous au point haut. Vous : Bien reçu.');
    expect(all['title'],'Tous');
    // Read by me: no longer counted.
    final read=carSnapshot(input(acks:[SarcadeAck(id:'a',eventId:'e',messageId:'m2',actorId:'TEL-1',status:'read',time:now)]));
    expect(((read['messages'] as List)[1] as Map)['unread'],0);
  });

  test('Ordres: mine only, in progress first, answers kept 30 min, never cancelled',(){
    final s=carSnapshot(input(orders:[
      order('o1','arrived',updated:'2026-11-01T09:45:00Z'),
      order('o2','sent'),
      order('o3','cancelled'),
      order('o4','sent',target:'TEL-2'),
      order('o5','refused',updated:'2026-11-01T08:00:00Z'),
    ]));
    final o=(s['orders'] as List).cast<Map<String,Object?>>();
    expect(o.map((x)=>x['id']),['o2','o1']);
    expect(o.first['title'],'P2'); expect(o.first['status'],'sent');
    expect(o.first['text'],'PCO · ${S.t('order.status.sent')} · 3,34 km au nord');
    expect(o.first['note'],'Prendre la radio'); expect(o.first['lat'],48.83);
  });

  test('Points: designated points, then the nearest high points and relays',(){
    final s=carSnapshot(input(references:[ref('r1','RELAY',48.82),ref('h1','HIGH_POINT',48.85),ref('far','RELAY',50.0)]));
    final p=(s['points'] as List).cast<Map<String,Object?>>();
    expect(p.map((x)=>x['id']),['poi1','r1','h1']);
    expect(p[0]['title'],'Point de regroupement'); expect(p[0]['icon'],'gathering');
    expect(p[1]['icon'],'relay'); expect(p[1]['text'],contains('Relais · 145,6125 MHz'));
    expect(p[2]['icon'],'high'); expect(p[2]['text'],contains('Point haut · 180 m'));
    // Without position: no « nearest » reference.
    final away=carSnapshot(input(references:[ref('r1','RELAY',48.82)],at:null));
    expect((away['points'] as List).map((x)=>(x as Map)['id']),['poi1']);
  });

  test('Équipe: other terminals, nearest first, icon and colour of the operator',(){
    final t=(carSnapshot(input())['team'] as List).cast<Map<String,Object?>>();
    expect(t.map((x)=>x['id']),['TEL-2','TEL-3']);
    expect(t.first['icon'],'car'); expect(t.first['color'],operatorColor('TEL-2'));
    expect(t.first['text'],contains('au nord'));
    expect(t.first['text'],contains('vu il y a 2'));
  });

  test('every text of the car exists in French and English',(){
    for(final lang in const ['fr','en']){
      S.setLanguage(lang);
      final labels=carLabels();
      for(final e in labels.entries){expect(e.value,isNot('car.${e.key}'),reason:'$lang ${e.key}');}
      expect(labels.length,35);
    }
    S.setLanguage('en');
    expect(carAway(here,const LatLng(48.83,1.95)),'3,34 km north');
  });

  group('actions of the driver',(){
    late List<String> done;
    late CarScreenActions act;
    setUp((){
      done=[];
      act=CarScreenActions(
        order:(o,s) async=>done.add('order ${o.id} $s'),
        ack:(a,m) async=>done.add('ack ${m.id} ${a.status} ${a.actorId}'),
        send:(m) async=>done.add('send ${m.recipientIds.join(',')} ${m.priority} ${m.body} ${m.replyTo}'),
        sos:() async=>done.add('sos'),sosEnd:() async=>done.add('sosEnd'));
    });

    test('parsed from the plugin, damaged entries skipped',(){
      final a=parseCarActions(jsonDecode('[{"type":"order","id":"o2","status":"accepted"},{"id":"x"},3,{"type":"sos"}]'));
      expect(a.map((x)=>x.type),['order','sos']);
      expect(a.first.id,'o2'); expect(a.first.status,'accepted');
      expect(parseCarActions(null),isEmpty);
    });

    test('order answers as on the phone, never out of order',() async {
      final i=input(orders:[order('o2','sent'),order('o6','accepted'),order('o4','sent',target:'TEL-2')]);
      await applyCarAction(const CarAction('order',{'id':'o2','status':'accepted'}),i,act);
      await applyCarAction(const CarAction('order',{'id':'o2','status':'arrived'}),i,act);
      await applyCarAction(const CarAction('order',{'id':'o6','status':'arrived'}),i,act);
      await applyCarAction(const CarAction('order',{'id':'o4','status':'refused'}),i,act);
      expect(done,['order o2 accepted','order o6 arrived']);
    });

    test('a conversation opened is read: one acknowledgement per unread message',() async {
      await applyCarAction(const CarAction('read',{'conversation':'u:F4JPO'}),input(),act);
      await applyCarAction(const CarAction('read',{'conversation':'u:nobody'}),input(),act);
      expect(done,['ack m2 read TEL-1']);
    });

    test('dictated answer: to the sender, in direct, linked to its message',() async {
      await applyCarAction(const CarAction('reply',{'conversation':'g:g1','text':' En route '}),input(),act);
      await applyCarAction(const CarAction('reply',{'conversation':'u:F4JPO','text':'Sur place'}),input(),act);
      await applyCarAction(const CarAction('reply',{'conversation':'all','text':''}),input(),act);
      expect(done,['send user:TEL-2 routine En route m4','send user:F4JPO routine Sur place m2']);
    });

    test('SOS once, its end only during a distress',() async {
      await applyCarAction(const CarAction('sos',{}),input(),act);
      await applyCarAction(const CarAction('sos',{}),input(inDistress:true),act);
      await applyCarAction(const CarAction('sosEnd',{}),input(),act);
      await applyCarAction(const CarAction('sosEnd',{}),input(inDistress:true),act);
      expect(done,['sos','sosEnd']);
    });
  });

  group('channel with the plugin',(){
    final messenger=TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;
    late List<Map<String,Object?>> pending;
    late bool carOn;
    Future<void> settle() async {for(var i=0;i<20;i++){await Future<void>.delayed(Duration.zero);}}
    Future<void> fromPlugin(String method,[Object? args]) async {
      await messenger.handlePlatformMessage(carScreenChannel.name,const StandardMethodCodec().encodeMethodCall(MethodCall(method,args)),(_){});
      await settle();
    }

    setUp((){
      calls=[]; pending=[]; carOn=false;
      messenger.setMockMethodCallHandler(carScreenChannel,(call) async {
        calls.add(call);
        switch(call.method){
          case 'state': return carOn;
          case 'takeActions': final raw=jsonEncode(pending); pending=[]; return raw;
        }
        return null;
      });
    });
    tearDown(()=>messenger.setMockMethodCallHandler(carScreenChannel,null));

    CarScreenBridge bridge(List<String> done,{bool inDistress=false})=>CarScreenBridge(enabled:true,
      read:()=>input(inDistress:inDistress),
      actions:CarScreenActions(order:(o,s) async=>done.add('order'),ack:(a,m) async=>done.add('ack'),send:(m) async=>done.add('send'),
        sos:() async=>done.add('sos'),sosEnd:() async=>done.add('sosEnd')));

    test('data written only while the car shows SARCADE, once when unchanged',() async {
      final b=bridge([]);
      b.start(); await settle();
      expect(calls.map((c)=>c.method),['state','takeActions']);
      expect(b.active,isFalse);
      await fromPlugin('active',true);
      expect(b.active,isTrue);
      final updates=calls.where((c)=>c.method=='update').toList();
      expect(updates,hasLength(1));
      final data=jsonDecode(updates.single.arguments as String) as Map;
      expect(data['labels']['tab.orders'],'Ordres');
      expect((data['messages'] as List),hasLength(3));
      await b.push();
      expect(calls.where((c)=>c.method=='update'),hasLength(1));
      await fromPlugin('active',false);
      expect(b.active,isFalse);
      b.dispose();
    });

    test('actions done in the car taken and applied, then the data written again',() async {
      final done=<String>[];
      final b=bridge(done);
      pending=[{'type':'sos','uid':'1','at':1}];
      carOn=true;
      b.start(); await settle();
      expect(done,['sos']);
      pending=[{'type':'read','conversation':'u:F4JPO'},{'type':'nothing'}];
      await fromPlugin('actions');
      expect(done,['sos','ack']);
      expect(calls.where((c)=>c.method=='takeActions'),hasLength(2));
      b.dispose();
    });

    test('nothing at all where there is no Android Auto',() async {
      final b=CarScreenBridge(enabled:false,read:()=>input(),actions:CarScreenActions(order:(o,s) async {},ack:(a,m) async {},
        send:(m) async {},sos:() async {},sosEnd:() async {}));
      b.start(); await b.push(); await b.drain(); await settle();
      expect(calls,isEmpty);
      b.dispose();
    });
  });
}
