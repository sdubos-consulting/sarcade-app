/// ADS-B aircraft (module ADRASEC, step 1: OpenSky Network through the
/// server; card « ADS-B : aéronefs sur la carte », 1 Nov 2026). Pure code.
library;

import 'package:latlong2/latlong.dart';

import '../../../l10n/strings.dart';

class Aircraft {
  final String icao24;
  final String? callsign, country, squawk, emergency;
  final LatLng position;
  final int? altM, altFt, speedKt, trackDeg, lastContact;
  final double? verticalRateMps;
  final bool onGround, rotorcraft;
  final List<LatLng> trail;
  const Aircraft({required this.icao24,required this.position,this.callsign,this.country,this.squawk,this.emergency,
    this.altM,this.altFt,this.speedKt,this.trackDeg,this.lastContact,this.verticalRateMps,this.onGround=false,
    this.rotorcraft=false,this.trail=const []});

  static int? _i(Object? v)=>v is num?v.round():null;

  static Aircraft? fromJson(Object? j){
    if(j is! Map)return null;
    final lat=j['lat'], lon=j['lon'], id=j['icao24'];
    if(lat is! num||lon is! num||id is! String||id.isEmpty)return null;
    final cs=j['callsign'] is String?(j['callsign'] as String).trim():'';
    return Aircraft(icao24:id,position:LatLng(lat.toDouble(),lon.toDouble()),
      callsign:cs.isEmpty?null:cs,
      country:j['country'] as String?,squawk:j['squawk'] as String?,emergency:j['emergency'] as String?,
      altM:_i(j['alt_m']),altFt:_i(j['alt_ft']),speedKt:_i(j['speed_kt']),trackDeg:_i(j['track_deg']),
      lastContact:_i(j['last_contact']),verticalRateMps:(j['vertical_rate_mps'] as num?)?.toDouble(),
      onGround:j['on_ground']==true,rotorcraft:j['rotorcraft']==true,
      trail:[for(final p in (j['trail'] as List?)??const [])
        if(p is List&&p.length==2&&p[0] is num&&p[1] is num)LatLng((p[0] as num).toDouble(),(p[1] as num).toDouble())]);
  }

  /// Callsign, else the ICAO address in capitals.
  String get name=>callsign??icao24.toUpperCase();
  bool get urgent=>emergency!=null;
}

/// Aircraft of an answer or a broadcast ({aircraft:[…]}).
List<Aircraft> aircraftList(Object? data){
  final list=data is Map?data['aircraft']:null;
  if(list is! List)return const [];
  return [for(final a in list)?Aircraft.fromJson(a)];
}

/// Label on the map: « SAMU75 · 3 100 ft (950 m) · 100 kt ».
String aircraftLabel(Aircraft a)=>[
  a.name,
  if(a.onGround)S.t('adsb.onGround')
  else if(a.altFt!=null)'${_grouped(a.altFt!)} ft (${_grouped(a.altM??(a.altFt!/3.28084).round())} m)',
  if(a.speedKt!=null&&!a.onGround)'${a.speedKt} kt',
].join(' · ');

String _grouped(int v){
  final s=v.abs().toString(), out=StringBuffer(v<0?'-':'');
  for(var i=0;i<s.length;i++){if(i>0&&(s.length-i)%3==0)out.write(' ');out.write(s[i]);}
  return out.toString();
}

/// « urgence (7700) », « panne radio (7600) », « intervention illicite (7500) ».
String emergencyText(String code)=>S.t('adsb.emergency.$code');

/// Lines of the sheet, label key and value.
List<(String,String)> aircraftLines(Aircraft a,{DateTime? now}){
  final seen=a.lastContact==null?null:DateTime.fromMillisecondsSinceEpoch(a.lastContact!*1000,isUtc:true);
  final age=seen==null?null:(now??DateTime.now()).toUtc().difference(seen).inSeconds;
  return [
    ('adsb.field.icao',a.icao24.toUpperCase()),
    if(a.country!=null)('adsb.field.country',a.country!),
    if(a.altFt!=null)('adsb.field.altitude','${_grouped(a.altFt!)} ft · ${_grouped(a.altM??0)} m'),
    if(a.speedKt!=null)('adsb.field.speed','${a.speedKt} kt · ${(a.speedKt!*1.852).round()} km/h'),
    if(a.trackDeg!=null)('adsb.field.track','${a.trackDeg}°'),
    if(a.verticalRateMps!=null)('adsb.field.vertical','${a.verticalRateMps!>0?'+':''}${(a.verticalRateMps!*196.85).round()} ft/min'),
    if(a.squawk!=null)('adsb.field.squawk',a.urgent?'${a.squawk} · ${emergencyText(a.emergency!)}':a.squawk!),
    if(age!=null)('adsb.field.seen',S.t('adsb.secondsAgo',{'n':'${age<0?0:age}'})),
  ];
}
