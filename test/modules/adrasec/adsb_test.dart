// ADS-B step 1 (module ADRASEC, OpenSky through the server), 1 Nov 2026.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

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
    expect(aircraftLabel(a),'SAMU75 · 3 117 ft (950 m) · 100 kt');
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
    expect(find.text('SAMU75 · 3 117 ft (950 m) · 100 kt'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('adsb-3c6444')));
    expect(tapped?.icao24,'3c6444');
  });
}
