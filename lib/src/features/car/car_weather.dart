/// Weather and vigilance at the destination, in the car (lot 24, card
/// « Android Auto : météo et vigilance à destination »):
/// 1. in the card of a point and of an order: temperature, wind, rain to
///    come within the hour at the destination (same source as the weather
///    of the application: GET /weather of the server, Météo-France first);
/// 2. Météo-France vigilance of the department of the point (colour and
///    phenomena), the colour in the picture of the row;
/// 3. read aloud when the vigilance at the destination of an accepted
///    order (a mission in progress) is orange or red, or rises.
/// Pure Dart: the forecast is fetched by the function given by the map page
/// (SarcadeApi.pointWeather).
library;

import '../../l10n/strings.dart';
import '../weather/weather_models.dart';

/// Forecast of a place (SarcadeApi.pointWeather).
typedef CarFetchWeather=Future<Map<String,dynamic>> Function(double lat,double lon);

/// Places closer than about 1 km share their forecast.
String carWeatherKey(double lat,double lon)=>'${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';

/// Colours of the vigilance (Météo-France): green, yellow, orange, red.
int carVigilanceColor(int id)=>switch(id){2=>0xFFFDD835,3=>0xFFFB8C00,4=>0xFFE53935,_=>0xFF43A047};

/// What the card of a point or an order shows of [r]: « 12 °C · vent
/// 20 km/h NO », « Pas de pluie dans l'heure », the vigilance and its colour.
Map<String,Object?>? carWeatherCard(WeatherReport r,DateTime now){
  final h=r.upcoming(now,n:1).firstOrNull;
  final v=r.vigilance;
  if(h==null&&v==null)return null;
  return {
    if(h!=null)...{
      'text':[
        if(h.temperatureC!=null)'${h.temperatureC!.round()} °C',
        if(h.windKmh!=null)S.t('car.wind',{'v':h.windKmh!.round(),'dir':windDirection(h.windDirectionDeg)}).trim(),
      ].join(' · '),
      'rain':(h.precipitationMm??0)>0?S.t('car.rain',{'mm':rainLabel(h.precipitationMm!)}):S.t('car.noRain'),
    },
    if(v!=null)...{
      'vigilance':S.t('weather.vigilance.${v.colorId.clamp(1,4)}',{'dep':v.department}),
      'phenomena':v.phenomena.join(', '),
      'vigColor':carVigilanceColor(v.colorId),
    },
  };
}

class CarWeather {
  final CarFetchWeather? fetch;
  /// Text to read aloud in the car.
  final void Function(String text) say;
  CarWeather({required this.fetch,required this.say});

  /// A forecast is fetched again after this time.
  static const keep=Duration(minutes:15);
  /// …and no longer shown after this one.
  static const shown=Duration(hours:1);

  final Map<String,({DateTime at,WeatherReport r})> _cache={};
  final Set<String> _loading={};
  /// Highest vigilance known at the destination of each order (choice 3).
  final Map<String,int> _vigilance={};

  /// Forecast of the place, null when not fetched yet (or too old).
  WeatherReport? of(double lat,double lon,DateTime now){
    final c=_cache[carWeatherKey(lat,lon)];
    return c==null||now.difference(c.at)>shown?null:c.r;
  }

  /// Cards of the places known, by key (data of the car).
  Map<String,Object?> cards(DateTime now)=>{
    for(final e in _cache.entries)
      if(now.difference(e.value.at)<=shown)
        e.key:?carWeatherCard(e.value.r,now),
  };

  /// Fetches the forecast of the place unless a recent one is kept.
  Future<WeatherReport?> want(double lat,double lon,DateTime now) async {
    final f=fetch;
    if(f==null||!lat.isFinite||!lon.isFinite)return null;
    final key=carWeatherKey(lat,lon);
    final c=_cache[key];
    if(c!=null&&now.difference(c.at)<keep)return c.r;
    if(!_loading.add(key))return c?.r;
    try{
      final r=WeatherReport.fromJson(await f(lat,lon).timeout(const Duration(seconds:10)));
      _cache[key]=(at:now,r:r);
      return r;
    }catch(_){
      return c?.r; // no network: the last one stays
    }finally{
      _loading.remove(key);
    }
  }

  /// Destinations of the accepted orders (missions in progress): their
  /// forecast kept fresh, and the vigilance read aloud when orange or red
  /// and higher than known for that order.
  Future<void> watch(List<({String id,double lat,double lon})> missions,DateTime now) async {
    _vigilance.removeWhere((id,_)=>!missions.any((m)=>m.id==id));
    for(final m in missions){
      final r=await want(m.lat,m.lon,now);
      final v=r?.vigilance;
      if(v==null)continue;
      final before=_vigilance[m.id]??1;
      _vigilance[m.id]=v.colorId>before?v.colorId:before;
      if(v.isAlert&&v.colorId>before){
        final level=S.t('weather.vigilance.${v.colorId.clamp(1,4)}',{'dep':v.department});
        say('${[S.t('car.vigilanceSay',{'level':level}),if(v.phenomena.isNotEmpty)v.phenomena.join(', ')].join(' : ')}.');
      }
    }
  }
}
