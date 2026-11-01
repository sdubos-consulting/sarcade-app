// Lot 19, card « Recherche : nœuds MeshCore et avions » (validated on
// 1 Nov 2026, 21 h 42): nodes by name and start of the key, with and
// without position; aircraft by callsign and ICAO code; the layer Aéronefs
// switched on; the order of the results.
import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_map.dart' show meshCoreSelected;
import 'package:sarcade_app/src/features/meshcore/meshcore_page.dart' show meshCoreFocusQuery;
import 'package:sarcade_app/src/features/search/map_search.dart';
import 'package:sarcade_app/src/features/search/map_search_sources.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/modules/adrasec/adsb/adsb_controller.dart';
import 'package:sarcade_app/src/modules/adrasec/adsb/adsb_search.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';

final now=DateTime.utc(2026,11,1,21,0);
final relay=MeshCoreContact(key:'a1b2c3d4e5f6',type:2,name:'Relais Élancourt',lastAdvert:now.subtract(const Duration(minutes:3)),lat:48.78,lon:1.95);
final companion=MeshCoreContact(key:'f0e1d2c3b4a5',type:1,name:'Boîtier Maurepas',lastAdvert:now.subtract(const Duration(hours:2)));

Map<String,dynamic> plane({String icao='3c6444',String? callsign='AFR92SC',bool rotor=false,bool ground=false})=>{
  'icao24':icao,'callsign':callsign,'lat':48.8,'lon':2.1,'alt_m':950,'alt_ft':3100,'on_ground':ground,'rotorcraft':rotor,'speed_kt':120};

AdsbController controller()=>AdsbController(api:SarcadeApi(baseUrl:'http://s',client:MockClient((r) async=>http.Response(jsonEncode({'enabled':true}),200))),
  eventId:'e',deviceId:'TEL-1',box:()=>null);

void main(){
  setUp(()=>S.setLanguage('fr'));

  group('MeshCore nodes',(){
    final items=meshCoreSearchables([relay,companion],now);
    test('by name (accents ignored) and by start of the key',(){
      expect(searchLocal('elancourt',items).single.title,'Relais Élancourt');
      expect(searchLocal('F0E1',items).single.title,'Boîtier Maurepas');
      expect(searchLocal('d2c3',items),isEmpty,reason:'the start of the key only');
    });
    test('kind and age in words; without position',(){
      final r=searchLocal('relais',items).single;
      expect(r.kind,SearchKind.meshNode);
      expect(r.subtitle,'Répéteur · il y a 3 min');
      expect(r.placed,isTrue); expect(r.point,const LatLng(48.78,1.95)); expect(r.ref,relay.key);
      final b=searchLocal('maurepas',items).single;
      expect(b.subtitle,'Compagnon · il y a 2 h · sans position');
      expect(b.placed,isFalse);
    });
    test('with position: the map on it and its card; without: Outils › MeshCore on it',() async {
      final map=MapController();
      MeshCoreContact? opened;
      meshCoreSelected.value=null;
      expect(openFoundOnMap(searchLocal('relais',items).single,map:map,nodes:[relay,companion],openNodeInTool:(c)=>opened=c),isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(meshCoreSelected.value,relay.key);
      expect(opened,isNull);
      expect(openFoundOnMap(searchLocal('maurepas',items).single,map:map,nodes:[relay,companion],openNodeInTool:(c)=>opened=c),isTrue);
      expect(opened?.key,companion.key);
      expect(meshCoreFocusQuery(companion),'Boîtier Maurepas');
    });
  });

  group('aircraft',(){
    test('by callsign and by ICAO code; altitude and kind in words',(){
      final c=controller();
      c.onRealtime('adsb.updated',{'aircraft':[plane(),plane(icao:'39ac45',callsign:null,rotor:true)]});
      final items=aircraftSearchables(c.received(DateTime.now()));
      final r=searchLocal('afr92',items).single;
      expect(r.kind,SearchKind.aircraft);
      expect(r.subtitle,'3 100 ft · Avion · 3C6444');
      expect(searchLocal('3C64',items).single.title,'AFR92SC');
      final h=searchLocal('39ac45',items).single;
      expect(h.title,'39AC45'); expect(h.subtitle,'3 100 ft · Hélicoptère');
      c.dispose();
    });
    test('only the aircraft received now',(){
      final c=controller();
      expect(c.received(DateTime.now()),isEmpty);
      c.onRealtime('adsb.updated',{'aircraft':[plane()]});
      expect(c.received(DateTime.now()).length,1);
      expect(c.received(DateTime.now().add(const Duration(minutes:3))),isEmpty,reason:'old broadcast');
      expect(c.aircraft,isEmpty,reason:'layer off: nothing drawn');
      c.dispose();
    });
    test('layer off: the result switches it on and opens the sheet',() async {
      final c=controller();
      c.onRealtime('adsb.updated',{'aircraft':[plane()]});
      expect(c.on,isFalse);
      final r=searchLocal('AFR92SC',aircraftSearchables(c.received(DateTime.now()))).single;
      expect(openFoundOnMap(r,map:MapController(),openNodeInTool:(_){}),isFalse,reason:'not a MeshCore node');
      expect(openAircraftFound(r,map:MapController(),adsb:c),isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(c.on,isTrue);
      expect(c.selectedId,'3c6444');
      expect(c.selected?.name,'AFR92SC');
      c.dispose();
    });
  });

  test('order: coordinates, operators, aircraft, MeshCore nodes, reference, points, drawings',(){
    const p=LatLng(48.8,1.9);
    final items=[
      const Searchable(SearchKind.drawing,'Zone Maurepas','',p),
      const Searchable(SearchKind.poi,'Mairie de Maurepas','',p),
      const Searchable(SearchKind.reference,'PH Maurepas','',p),
      ...meshCoreSearchables([companion],now),
      ...aircraftSearchables([]),
      const Searchable(SearchKind.aircraft,'MAUREPAS1','',p),
      const Searchable(SearchKind.operator,'Maurepas-1','',p),
    ];
    expect(searchLocal('maurepas',items).map((r)=>r.kind),[SearchKind.operator,SearchKind.aircraft,SearchKind.meshNode,
      SearchKind.reference,SearchKind.poi,SearchKind.drawing]);
    expect(SearchKind.values.last,SearchKind.address);
    expect(S.t('search.kind.meshNode'),'Nœud MeshCore');
  });
}
