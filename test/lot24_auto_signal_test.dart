// Android Auto, lot 24, card « Android Auto : « Signal entendu ici »
// (SATER) »: button during a SATER event only (setting `sater`); one touch
// sends a listening point (map_feature « listening »: position, heading,
// time) through /sync; « Annuler » within 10 s deletes it.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/car/car_field.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/position.dart';

final heardAt=DateTime.utc(2026,11,3,9,0);
const here=LatLng(48.75,2.05);

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>S.setLanguage('fr'));

  late List<Map<String,dynamic>> queued;
  late DateTime clock;
  CarField field()=>CarField(baseUrl:'https://s',eventId:'e',me:'TEL-1',clock:()=>clock,client:()=>throw StateError('no HTTP'),
    queue:({required String objectId,required String objectType,required Map<String,dynamic> payload,String action='create'}) async =>
      queued.add({'object_id':objectId,'object_type':objectType,'action':action,'payload':payload}));
  setUp((){queued=[];clock=heardAt;});

  CarScreenInput input(CarField f,{LatLng? at=here,Map<String,dynamic> settings=const {'sater':true}})=>CarScreenInput(
    me:'TEL-1',eventId:'e',now:heardAt,here:at,field:f,settings:settings,
    positions:[SarcadePosition(id:'p',eventId:'e',deviceId:'TEL-1',lat:here.latitude,lon:here.longitude,time:heardAt,headingDeg:135,speedMps:12.5,accuracyM:8)]);
  final act=CarScreenActions(order:(o,s) async {},ack:(a,m) async {},send:(m) async {},sos:() async {},sosEnd:() async {});

  test('shown during a SATER event only, with or without position',(){
    final f=field();
    expect(carSnapshot(input(f))['sater'],{'ready':true});
    expect(carSnapshot(input(f,at:null))['sater'],{'ready':false});
    expect(carSnapshot(input(f,settings:const {}))['sater'],isNull);
    expect(carSnapshot(input(f,settings:const {'sater':false}))['sater'],isNull);
    expect(carLabels()['heard'],'Signal entendu ici');
  });

  test('one touch: listening point with position, heading and time, nothing typed',() async {
    final f=field();
    await applyCarAction(CarAction('heard',{'id':'l1','at':heardAt.millisecondsSinceEpoch}),input(f),act);
    expect(queued.single,{'object_id':'l1','object_type':'map_feature','action':'create','payload':{
      'id':'l1','event_id':'e','kind':'listening','points':[[48.75,2.05]],
      'listening':{'heard_at':'2026-11-03T09:00:00.000Z','heading_deg':135.0,'speed_mps':12.5,'accuracy_m':8.0},
      'created_by':'TEL-1','updated_by':'TEL-1','updated_at':'2026-11-03T09:00:00.000Z'}});
    // The same touch read twice: one point.
    await applyCarAction(CarAction('heard',{'id':'l1','at':heardAt.millisecondsSinceEpoch}),input(f),act);
    expect(queued.length,1);
  });

  test('no position: nothing sent',() async {
    final f=field();
    await applyCarAction(const CarAction('heard',{'id':'l2'}),input(f,at:null),act);
    expect(queued,isEmpty);
  });

  test('« Annuler » within 10 s deletes it; too late: kept',() async {
    final f=field();
    await applyCarAction(CarAction('heard',{'id':'l1','at':heardAt.millisecondsSinceEpoch}),input(f),act);
    await applyCarAction(CarAction('heard',{'id':'l2','at':heardAt.millisecondsSinceEpoch}),input(f),act);
    clock=heardAt.add(const Duration(seconds:9));
    await applyCarAction(const CarAction('heardCancel',{'id':'l1'}),input(f),act);
    expect(queued.last,{'object_id':'l1','object_type':'map_feature','action':'delete',
      'payload':{'id':'l1','event_id':'e','updated_by':'TEL-1','updated_at':'2026-11-03T09:00:09.000Z'}});
    clock=heardAt.add(const Duration(seconds:16));
    expect(await f.cancelListening('l2'),isFalse);
    expect(await f.cancelListening('unknown'),isFalse);
    expect(queued.length,3);
  });
}
