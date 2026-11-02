/// Weather of the map pill fetched by the map itself (lot 19, card
/// « Windows : météo absente de la pastille en haut à droite », 1 Nov 2026):
/// the pill only read the last forecast kept on the device, saved when the
/// Weather screen was opened; a computer that never opened it had no
/// temperature. Now the map loads the forecast of the event at start, every
/// 30 min and when the link comes back, into the same cache as the Weather
/// screen (`weather:<eventId>`); offline, the last one stays, with its time.
/// All platforms.
library;

import 'dart:async';

import '../../l10n/strings.dart';
import 'weather_models.dart';

/// Time between two loads of the forecast by the map.
const mapWeatherEvery=Duration(minutes:30);

/// Time between two looks at the link (its return triggers a load).
const mapWeatherCheck=Duration(seconds:15);

/// Cache key of the forecast of an event, shared with the Weather screen.
String weatherCacheKey(String eventId)=>'weather:$eventId';

class MapWeather {
  /// Forecast of the event from the server (`GET /events/{id}/weather`).
  final Future<Map<String,dynamic>> Function() load;
  /// Last forecast kept on the device, and its saving.
  final Map<String,dynamic>? Function() read;
  final Future<void> Function(Map<String,dynamic> j) save;
  /// The server answers (synchronisation working).
  final bool Function() online;
  /// The map is still there: the timer stops by itself after it.
  final bool Function() alive;
  /// A new forecast was saved, or the state changed: rebuild the pill.
  final void Function() onChanged;
  final DateTime Function() now;
  MapWeather({required this.load,required this.read,required this.save,required this.online,required this.alive,
    required this.onChanged,DateTime Function()? now}):now=now??DateTime.now;

  Timer? _timer;
  bool _loading=false, _failed=false, _wasOnline=true;
  DateTime? _lastTry;

  /// The last load failed: the pill shows the kept forecast with its time.
  bool get failed=>_failed;

  /// At start of the map: a first load, then the timer. Called again, it
  /// does nothing.
  void start(){
    if(_timer!=null||_lastTry!=null)return;
    _wasOnline=online();
    // Started from a build (the pill): the load begins after it.
    _lastTry=now();
    scheduleMicrotask(()=>unawaited(refresh()));
    _timer=Timer.periodic(mapWeatherCheck,(_)=>tick());
  }

  void stop(){_timer?.cancel();_timer=null;}

  /// Every [mapWeatherCheck]: link back → load; [mapWeatherEvery] passed → load.
  void tick(){
    if(!alive()){stop();return;}
    final on=online(), back=on&&!_wasOnline;
    _wasOnline=on;
    final last=_lastTry;
    if(back||last==null||now().difference(last)>=mapWeatherEvery)unawaited(refresh());
  }

  /// Loads the forecast and keeps it (same cache as the Weather screen).
  Future<void> refresh() async {
    if(_loading)return;
    _loading=true; _lastTry=now();
    try{
      final j=await load();
      // Time it reached the device, for a forecast without « fetched_at ».
      await save({...j,'saved_at':now().toUtc().toIso8601String()});
      _failed=false;
    }catch(_){
      _failed=true;
    }finally{
      _loading=false;
    }
    if(alive())onChanged();
  }

  /// Last forecast kept on the device (null on a new device before the
  /// first load).
  WeatherReport? get report{final j=read();return j==null?null:WeatherReport.fromJson(j);}

  /// Time of the kept forecast: when the server fetched it, else when it
  /// reached the device.
  DateTime? get keptAt{
    final j=read(); if(j==null)return null;
    return WeatherReport.fromJson(j).fetchedAt??DateTime.tryParse('${j['saved_at']}');
  }

  /// Text of the pill: offline (or last load failed), the time of the kept
  /// forecast is added: « 7° · E 11 km/h · à 14:05 ».
  String? pillText(String? text){
    if(text==null||(!_failed&&online()))return text;
    final at=keptAt; if(at==null)return text;
    final l=at.toLocal(); String two(int v)=>v.toString().padLeft(2,'0');
    return S.t('weather.pillAt',{'text':text,'time':'${two(l.hour)}:${two(l.minute)}'});
  }
}
