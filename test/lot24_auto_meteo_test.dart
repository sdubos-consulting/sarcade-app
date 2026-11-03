// Android Auto, lot 24, card « Android Auto : météo et vigilance à
// destination »: temperature, wind, rain within the hour and vigilance of
// the department in the card of a point or an order (forecast of the
// server, as the weather of the application); vigilance orange or red at
// the destination of an accepted order read aloud.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/car/car_field.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/features/car/car_weather.dart';
import 'package:sarcade_app/src/features/orders/move_orders.dart';
import 'package:sarcade_app/src/features/weather/weather_models.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/poi.dart';

final now=DateTime.utc(2026,11,3,9,10);
const dest=LatLng(48.82,1.92);

Map<String,dynamic> forecast({int vigilance=2,double rain=0.4})=>{
  'forecast':{'provider':'meteofrance','hourly':[
    {'time':'2026-11-03T09:00:00Z','temperature_c':12.4,'wind_kmh':19.6,'wind_direction_deg':315,'precipitation_mm':rain},
    {'time':'2026-11-03T10:00:00Z','temperature_c':13.0,'wind_kmh':25.0,'wind_direction_deg':300,'precipitation_mm':2.0},
  ]},
  'vigilance':{'department':'78','color_id':vigilance,'phenomena':['vent violent','orages']},
};

MoveOrder order(String status)=>MoveOrder({'id':'o1','event_id':'e','target_id':'TEL-1','created_by':'PCO','status':status,
  'destination':{'lat':dest.latitude,'lon':dest.longitude,'label':'P2'},'updated_at':now.toIso8601String()});

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>S.setLanguage('fr'));

  late List<String> asked;
  late int vigilance;
  late DateTime clock;
  setUp((){asked=[];vigilance=2;clock=now;});
  CarField field()=>CarField(baseUrl:'https://s',eventId:'e',me:'TEL-1',clock:()=>clock,
    client:()=>throw StateError('no HTTP'),
    queue:({required String objectId,required String objectType,required Map<String,dynamic> payload,String action='create'}) async {},
    pointWeather:(lat,lon) async {asked.add(carWeatherKey(lat,lon));return forecast(vigilance:vigilance);});
  CarScreenInput input(CarField f,{String status='accepted'})=>CarScreenInput(me:'TEL-1',eventId:'e',now:clock,field:f,
    orders:[order(status)],pois:[SarcadePoi(id:'poi1',eventId:'e',kind:'designated',label:'P2',lat:dest.latitude,lon:dest.longitude,createdAt:now)]);
  final act=CarScreenActions(order:(o,s) async {},ack:(a,m) async {},send:(m) async {},sos:() async {},sosEnd:() async {});

  test('card: temperature, wind, rain within the hour, vigilance and its colour',() async {
    final f=field();
    final snap0=carSnapshot(input(f));
    final key=((snap0['points'] as List).first as Map)['wkey'];
    expect(key,'48.82,1.92');
    expect(((snap0['orders'] as List).first as Map)['wkey'],key);
    expect(snap0['weather'],isEmpty);
    await applyCarAction(CarAction('weather',{'lat':dest.latitude,'lon':dest.longitude}),input(f),act);
    await Future<void>.delayed(Duration.zero);
    final w=(carSnapshot(input(f))['weather'] as Map)[key] as Map;
    expect(w['text'],'12 °C · vent 20 km/h NO');
    expect(w['rain'],'Pluie dans l’heure : 0,4 mm');
    expect(w['vigilance'],'Vigilance jaune (78)');
    expect(w['phenomena'],'vent violent, orages');
    expect(w['vigColor'],0xFFFDD835);
    expect(carWeatherCard(WeatherReport.fromJson(forecast(rain:0)),now)!['rain'],'Pas de pluie dans l’heure');
  });

  test('fetched once every 15 minutes for the same place',() async {
    final f=field();
    await f.weather.want(48.821,1.919,clock);
    await f.weather.want(48.8204,1.9198,clock.add(const Duration(minutes:5)));
    expect(asked,['48.82,1.92']);
    await f.weather.want(48.82,1.92,clock.add(const Duration(minutes:16)));
    expect(asked.length,2);
  });

  test('vigilance orange or red at the destination of an accepted order: read aloud, once by rise',() async {
    final f=field();
    await carFieldTick(input(f));
    await Future<void>.delayed(Duration.zero);
    expect(f.said,isNull,reason:'yellow');
    vigilance=3; clock=clock.add(const Duration(minutes:16));
    await carFieldTick(input(f));
    await Future<void>.delayed(Duration.zero);
    expect(f.said!.text,'Attention : Vigilance orange (78) à destination : vent violent, orages.');
    final first=f.said!.id;
    clock=clock.add(const Duration(minutes:16));
    await carFieldTick(input(f));
    await Future<void>.delayed(Duration.zero);
    expect(f.said!.id,first,reason:'still orange: not again');
    vigilance=4; clock=clock.add(const Duration(minutes:16));
    await carFieldTick(input(f));
    await Future<void>.delayed(Duration.zero);
    expect(f.said!.text,startsWith('Attention : Vigilance rouge (78)'));
  });

  test('no mission (order not accepted): nothing read',() async {
    vigilance=4;
    final f=field();
    await carFieldTick(input(f,status:'sent'));
    await Future<void>.delayed(Duration.zero);
    expect(f.said,isNull);
    expect(asked,isEmpty);
  });
}
