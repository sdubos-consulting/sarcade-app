// ADS-B step 1 (module ADRASEC, OpenSky through the server), 1 Nov 2026.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:sarcade_app/src/features/settings/diagnostics_panel.dart' show adsbDiagLine;
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/modules/adrasec/adsb/adsb_controller.dart';
import 'package:sarcade_app/src/modules/adrasec/adsb/adsb_layer.dart';
import 'package:sarcade_app/src/modules/adrasec/adsb/adsb_models.dart';
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

  testWidgets('icons on the map, touch opens the sheet',(t) async {
    Aircraft? tapped;
    final a=Aircraft.fromJson(plane())!;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:FlutterMap(options:const MapOptions(initialCenter:LatLng(48.8,2.1),initialZoom:10),children:[
      aircraftTrails([a]),aircraftMarkers([a],onTap:(x)=>tapped=x)]))));
    await t.pump();
    expect(find.text('SAMU75 · 3 117 ft · 100 kt'),findsNothing,reason:'uncluttered: no label');
    await t.tap(find.byKey(const ValueKey('adsb-3c6444')));
    expect(tapped?.icao24,'3c6444');
  });

  test('filters: 0 → 10 000 ft by default, ground hidden, emergency always shown',(){
    const f=AdsbFilters();
    Aircraft at(int ft,{bool ground=false,String? em})=>Aircraft.fromJson({...plane(),'alt_ft':ft,'on_ground':ground,'emergency':em})!;
    expect(f.shows(at(2000)),isTrue);
    expect(f.shows(at(37000)),isFalse);
    expect(f.shows(at(300,ground:true)),isFalse);
    expect(f.shows(at(37000,em:'emergency')),isTrue);
    expect(f.rangeText,'0 ft – 10\u202f000 ft');
    expect(AdsbFilters.all.shows(at(37000)),isTrue);
    expect(AdsbFilters.all.rangeText,'0 ft – ∞');
    final back=AdsbFilters.fromJson(const AdsbFilters(minFt:2000,maxFt:null,ground:true).toJson());
    expect(back.maxFt,isNull); expect(back.minFt,2000); expect(back.ground,isTrue);
    expect(AdsbFilters.fromJson(null),const AdsbFilters());
    expect(f.tvJson(),{'aircraft_min_ft':0,'aircraft_max_ft':10000,'aircraft_ground':false,'aircraft_labels':false});
  });

  test('labels only for the selected aircraft, an emergency, or when asked',(){
    final a=Aircraft.fromJson(plane())!, u=Aircraft.fromJson(plane(icao:'u',squawk:'7700',emergency:'emergency'))!;
    expect(aircraftLabelled(a,labels:false),isFalse);
    expect(aircraftLabelled(a,labels:false,selectedId:'3c6444'),isTrue);
    expect(aircraftLabelled(u,labels:false),isTrue);
    expect(aircraftLabelled(a,labels:true),isTrue);
    expect(aircraftColorValue(Aircraft.fromJson({...plane(),'alt_ft':1500})!),0xFFF57C00,reason:'low = more visible');
  });

  test('selected aircraft: whole trace read from the server',() async {
    final api=SarcadeApi(baseUrl:'http://s',client:MockClient((r) async {
      if(r.url.path.endsWith('/track'))return http.Response(jsonEncode({'icao24':'3c6444','track':[[48.7,2.0],[48.75,2.05],[48.8,2.1]]}),200);
      return http.Response(jsonEncode({'enabled':true,'time':'t','aircraft':[plane()]}),200);
    }));
    final c=AdsbController(api:api,eventId:'e',deviceId:'TEL-1',box:()=>(south:48.7,west:1.9,north:48.9,east:2.2));
    await c.setOn(true);
    await c.select(c.aircraft.single);
    expect(c.selected?.icao24,'3c6444'); expect(c.track.length,3);
    c.setFollow(true); expect(c.follow,isTrue);
    await c.select(null);
    expect(c.selected,isNull); expect(c.follow,isFalse);
    c.dispose();
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
