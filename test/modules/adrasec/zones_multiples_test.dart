// Several beacons on one signal (option 1 validated 1 Nov 2026, 7 h 44) and
// card « Plusieurs zones : le découpage ne se fait pas quand un relevé est
// gardé à la main » (points 1 to 13, 1 Nov 2026): same cases as the server
// (tests/test_tv.py), keep in step.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/drawing/geometry.dart' as geo;
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/modules/adrasec/bearings/bearing_models.dart';

var _n=0;
Bearing towards(double lat,double lon,LatLng t,{String zone='auto',String? id,double lengthM=10000,double? deltaDeg}){
  final dy=(t.latitude-lat)*110540.0, dx=(t.longitude-lon)*111320.0*math.cos(lat*math.pi/180);
  final az=(math.atan2(dx,dy)*180/math.pi+360+(deltaDeg??0))%360;
  final now=DateTime.utc(2026,11,1);
  return Bearing(id:id??'b${_n++}',eventId:'e',origin:LatLng(lat,lon),azimuthDeg:az,zone:zone,search:'121,375 MHz',lengthM:lengthM,
    takenAt:now,createdBy:'A',updatedBy:'A',updatedAt:now);
}

const target=LatLng(48.80,2.10), second=LatLng(48.86,1.92);
List<Bearing> good()=>[towards(48.75,2.10,target),towards(48.80,2.03,target),towards(48.75,2.04,target),towards(48.85,2.16,target)];
List<Bearing> other()=>[towards(48.82,1.90,second),towards(48.88,1.86,second),towards(48.86,2.00,second)];
/// Azimuth errors of the realistic set, the same as the server tests.
const noise=[2.1,-1.4,0.7,-2.6,1.9,-0.3,2.8,-1.1,-2.2,1.3,0.4,-2.9,1.6,-0.8,2.5,-1.7];
Bearing wild({String zone='auto',String? id})=>towards(48.78,2.20,const LatLng(48.70,2.05),zone:zone,id:id);

void main(){
  setUp(()=>S.setLanguage('fr'));

  test('two beacons, two zones',(){
    final zones=probableZones([...good(),...other()]);
    expect(zones.length,2);
    final z1=zones[0], z2=zones[1];
    expect(z1.index,1); expect(z1.bearings,4); expect(z2.bearings,3);
    expect((z1.centre!.latitude-target.latitude).abs(),lessThan(0.004));
    expect((z2.centre!.latitude-second.latitude).abs(),lessThan(0.004));
    expect(zonesLabel(z1),startsWith('Zone 1 · ±'));
    expect(zonesLabel(z2),startsWith('Zone 2 · ±'));
    expect(z1.excluded,isEmpty);
  });

  test('one beacon and wrong bearings stay one zone',(){
    final zones=probableZones([...good(),wild(),towards(48.70,2.00,const LatLng(48.95,2.30))]);
    expect(zones.length,1); expect(zones.single.index,0);
    expect(zonesLabel(zones.single),startsWith('±'));
  });

  test('one beacon and one wrong bearing: one zone, one set aside',(){
    final w=wild(id:'w');
    final z=probableZones([...good(),w]).single;
    expect(z.index,0); expect(z.excluded,['w']); expect(z.mode,'auto');
  });

  test('three bearings from one place never make a zone',(){
    final same=[for(var i=0;i<3;i++)towards(48.90,1.96,second,id:'p$i')];
    expect(probableZones([...good(),...same]).length,1);
  });

  test('capture: two groups of three and one kept by hand make two zones (points 1, 2)',(){
    final zones=probableZones([...good().take(3),...other(),wild(zone:'in',id:'hand')]);
    expect(zones.length,2);
    expect(zones[0].bearings,4); expect(zones[1].bearings,3);   // kept by hand in zone 1
    expect(zones[0].excluded,isEmpty);
    final o=other();
    final again=probableZones([...good(),o[0],o[1],towards(48.86,2.00,second,zone:'in')]);
    expect([for(final z in again)z.bearings],[4,3]);
    expect((again[1].centre!.latitude-second.latitude).abs(),lessThan(0.004));
  });

  test('kept by hand joins the zone it agrees with',(){
    final zones=splitZones([...good(),...other(),towards(48.90,1.80,second,zone:'in',id:'hand')])!;
    expect(zones.length,2);
    final z2=zones.firstWhere((z)=>(z.centre!.latitude-second.latitude).abs()<0.004);
    expect(z2.bearings,4);
  });

  test('set aside by hand stays set aside (point 3)',(){
    final zones=probableZones([...good(),...other(),towards(48.70,2.15,target,zone:'out',id:'out')]);
    expect(zones.length,2); expect(zones[0].excluded,['out']); expect(zones[0].autoExcluded,isEmpty);
    expect(zones[0].bearings,4); expect(zones[1].bearings,3);
  });

  test('a grown zone keeps its seed and the zones found (points 5, 6)',(){
    final far=[towards(48.82,2.50,const LatLng(48.82,2.10),lengthM:40000,id:'f1'),towards(48.55,2.12,const LatLng(48.80,2.12),lengthM:40000,id:'f2')];
    final all=[...good(),...other(),...far];
    final grown=splitZones(all,maxRadiusM:1e9)!.first.radiusM;
    final zones=splitZones(all,maxRadiusM:grown-100)!;
    expect(zones.length,2);
    expect(zones[0].radiusM,lessThanOrEqualTo(grown-100));
    expect(zones[0].bearings+zones[1].bearings+zones[0].excluded.length,all.length);
  });

  test('mode « Une seule balise »: one circle',(){
    final zones=probableZones([...good(),...other()],mode:'single');
    expect(zones.length,1); expect(zones.single.mode,'single');
    expect(zonesLabel(zones.single),startsWith('Une seule balise · ±'));
  });

  test('mode « Plusieurs balises »: two zones, the label tells it (point 12)',(){
    final zones=probableZones([...good(),...other()],mode:'multi');
    expect(zones.length,2);
    expect(zonesLabel(zones[0]),startsWith('Zone 1 · plusieurs balises · ±'));
    expect(zonesLabel(zones[1]),startsWith('Zone 2 · plusieurs balises · ±'));
    expect(zonesLabel(probableZones([...good(),...other()])[0]),startsWith('Zone 1 · ±'));
  });

  test('mode « Plusieurs balises »: relaxed thresholds (point 8)',(){
    final o=other();
    final wide=[o[0],towards(48.88,1.86,second,deltaDeg:30),o[2]];
    expect(probableZones([...good(),...wide]).length,1);
    expect(probableZones([...good(),...wide],mode:'multi').length,2);
  });

  test('realistic: two beacons 10 km apart, four teams from two places each',(){
    const b1=LatLng(48.80,2.10), b2=LatLng(48.83,2.23);
    expect(geo.distanceM(b1,b2),inInclusiveRange(9000,11000));
    const places=[LatLng(48.74,2.05),LatLng(48.76,2.08),LatLng(48.88,2.02),LatLng(48.90,2.06),
      LatLng(48.86,2.30),LatLng(48.88,2.27),LatLng(48.75,2.25),LatLng(48.74,2.20)];
    final all=[for(var k=0;k<places.length;k++)for(final (n,t) in [(1,b1),(2,b2)])
      towards(places[k].latitude,places[k].longitude,t,lengthM:15000,id:'$k-$n',deltaDeg:noise[2*k+n-1])];
    for(final mode in ['auto','multi']){
      final zones=probableZones(all,mode:mode);
      expect(zones.length,2,reason:mode);
      for(final z in zones){
        expect(math.min(geo.distanceM(z.centre!,b1),geo.distanceM(z.centre!,b2)),lessThan(1500),reason:mode);
      }
    }
    expect(probableZones(all,mode:'single').single.index,0);
  });

  test('mode of a signal read from the event settings (point 11)',(){
    final modes=zoneModesOf({'zone_modes':{"121,375 mhz · balise d'exercice":'multi','réseau':'nope','x':'single'}});
    expect(modes,{"121,375 mhz · balise d'exercice":'multi','x':'single'});
    expect(zoneModeOf(modes,'121,375 MHz · Balise d’Exercice'),'multi');
    expect(zoneModeOf(modes,'autre'),'auto');
    expect(zoneModeKey('  Réseau  Été '),'reseau ete');
    expect(zoneModesOf(const {}),isEmpty);
  });
}
