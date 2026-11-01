// ADS-B step 1 (module ADRASEC, OpenSky through the server), 1 Nov 2026;
// lot 17: bands, folded lists, floating sheet, aircraft followed,
// estimated position, icons by type.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:sarcade_app/src/features/settings/diagnostics_panel.dart' show adsbDiagLine;
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/modules/adrasec/adsb/adsb_controller.dart';
import 'package:sarcade_app/src/modules/adrasec/adsb/adsb_icons.dart';
import 'package:sarcade_app/src/modules/adrasec/adsb/adsb_layer.dart';
import 'package:sarcade_app/src/modules/adrasec/adsb/adsb_models.dart';
import 'package:sarcade_app/src/modules/adrasec/adsb/adsb_page.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';

Map<String,dynamic> plane({String icao='3c6444',String? squawk='1000',String? emergency,bool rotor=false})=>{
  'icao24':icao,'callsign':'SAMU75','country':'France','lat':48.8,'lon':2.1,'alt_m':950,'alt_ft':3117,'on_ground':false,
  'speed_kt':100,'track_deg':272,'vertical_rate_mps':-1.2,'squawk':squawk,'emergency':emergency,'rotorcraft':rotor,
  'last_contact':1793491200,'trail':[[48.8,2.0],[48.8,2.1]]};

void main(){
  setUp(()=>S.setLanguage('fr'));

  test('aircraft from the server, label and sheet',(){
    final a=Aircraft.fromJson(plane(rotor:true))!;
    expect(a.name,'SAMU75'); expect(a.rotorcraft,isTrue); expect(a.trail.length,2);
    expect(aircraftLabel(a),'SAMU75 · 3 117 ft · 100 kt',reason:'feet only on the map');
    final lines={for(final (k,v) in aircraftLines(a,now:DateTime.utc(2026,11,1,0,0,12)))k:v};
    expect(lines['adsb.field.icao'],'3C6444');
    expect(lines['adsb.field.speed'],'100 kt · 185 km/h');
    expect(lines['adsb.field.seen'],'il y a 12 s');
    expect(Aircraft.fromJson({'icao24':'x'}),isNull,reason:'no position');
    expect(aircraftList({'aircraft':[plane(),{'bad':1}]}).length,1);
    expect(Aircraft.fromJson({...plane(),'callsign':'  '})!.name,'3C6444');
  });

  test('emergency squawks in words',(){
    final a=Aircraft.fromJson(plane(squawk:'7700',emergency:'emergency'))!;
    expect(a.urgent,isTrue);
    expect({for(final (k,v) in aircraftLines(a))k:v}['adsb.field.squawk'],'7700 · urgence (7700)');
    expect(emergencyText('radio_failure'),'panne radio (7600)');
    expect(aircraftColor(a),adsbUrgentColor);
  });

  test('watch while shown, told when hidden, emergency announced once',() async {
    final calls=<Map<String,dynamic>>[];
    final api=SarcadeApi(baseUrl:'http://s',client:MockClient((r) async {
      calls.add(jsonDecode(r.body) as Map<String,dynamic>);
      return http.Response(jsonEncode({'enabled':true,'interval_s':30,'ttl_s':120,'time':'2026-11-01T00:00:00Z',
        'aircraft':[plane(squawk:'7600',emergency:'radio_failure')]}),200);
    }));
    final c=AdsbController(api:api,eventId:'e',deviceId:'TEL-1',box:()=>(south:48.7,west:1.9,north:48.9,east:2.2));
    final alerts=<String>[];
    c.onEmergency=(a)=>alerts.add(a.icao24);
    await c.setOn(true);
    expect(calls.single['on'],isTrue); expect(calls.single['lamin'],48.7);
    expect(c.aircraft.length,1); expect(c.serverEnabled,isTrue);
    c.onRealtime('adsb.updated',{'aircraft':[plane(squawk:'7600',emergency:'radio_failure')]});
    expect(alerts,['3c6444'],reason:'once per aircraft and code');
    await c.setOn(false);
    expect(calls.last['on'],isFalse); expect(c.aircraft,isEmpty);
    c.onRealtime('adsb.updated',{'aircraft':[plane()]});
    expect(c.aircraft,isEmpty,reason:'layer hidden: broadcasts ignored');
    c.dispose();
  });

  testWidgets('icons on the map, touch opens the sheet, no trace by default',(t) async {
    Aircraft? tapped;
    final a=Aircraft.fromJson(plane())!;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:FlutterMap(options:const MapOptions(initialCenter:LatLng(48.8,2.1),initialZoom:10),children:[
      aircraftRoutes(const {}),AircraftMarkers(aircraft:[a],onTap:(x)=>tapped=x,now:()=>DateTime.fromMillisecondsSinceEpoch(1793491200*1000))]))));
    await t.pump();
    expect(find.text('SAMU75 · 3 117 ft · 100 kt'),findsNothing,reason:'uncluttered: no label');
    expect(aircraftRoutes(const {}).polylines,isEmpty,reason:'no trace for an aircraft not followed');
    expect(aircraftRoutes({'x':[const LatLng(1,1),const LatLng(1,2)]}).polylines.length,1);
    await t.tap(find.byKey(const ValueKey('adsb-3c6444')));
    expect(tapped?.icao24,'3c6444');
    await t.pumpWidget(const SizedBox());
  });

  Aircraft at(int? ft,{bool ground=false,String? em,String icao='3c6444'})=>
    Aircraft.fromJson({...plane(icao:icao),'alt_ft':ft,'on_ground':ground,'emergency':em})!;

  test('bands: 3 000 / 10 000 ft, Bas and Moyen shown, emergency always shown',(){
    const f=AdsbFilters();
    expect(f.shows(at(2000)),isTrue);
    expect(f.shows(at(8000)),isTrue);
    expect(f.shows(at(37000)),isFalse,reason:'Haut hidden by default (the former 0 → 10 000 ft)');
    expect(f.shows(at(300,ground:true)),isFalse);
    expect(f.shows(at(null)),isTrue,reason:'unknown altitude follows Bas');
    expect(f.shows(at(37000,em:'emergency')),isTrue);
    expect([3000,3001,10000,10001].map((v)=>f.bandOf(at(v))),[AdsbBand.low,AdsbBand.mid,AdsbBand.mid,AdsbBand.high]);
    expect(f.bandOf(at(null)),AdsbBand.ground);
    expect(f.rangeOf(AdsbBand.low),'0 – 3 000 ft');
    expect(f.rangeOf(AdsbBand.high),'au-delà de 10 000 ft');
    expect(f.all.shows(at(37000)),isTrue); expect(f.all.ground,isTrue);
    // The porteur's example: Bas and Haut hidden, Moyen alone.
    final mid=f.withBand(AdsbBand.low,false);
    expect(mid.shows(at(2000)),isFalse); expect(mid.shows(at(8000)),isTrue); expect(mid.shows(at(null)),isFalse);
    expect(mid.defaults,const AdsbFilters());
    expect(f.tvJson(),{'aircraft_low_ft':3000,'aircraft_high_ft':10000,'aircraft_bands':{'low':true,'mid':true,'high':false},
      'aircraft_ground':false,'aircraft_labels':false});
  });

  test('thresholds: colour of an aircraft follows the bands',(){
    const d=AdsbFilters();
    final f=d.withThresholds(1500,5000);
    expect(aircraftColorValue(at(2000),d),adsbLowValue);
    expect(aircraftColorValue(at(2000),f),adsbMidValue);
    expect(aircraftColorValue(at(6000),f),adsbHighValue);
    expect(aircraftColorValue(at(null),f),adsbGroundValue);
    expect(aircraftColorValue(at(6000,em:'emergency'),f),adsbUrgentValue,reason:'emergency always red');
    expect(d.withThresholds(12000,4010),d.copyWith(lowFt:4000,highFt:12000),reason:'500 ft steps, low ≤ high');
    expect(d.withThresholds(0,99000).highFt,AdsbFilters.topFt);
    final back=AdsbFilters.fromJson(f.withBand(AdsbBand.high,true).toJson());
    expect(back,f.withBand(AdsbBand.high,true));
    expect(AdsbFilters.fromJson(null),const AdsbFilters());
  });

  test('filters stored by #181 are converted to bands',(){
    final old=AdsbFilters.fromJson({'min':0,'max':10000,'ground':true,'labels':false});
    expect([old.showLow,old.showMid,old.showHigh,old.ground],[true,true,false,true]);
    final all=AdsbFilters.fromJson({'min':0,'max':null});
    expect([all.showLow,all.showMid,all.showHigh],[true,true,true]);
    final high=AdsbFilters.fromJson({'min':5000,'max':null});
    expect([high.showLow,high.showMid,high.showHigh],[false,true,true]);
  });

  test('sections: emergencies apart, one section per band shown, empty ones left out, counts',(){
    final all=[at(1000,icao:'a1'),at(500,icao:'a2'),at(8000,icao:'b1'),at(37000,icao:'c1'),at(37000,icao:'u1',em:'emergency'),
      at(200,ground:true,icao:'g1'),at(null,icao:'n1')];
    final s=adsbSections(all,const AdsbFilters());
    expect(s.urgent.map((a)=>a.icao24),['u1']);
    expect(s.bands.keys,[AdsbBand.low,AdsbBand.mid,AdsbBand.ground],reason:'Haut hidden: no section');
    expect(s.bands[AdsbBand.low]!.map((a)=>a.icao24),['a2','a1'],reason:'by increasing altitude');
    expect(s.bands[AdsbBand.ground]!.map((a)=>a.icao24),['n1']);
    expect(s.hidden,2,reason:'Haut and the aircraft on the ground');
    final t=adsbSections(all,const AdsbFilters().withThresholds(500,1000),followed:{'c1'});
    expect(t.bands[AdsbBand.low]!.map((a)=>a.icao24),['a2']);
    expect(t.bands[AdsbBand.mid]!.map((a)=>a.icao24),['a1']);
    expect(t.followed.map((a)=>a.icao24),['c1']);
    expect(adsbSections(all,const AdsbFilters().withBand(AdsbBand.low,false).withBand(AdsbBand.mid,false)).urgent.length,1,
      reason:'emergency always visible');
  });

  test('estimated position: 60 s at most, then grey',(){
    final a=Aircraft.fromJson({...plane(),'speed_kt':250,'track_deg':90,'position_time':1000})!;
    DateTime t(int s)=>DateTime.fromMillisecondsSinceEpoch(s*1000);
    expect(aircraftEstimated(a,t(1000)),a.position);
    final p30=aircraftEstimated(a,t(1030));
    expect(p30.latitude,closeTo(48.8,1e-6));
    expect((p30.longitude-2.1)*111320*math.cos(48.8*math.pi/180),closeTo(250*0.514444*30,1));
    expect(aircraftEstimated(a,t(1200)),aircraftEstimated(a,t(1060)),reason:'60 s at most');
    expect(aircraftStale(a,t(1060)),isFalse); expect(aircraftStale(a,t(1061)),isTrue);
    expect(aircraftStale(Aircraft.fromJson({...plane(squawk:'7700',emergency:'emergency'),'position_time':1000})!,t(2000)),isFalse);
    expect(aircraftEstimated(Aircraft.fromJson({...plane(),'on_ground':true,'position_time':1000})!,t(1030)).longitude,2.1);
    expect(Aircraft.fromJson(plane())!.positionTime,1793491200,reason:'no position time: last contact');
  });

  test('icon by OpenSky category, unknown → generic, type in words',(){
    Aircraft cat(int? c,{bool rotor=false})=>Aircraft.fromJson({...plane(rotor:rotor),'category':c})!;
    final expected={2:AircraftKind.light,3:AircraftKind.light,4:AircraftKind.airliner,5:AircraftKind.airliner,6:AircraftKind.airliner,
      8:AircraftKind.heli,9:AircraftKind.glider,10:AircraftKind.balloon,11:AircraftKind.parachute,12:AircraftKind.ulm,14:AircraftKind.drone,
      0:AircraftKind.plane,1:AircraftKind.plane,7:AircraftKind.plane};
    for(final e in expected.entries){expect(aircraftKind(cat(e.key)),e.value,reason:'category ${e.key}');}
    expect(aircraftKind(cat(null)),AircraftKind.plane);
    expect(aircraftKind(cat(null,rotor:true)),AircraftKind.heli,reason:'former server: rotorcraft flag');
    for(final k in AircraftKind.values){expect(aircraftShapes[k]!.polygons,isNotEmpty);}
    expect(aircraftTurned(AircraftKind.heli),isFalse); expect(aircraftTurned(AircraftKind.plane),isTrue);
    expect(aircraftIconSize(AircraftKind.airliner),greaterThan(aircraftIconSize(AircraftKind.light)));
    expect(aircraftTypeText(cat(8)),'Hélicoptère');
    expect(aircraftTypeText(cat(0)),'Catégorie non transmise');
    expect(aircraftTypeText(cat(null)),'Catégorie non transmise');
    expect(aircraftTypeText(cat(4)),'Avion de ligne');
    expect(aircraftTypeText(cat(7)),'Avion (catégorie 7)');
  });

  SarcadeApi trackApi()=>SarcadeApi(baseUrl:'http://s',client:MockClient((r) async {
    if(r.url.path.endsWith('/track')){
      final id=r.url.pathSegments[r.url.pathSegments.length-2];
      return http.Response(jsonEncode({'icao24':id,'track':[[48.7,2.0],[48.75,2.05],[48.8,2.1]]}),200);
    }
    return http.Response(jsonEncode({'enabled':true,'time':'t','now':1793491230,'aircraft':[plane(),plane(icao:'abc123')]}),200);
  }));

  test('several aircraft followed: two routes, kept when the sheet closes',() async {
    final c=AdsbController(api:trackApi(),eventId:'e',deviceId:'TEL-1',box:()=>(south:48.7,west:1.9,north:48.9,east:2.2));
    final centred=<LatLng>[]; var pushed=0;
    c.onCentre=centred.add; c.onFollowedChanged=()=>pushed++;
    await c.setOn(true);
    expect(c.routes,isEmpty,reason:'no trace by default');
    expect(c.serverNow.difference(DateTime.fromMillisecondsSinceEpoch(1793491230*1000)).inSeconds.abs(),lessThan(5),reason:'server clock kept');
    final a=c.aircraft[0], b=c.aircraft[1];
    await c.select(a);
    await c.follow(a);
    await c.select(b);
    await c.follow(b);
    expect(c.followed,{'3c6444','abc123'}); expect(c.routes.length,2); expect(c.routes['abc123']!.length,3);
    expect(c.centredId,'abc123',reason:'centred on the last one followed');
    expect(centred,isNotEmpty); expect(pushed,2,reason:'« Suivre ma vue » told');
    await c.select(null);
    expect(c.selected,isNull); expect(c.routes.length,2,reason:'routes stay when the sheet closes');
    c.stopCentring();
    expect(c.centredId,isNull); expect(c.routes.length,2,reason:'moving the map keeps the routes');
    expect(c.tvJson()['aircraft_followed'],['3c6444','abc123']);
    c.unfollow('3c6444');
    expect(c.routes.keys,['abc123']);
    c.unfollowAll();
    expect(c.followed,isEmpty); expect(c.routes,isEmpty);
    c.dispose();
  });

  testWidgets('floating sheet: Suivre then Ne plus suivre, the close cross keeps the route',(t) async {
    final c=AdsbController(api:trackApi(),eventId:'e',deviceId:'TEL-1',box:()=>(south:48.7,west:1.9,north:48.9,east:2.2));
    await t.runAsync(()=>c.setOn(true));
    await c.select(c.aircraft.first);
    t.view.physicalSize=const Size(1200,1600); t.view.devicePixelRatio=1;
    addTearDown(t.view.reset);
    var closed=0;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Stack(children:[const Positioned.fill(child:ColoredBox(color:Colors.green)),
      Positioned(top:8,left:8,child:AircraftCard(adsb:c,onClose:(){closed++;c.select(null);}))]))));
    expect(find.byKey(const ValueKey('adsb-card')),findsOneWidget);
    expect(t.getSize(find.byKey(const ValueKey('adsb-card'))).width,300,reason:'small window, the map stays visible');
    expect(find.text('Catégorie non transmise'),findsOneWidget,reason:'type in words');
    await t.ensureVisible(find.byKey(const ValueKey('adsb-follow')));
    await t.tap(find.byKey(const ValueKey('adsb-follow')));
    expect(c.isFollowed('3c6444'),isTrue);
    expect(c.centredId,'3c6444');
    await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:50)));
    await t.pump();
    expect(c.routes['3c6444']?.length,3,reason:'route read from the server');
    expect(find.text('Ne plus suivre'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('adsb-close')));
    await t.pump();
    expect(closed,1); expect(find.byKey(const ValueKey('adsb-card')),findsNothing);
    expect(c.isFollowed('3c6444'),isTrue,reason:'closing the sheet does not stop following');
    c.dispose();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Outils › ADS-B: sections folded, emergency visible, bands switched',(t) async {
    final c=AdsbController(api:SarcadeApi(baseUrl:'http://s',client:MockClient((r) async=>http.Response(jsonEncode({'enabled':true,'time':'t',
      'aircraft':[{...plane(icao:'aaaaa1'),'callsign':'LOW1','alt_ft':1000},{...plane(icao:'aaaaa2'),'callsign':'MID1','alt_ft':8000},
        {...plane(icao:'aaaaa3'),'callsign':'MAY7700','alt_ft':30000,'squawk':'7700','emergency':'emergency'},
        {...plane(icao:'aaaaa4'),'callsign':'HIGH1','alt_ft':36000}]}),200))),
      eventId:'e',deviceId:'TEL-1',box:()=>(south:48.7,west:1.9,north:48.9,east:2.2));
    await t.runAsync(()=>c.setOn(true));
    t.view.physicalSize=const Size(900,3000); t.view.devicePixelRatio=1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home:AdsbPage(adsb:c,onShow:(_){})));
    await t.pump();
    expect(find.byKey(const ValueKey('adsb-section-low')),findsOneWidget);
    expect(find.byKey(const ValueKey('adsb-section-mid')),findsOneWidget);
    expect(find.byKey(const ValueKey('adsb-section-high')),findsNothing,reason:'Haut hidden: no section');
    expect(find.text('Bas · 0 – 3 000 ft · 1'),findsOneWidget);
    expect(find.byKey(const ValueKey('adsb-row-aaaaa1')),findsNothing,reason:'folded at start');
    expect(find.byKey(const ValueKey('adsb-row-aaaaa3')),findsOneWidget,reason:'emergency never folded');
    expect(find.byKey(const ValueKey('adsb-hidden')),findsOneWidget);
    await t.tap(find.text('Bas · 0 – 3 000 ft · 1'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('adsb-row-aaaaa1')),findsOneWidget);
    // Haut switched on: its section appears.
    await t.tap(find.byKey(const ValueKey('adsb-band-high')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('adsb-section-high')),findsOneWidget);
    expect(find.byKey(const ValueKey('adsb-legend-heli')),findsOneWidget,reason:'legend of the icons');
    c.dispose();
    await t.pumpWidget(const SizedBox());
  });

  test('labels only for the selected aircraft, an emergency, or when asked',(){
    final a=Aircraft.fromJson(plane())!, u=Aircraft.fromJson(plane(icao:'u',squawk:'7700',emergency:'emergency'))!;
    expect(aircraftLabelled(a,labels:false),isFalse);
    expect(aircraftLabelled(a,labels:false,selectedId:'3c6444'),isTrue);
    expect(aircraftLabelled(u,labels:false),isTrue);
    expect(aircraftLabelled(a,labels:true),isTrue);
    expect(aircraftColorValue(Aircraft.fromJson({...plane(),'alt_ft':1500})!),adsbLowValue,reason:'low = more visible');
  });

  test('OpenSky link in Liaisons',(){
    final now=DateTime.utc(2026,11,1,8,30,40);
    expect(adsbDiagLine('L',null,now),isNull,reason:'event without ADRASEC');
    expect(adsbDiagLine('L',{'enabled':false},now)!.value,startsWith('non configuré'));
    expect(adsbDiagLine('L',{'enabled':true,'paused':true},now)!.state,'orange');
    final ok=adsbDiagLine('L',{'enabled':true,'connected':true,'last_ok_at':'2026-11-01T08:30:10Z','requests_today':100,'credits_per_day':4000},now)!;
    expect(ok.state,'green');
    expect(ok.value,'connecté, dernière réponse il y a 30 s · 100 requêtes aujourd’hui, ≈ 3900 crédits restants');
    expect(adsbDiagLine('L',{'enabled':true,'connected':false,'detail':''},now)!.value,startsWith('en veille'));
    expect(adsbDiagLine('L',{'enabled':true,'connected':false,'detail':'ConnectError'},now)!.state,'red');
  });
}
