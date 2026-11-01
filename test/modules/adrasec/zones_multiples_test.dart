// Several beacons on one signal (option 1 validated 1 Nov 2026, 7 h 44):
// same cases as the server (tests/test_tv.py).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/modules/adrasec/bearings/bearing_models.dart';

var _n=0;
Bearing towards(double lat,double lon,LatLng t,{String zone='auto',String? id}){
  final dy=(t.latitude-lat)*110540.0, dx=(t.longitude-lon)*111320.0*math.cos(lat*math.pi/180);
  final az=(math.atan2(dx,dy)*180/math.pi+360)%360;
  final now=DateTime.utc(2026,11,1);
  return Bearing(id:id??'b${_n++}',eventId:'e',origin:LatLng(lat,lon),azimuthDeg:az,zone:zone,search:'121,375 MHz',
    takenAt:now,createdBy:'A',updatedBy:'A',updatedAt:now);
}

const target=LatLng(48.80,2.10), second=LatLng(48.86,1.92);
List<Bearing> good()=>[towards(48.75,2.10,target),towards(48.80,2.03,target),towards(48.75,2.04,target),towards(48.85,2.16,target)];
List<Bearing> other()=>[towards(48.82,1.90,second),towards(48.88,1.86,second),towards(48.86,2.00,second)];

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
    final zones=probableZones([...good(),towards(48.78,2.20,const LatLng(48.70,2.05)),towards(48.70,2.00,const LatLng(48.95,2.30))]);
    expect(zones.length,1); expect(zones.single.index,0);
    expect(zonesLabel(zones.single),startsWith('±'));
  });

  test('three bearings from one place never make a zone',(){
    final same=[for(var i=0;i<3;i++)towards(48.90,1.96,second,id:'p$i')];
    expect(probableZones([...good(),...same]).length,1);
  });

  test('a bearing kept by hand keeps one zone',(){
    final o=other();
    final zones=probableZones([...good(),o[0],o[1],towards(48.86,2.00,second,zone:'in')]);
    expect(zones.length,1);
  });
}
