// Android Auto, lot 23 (card « Android Auto, onglet Points : changer de
// filtre en appuyant de nouveau sur l'onglet »): texts of the filter sent to
// the car, and the kind of each point the car filters on (the loop itself
// is tested with the car screens, third_party/sarcade_car/android/src/test).
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/poi.dart';

final now=DateTime.utc(2026,11,2,20,30);

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>S.setLanguage('fr'));

  test('filter texts in French and English',(){
    var l=carLabels();
    expect(l['filter']!.replaceAll('{name}',l['filter.all']!),'Filtre : Tout');
    expect(l['filter.event'],'Points de l’événement');
    expect(l['filter.high'],'Points hauts');
    S.setLanguage('en');
    l=carLabels();
    expect(l['filter']!.replaceAll('{name}',l['filter.high']!),'Filter: High points');
    expect(l['filter.event'],'Event points');
  });

  test('each point tells its kind: event point or high point',(){
    final p=carPoints(CarScreenInput(me:'TEL-1',eventId:'e',now:now,here:const LatLng(48.80,1.95),
      pois:[SarcadePoi(id:'poi1',eventId:'e',kind:'designated',lat:48.79,lon:1.95,createdAt:now,label:'F6KRK',icon:'flag',createdBy:'PCO')],
      references:[(id:'h1',name:'Butte',relay:false,lat:48.85,lon:1.95,mhz:null,altM:180.0)]));
    expect(p.map((x)=>'${x['id']}:${x['kind']}'),['poi1:poi','h1:high']);
  });
}
