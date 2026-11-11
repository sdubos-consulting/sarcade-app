// Android Auto, lot 20 (card « Android Auto, onglet Points : boutons ronds
// gris vides, SOS en disque blanc, ligne coupée », choice 3): the line of a
// point is short, « 3 km NO », so that it is no longer cut. The icons of
// the buttons and the red SOS are in the plugin (MainScreen.kt, CarUi.kt).
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/poi.dart';

final now=DateTime.utc(2026,11,2,8,0);
const here=LatLng(48.80,1.95);

void main(){
  tearDown(()=>S.setLanguage('fr'));

  test('short line of the Points tab: rounded distance, short direction',(){
    S.setLanguage('fr');
    // ≈ 3 km to the north-west.
    const nw=LatLng(48.8191,1.9210);
    expect(carAway(here,nw,short:true),'3 km NO');
    expect(carAway(here,nw),'3 km au nord-ouest',reason:'other tabs keep the long form');
    final p=carPoints(CarScreenInput(me:'TEL-1',eventId:'e',now:now,here:here,
      pois:[SarcadePoi(id:'poi1',eventId:'e',kind:'designated',lat:nw.latitude,lon:nw.longitude,createdAt:now,label:'PC',createdBy:'PCO')],
      references:const [(id:'h1',name:'Butte',relay:false,lat:48.8191,lon:1.9790,mhz:null,altM:412.0)]));
    expect(p[0]['text'],'3 km NO');
    expect(p[1]['text'],'3 km NE · Point haut · 412 m');
    S.setLanguage('en');
    expect(carAway(here,nw,short:true),'3 km NW');
    expect(carAway(here,const LatLng(48.80,1.91),short:true),'3 km W');
  });
}
