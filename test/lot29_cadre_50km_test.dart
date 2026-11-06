import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/operators_frame.dart';
import 'package:sarcade_app/src/models/position.dart';

SarcadePosition _p(String id,double lat,double lon,DateTime t)=>SarcadePosition(id:id,eventId:'e',deviceId:id,lat:lat,lon:lon,time:t);

void main(){
  final now=DateTime.utc(2026,11,5,12);
  const versailles=LatLng(48.80,2.13);
  test('only operators within 50 km, fresh and valid',(){
    final f=operatorsFrame([
      _p('a',48.85,2.35,now),          // Paris, ~17 km
      _p('b',43.30,5.37,now),          // Marseille
      _p('c',0,0,now),                 // invalid
      _p('d',48.81,2.14,now.subtract(const Duration(hours:30))), // too old
    ],versailles,now);
    expect(f.inside.length,1); expect(f.all.length,2); expect(f.outside,1);
  });
  test('radius from the preference',(){
    expect(frameRadiusFrom(null),50); expect(frameRadiusFrom('25'),25); expect(frameRadiusFrom('33'),50);
  });
  test('nobody in the radius: a 50 km box around me',(){
    final box=radiusBox(versailles,50);
    expect(box.length,4);
    expect(const Distance().as(LengthUnit.Kilometer,versailles,box.first),closeTo(50,1));
  });
}
