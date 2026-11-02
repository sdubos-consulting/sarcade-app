// Android Auto, lot 20 (card « Android Auto, onglet Points : retirer les
// relais radio, garder les endroits utiles pour se déplacer »): the points
// of the event first, then up to 10 high points within 50 km, with their
// altitude; never a relay.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/poi.dart';

final now=DateTime.utc(2026,11,2,8,0);
const here=LatLng(48.80,1.95);

CarSite site(String id,{bool relay=false,required double lat,double? alt})=>
  (id:id,name:'Site $id',relay:relay,lat:lat,lon:1.95,mhz:relay?145.275:null,altM:alt);

void main(){
  setUp(()=>S.setLanguage('fr'));

  test('points of the event, then the 10 nearest high points within 50 km, no relay',(){
    final refs=<CarSite>[
      for(var k=1;k<=12;k++)site('h$k',lat:48.80+k*0.02,alt:100.0+k),
      site('r1',relay:true,lat:48.801),
      site('far',lat:49.40,alt:300),
    ];
    final p=carPoints(CarScreenInput(me:'TEL-1',eventId:'e',now:now,here:here,references:refs,
      pois:[SarcadePoi(id:'poi1',eventId:'e',kind:'designated',lat:49.0,lon:1.95,createdAt:now,label:'PC',createdBy:'PCO')]));
    expect(p.first['id'],'poi1',reason:'the event first, even when farther');
    expect(p.skip(1).map((x)=>x['id']),[for(var k=1;k<=10;k++)'h$k']);
    expect(p.any((x)=>x['kind']=='relay'||x['icon']=='relay'),isFalse);
    expect(p[1]['text'],contains('· 101 m'));
    expect(p[1]['icon'],'high');
  });
}
