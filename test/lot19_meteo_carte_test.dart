// Lot 19, card « Windows : météo absente de la pastille en haut à droite »
// (1 Nov 2026): the map loads the forecast of the event itself, at start,
// every 30 min and when the link comes back, into the cache of the Weather
// screen; a new device that never opened Météo has the temperature and the
// wind in the pill; offline, the last forecast stays with its time.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/link_weather_pill.dart';
import 'package:sarcade_app/src/features/weather/map_weather.dart';
import 'package:sarcade_app/src/features/weather/weather_models.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

/// Answer of `GET /events/E1/weather`: 7 °C, wind from the east 11 km/h.
Map<String,dynamic> _forecast(DateTime now)=>{'stale':false,'forecast':{'provider':'meteofrance','fetched_at':'2026-11-01T13:05:00Z',
  'hourly':[for(var i=-1;i<4;i++){'time':now.toUtc().add(Duration(hours:i)).toIso8601String(),'temperature_c':7.2,
    'wind_kmh':11,'wind_direction_deg':90,'weather_code':0}]}};

/// The pill as the map draws it (operational_map_page.dart, _linkWeatherPill).
Widget _pill(MapWeather w){
  final next=w.report?.upcoming(DateTime.now(),n:1)??const <WeatherHour>[];
  final h=next.isEmpty?null:next.first;
  return MaterialApp(home:Scaffold(body:Center(child:LinkWeatherPill(dot:Colors.green,linkTooltip:'',onLinks:(){},onWeather:(){},
    weatherText:h==null?null:w.pillText(pillWeatherText(temperatureC:h.temperatureC,compact:false,
      wind:h.windKmh==null?null:'${windDirection(h.windDirectionDeg)} ${h.windKmh!.round()} km/h'))))));
}

void main(){
  setUp(()=>S.setLanguage('fr'));

  testWidgets('new device, Météo never opened: temperature and wind in the pill',(t) async {
    final cache=<String,Map<String,dynamic>>{};
    var loads=0, online=true;
    final w=MapWeather(load:() async {loads++;if(!online)throw Exception('offline');return _forecast(DateTime.now());},
      read:()=>cache[weatherCacheKey('E1')],save:(j) async {cache[weatherCacheKey('E1')]=j;},
      online:()=>online,alive:()=>true,onChanged:(){});
    await t.pumpWidget(_pill(w));
    expect(find.textContaining('°'),findsNothing,reason:'nothing kept on a new device');
    w.start();
    await t.pump(); await t.pump();
    expect(loads,1);
    expect(cache.keys.toList(),['weather:E1'],reason:'same cache as the Weather screen');
    await t.pumpWidget(_pill(w));
    expect(find.text('7° · E 11 km/h'),findsOneWidget);
    // Offline: the last forecast stays, with its time.
    online=false;
    await w.refresh();
    expect(w.failed,isTrue);
    await t.pumpWidget(_pill(w));
    final l=DateTime.utc(2026,11,1,13,5).toLocal();
    final hm='${l.hour.toString().padLeft(2,'0')}:${l.minute.toString().padLeft(2,'0')}';
    expect(find.text('7° · E 11 km/h · à $hm'),findsOneWidget);
    w.stop();
  });

  test('loaded at start, every 30 min and when the link comes back',() async {
    var now=DateTime(2026,11,1,14), loads=0, online=false, changes=0;
    final cache=<String,Map<String,dynamic>>{};
    final w=MapWeather(load:() async {loads++;if(!online)throw Exception('offline');return _forecast(now);},
      read:()=>cache['weather:E1'],save:(j) async {cache['weather:E1']=j;},
      online:()=>online,alive:()=>true,onChanged:()=>changes++,now:()=>now);
    w.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(loads,1); expect(w.failed,isTrue); expect(cache,isEmpty);
    w.start();
    expect(loads,1,reason:'started once');
    // Link back: loaded at once.
    now=now.add(const Duration(seconds:15)); online=true;
    w.tick(); await Future<void>.delayed(Duration.zero);
    expect(loads,2); expect(w.failed,isFalse); expect(cache['weather:E1'],isNotNull);
    expect(cache['weather:E1']!['saved_at'],isNotNull);
    // Nothing new before 30 min.
    now=now.add(const Duration(minutes:29)); w.tick(); await Future<void>.delayed(Duration.zero);
    expect(loads,2);
    now=now.add(const Duration(minutes:1)); w.tick(); await Future<void>.delayed(Duration.zero);
    expect(loads,3);
    expect(changes,3);
    w.stop();
  });

  test('the map gone: the timer stops by itself',() async {
    var alive=true, loads=0;
    final w=MapWeather(load:() async {loads++;return const {};},read:()=>null,save:(_) async {},
      online:()=>true,alive:()=>alive,onChanged:(){});
    w.start(); await Future<void>.delayed(Duration.zero);
    alive=false; w.tick();
    expect(loads,1);
  });
}
