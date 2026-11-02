// Android Auto, lot 20 (card « Android Auto : ordres de déplacement peu
// utilisables… », choices 1 to 6): orders of the person on each of its
// terminals, fields of the order alert, messages of one sender grouped in
// one notification, move orders fetched when the car opens SARCADE.
// The car screens themselves are tested in the plugin (Robolectric,
// androidx.car.app:app-testing): third_party/sarcade_car/android/src/test.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/car/car_android.dart';
import 'package:sarcade_app/src/features/car/car_messaging.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/features/car/car_screen_channel.dart';
import 'package:sarcade_app/src/features/orders/move_orders.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/message.dart';
import 'package:sarcade_app/src/services/notification_keys.dart';

final now=DateTime.utc(2026,11,2,6,46);
const here=LatLng(48.80,1.95);

MoveOrder order(String id,String target,{String status='sent'})=>MoveOrder({
  'id':id,'target_id':target,'created_by':'PCO-iphone-apps','status':status,'note':'',
  'destination':{'lat':48.8191,'lon':1.9210,'label':'Point de la carte'},'updated_at':'2026-11-02T06:45:00Z'});

const devices=<String,Map<String,dynamic>>{
  'TEL-1':{'device_id':'TEL-1','callsign':'F4ABC-7'},
  'SURFACE':{'device_id':'SURFACE','callsign':'f4abc'},
  'TEL-2':{'device_id':'TEL-2','callsign':'F4XYZ'},
  'TEL-3':{'device_id':'TEL-3'},
};

CarScreenInput input(List<MoveOrder> orders,{String me='TEL-1'})=>CarScreenInput(
  me:me,eventId:'e',now:now,here:here,orders:orders,devices:devices);

SarcadeMessage msg(String id,String from,List<String> to,String body,{int min=0,String priority='immediate'})=>SarcadeMessage(
  id:id,eventId:'e',senderId:from,recipientIds:to,priority:priority,body:body,createdAt:now.add(Duration(minutes:min)));

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>S.setLanguage('fr'));

  test('the order of the person on each of its terminals (same callsign)',(){
    expect(carSamePerson('TEL-1','TEL-1',devices),isTrue);
    expect(carSamePerson('SURFACE','TEL-1',devices),isTrue,reason:'F4ABC-7 and f4abc: same person');
    expect(carSamePerson('TEL-2','TEL-1',devices),isFalse);
    expect(carSamePerson('TEL-1','TEL-3',devices),isFalse,reason:'no callsign: this terminal only');
    expect(carSamePerson('TEL-3','TEL-3',devices),isTrue);
    final orders=[order('o1','SURFACE'),order('o2','TEL-2'),order('o3','TEL-1')];
    expect(carOrders(input(orders)).map((o)=>o.id),containsAll(['o1','o3']));
    expect(carOrders(input(orders)).map((o)=>o.id),isNot(contains('o2')));
  });

  test('answered from the car of another terminal of the person',() async {
    final done=<String>[];
    final act=CarScreenActions(order:(o,s) async=>done.add('${o.id} $s'),ack:(a,m) async {},send:(m) async {},sos:() async {},sosEnd:() async {});
    final i=input([order('o1','SURFACE'),order('o2','TEL-2')]);
    await applyCarAction(const CarAction('order',{'id':'o1','status':'accepted'}),i,act);
    await applyCarAction(const CarAction('order',{'id':'o2','status':'accepted'}),i,act);
    expect(done,['o1 accepted']);
  });

  test('alert of the order: name of the point, sender, short distance; Y aller and Voir',(){
    final s=carSnapshot(input([order('o1','TEL-1')]));
    final o=(s['orders'] as List).single as Map;
    expect(o['title'],'Point de la carte');
    expect(o['from'],'PCO-iphone-apps');
    expect(o['away'],'3 km NO');
    final labels=s['labels'] as Map;
    expect(labels['go'],'Y aller'); expect(labels['view'],'Voir'); expect(labels['orderAlert'],'Ordre de déplacement');
    S.setLanguage('en');
    expect(carLabels()['go'],'Go there'); expect(carLabels()['view'],'View'); expect(carLabels()['orderAlert'],'Move order');
  });

  test('two orders of the PCO: one notification, the latest shown last',(){
    final first=msg('m1','PCO',['TEL-1'],'📍 Ordre de déplacement : rejoindre « A »');
    final second=msg('m2','PCO',['TEL-1'],'📍 Ordre de déplacement : rejoindre « B »',min:1);
    final others=[
      msg('m0','PCO',['TEL-1'],'trop ancien',min:-180),
      msg('mx','PCO',const ['group:g1'],'au canal'),
      msg('my','TEL-2',['TEL-1'],'autre expéditeur'),
      msg('mz','PCO',['TEL-1'],'plus tard',min:5),
    ];
    final earlier=carThread(second,[first,second,...others],me:'TEL-1');
    expect(earlier.map((m)=>m.id),['m1']);
    final c=carConversation(second,me:'TEL-1',earlier:earlier);
    expect(c.replaces,[messageNotificationKey(first)]);
    final style=carStyle(c);
    expect(style.messages!.map((m)=>m.text),[first.body,second.body]);
    expect(style.messages!.last.person!.name,'PCO');
    // At most 4 earlier messages; never for my own messages.
    final many=[for(var k=0;k<8;k++)msg('k$k','PCO',['TEL-1'],'n° $k',min:-k-1)];
    expect(carThread(second,many,me:'TEL-1'),hasLength(carThreadMax));
    expect(carThread(msg('me','TEL-1',['PCO'],'ok'),[first],me:'TEL-1'),isEmpty);
  });

  test('a distress keeps its own notification',(){
    final sos=msg('s1','PCO',const [],'🆘 Détresse');
    expect(carThread(sos,[msg('a','PCO',const [],'avant',min:-1)],me:'TEL-1'),isEmpty);
  });

  test('the car opens SARCADE: move orders fetched at once',() async {
    final messenger=TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(carScreenChannel,(call) async {
      if(call.method=='state')return true;
      if(call.method=='takeActions')return '[]';
      return null;
    });
    var fetched=0;
    final b=CarScreenBridge(enabled:true,read:()=>input(const []),onActive:()=>fetched++,
      actions:CarScreenActions(order:(o,s) async {},ack:(a,m) async {},send:(m) async {},sos:() async {},sosEnd:() async {}));
    b.start();
    for(var i=0;i<20;i++){await Future<void>.delayed(Duration.zero);}
    expect(fetched,1);
    b.dispose();
    messenger.setMockMethodCallHandler(carScreenChannel,null);
  });
}
