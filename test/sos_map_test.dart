import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/sos_alert.dart';
import 'package:sarcade_app/src/features/map/sos_map.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/message.dart';
import 'package:sarcade_app/src/models/position.dart';

// SOS on the map (lot 17, choices validated on 1 Nov 2026, 12 h 04).
final now=DateTime.utc(2026,11,1,14);

SarcadeMessage _m(String id,String who,String body,int minutesAgo,{String priority='immediate',List<String> to=const []})=>
  SarcadeMessage(id:id,eventId:'e',senderId:who,recipientIds:to,priority:priority,body:body,createdAt:now.subtract(Duration(minutes:minutesAgo)));

SarcadePosition _p(String who,double lat,double lon,int minutesAgo)=>
  SarcadePosition(id:'p-$who',eventId:'e',deviceId:who,lat:lat,lon:lon,time:now.subtract(Duration(minutes:minutesAgo)));

String sos(String who,[String pos='inconnue'])=>'🆘 DÉTRESSE — $who — position $pos';

void main(){
  setUp(()=>S.setLanguage('fr'));

  test('distress with a recent position: halo at the last position, its age',(){
    final [t]=sosTargetsFor([_m('1','TEL-01',sos('TEL-01'),1)],'ME',{'TEL-01':_p('TEL-01',48.8,2.1,2)});
    expect(t.known,isTrue);
    expect(t.point,const LatLng(48.8,2.1));
    expect(t.stale(now),isFalse);
    expect(sosAge(t,now),'il y a 2 min');
  });

  test('distress without any position: « position inconnue »',(){
    final [t]=sosTargetsFor([_m('1','TEL-01',sos('TEL-01'),1)],'ME',{'TEL-02':_p('TEL-02',48.8,2.1,1)});
    expect(t.known,isFalse);
    expect(sosAge(t,now),'position inconnue');
    expect(t.label,'TEL-01');
  });

  test('position older than 10 min: stale, « position ancienne »',(){
    final [t]=sosTargetsFor([_m('1','TEL-01',sos('TEL-01'),1)],'ME',{'TEL-01':_p('TEL-01',48.8,2.1,25)});
    expect(t.stale(now),isTrue);
    expect(sosAge(t,now),'position ancienne · il y a 25 min');
    S.setLanguage('en');
    expect(sosAge(t,now),'old position · 25 min ago');
  });

  test('position written in the SOS message when it is more recent',(){
    final msg=_m('1','TEL-01',sos('TEL-01','48.81234, 2.05678'),3);
    expect(sosTargetsFor([msg],'ME',{}).single.point,const LatLng(48.81234,2.05678));
    expect(sosTargetsFor([msg],'ME',{'TEL-01':_p('TEL-01',48.9,2.2,1)}).single.point,const LatLng(48.9,2.2));
    expect(sosTargetsFor([msg],'ME',{'TEL-01':_p('TEL-01',48.9,2.2,30)}).single.point,const LatLng(48.81234,2.05678));
    expect(sosBodyPosition(sos('TEL-01')),isNull);
    expect(sosBodyPosition('position 123.0, 2.0'),isNull);
  });

  test('end of distress removes the halo; own distress and private SOS not shown',(){
    final msgs=[_m('1','TEL-01',sos('TEL-01'),3),_m('2','TEL-01','Fin de détresse — TEL-01',1,priority:'urgent')];
    expect(sosTargetsFor(msgs,'ME',{'TEL-01':_p('TEL-01',48.8,2.1,1)}),isEmpty);
    expect(sosTargetsFor([_m('1','ME',sos('ME'),1)],'ME',{}),isEmpty);
    expect(sosTargetsFor([_m('1','TEL-03',sos('TEL-03'),1,to:['user:PCO'])],'ME',{}),isEmpty);
  });

  test('two distresses: one target each, oldest first',(){
    final targets=sosTargetsFor([_m('2','TEL-02',sos('TEL-02'),2),_m('1','TEL-01',sos('TEL-01'),5)],'ME',
      {'TEL-01':_p('TEL-01',48.8,2.1,1),'TEL-02':_p('TEL-02',48.7,2.0,30)});
    expect(targets.map((t)=>t.deviceId),['TEL-01','TEL-02']);
    expect(targets.map((t)=>t.stale(now)),[false,true]);
    expect(sosTargetOf(targets,'TEL-02')?.deviceId,'TEL-02');
    expect(sosTargetOf(targets,'TEL-09'),isNull);
    expect(S.t('sos.count',{'n':targets.length}),'2 SOS');
  });

  Widget banner(List<SosTarget> targets,ValueChanged<SosTarget> onCenter)=>
    MaterialApp(home:Scaffold(body:SosAlertBanner(targets:targets,now:now,muted:false,onMute:(){},onCenter:onCenter)));

  testWidgets('touch on the banner centres on the operator',(t) async {
    final targets=sosTargetsFor([_m('1','TEL-01',sos('TEL-01'),1)],'ME',{'TEL-01':_p('TEL-01',48.8,2.1,2)});
    SosTarget? centred;
    await t.pumpWidget(banner(targets,(x)=>centred=x));
    expect(find.text('SOS : TEL-01 en détresse · il y a 2 min'),findsOneWidget);
    await t.tap(find.byKey(const Key('sos-banner')));
    expect(centred?.deviceId,'TEL-01');
  });

  testWidgets('several distresses: « 2 SOS », one pill each',(t) async {
    final targets=sosTargetsFor([_m('1','TEL-01',sos('TEL-01'),5),_m('2','TEL-02',sos('TEL-02'),2)],'ME',{'TEL-01':_p('TEL-01',48.8,2.1,1)});
    SosTarget? centred;
    await t.pumpWidget(banner(targets,(x)=>centred=x));
    expect(find.text('2 SOS'),findsOneWidget);
    expect(find.text('TEL-02 · position inconnue'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('sos-target-TEL-01')));
    expect(centred?.deviceId,'TEL-01');
  });

  testWidgets('halo: label « SOS · nom » and its age, dashed when old',(t) async {
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:Center(child:SizedBox(width:240,height:180,
      child:SosHalo(label:'SOS · TEL-01',age:'position ancienne · il y a 25 min',stale:true))))));
    await t.pump(const Duration(milliseconds:700));
    expect(find.text('SOS · TEL-01'),findsOneWidget);
    expect(find.text('position ancienne · il y a 25 min'),findsOneWidget);
    final painter=t.widget<CustomPaint>(find.byWidgetPredicate((w)=>w is CustomPaint&&w.painter is SosHaloPainter)).painter as SosHaloPainter;
    expect(painter.dashed,isTrue);
    expect(painter.progress,greaterThan(0));
    expect(const SosHaloPainter(progress:0.2,dashed:false).shouldRepaint(const SosHaloPainter(progress:0.4,dashed:false)),isTrue);
  });

  testWidgets('« Y aller » button',(t) async {
    var taps=0;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:SosGoButton(onPressed:()=>taps++))));
    expect(find.text('Y aller'),findsOneWidget);
    await t.tap(find.byKey(const Key('sos-go')));
    expect(taps,1);
  });
}
