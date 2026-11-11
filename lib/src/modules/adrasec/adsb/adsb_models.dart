/// ADS-B aircraft (module ADRASEC, step 1: OpenSky Network through the
/// server; card « ADS-B : aéronefs sur la carte », 1 Nov 2026). Pure code.
///
/// Lot 17 (cards validated 1 Nov 2026, 11 h 29 to 12 h 04): three altitude
/// bands Bas / Moyen / Haut with adjustable thresholds, each shown or not
/// (replaces the 0 → ∞ range of #181); position estimated from the OpenSky
/// time of the position (60 s at most, then grey); icon by OpenSky category.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../../l10n/strings.dart';

class Aircraft {
  final String icao24;
  final String? callsign, country, squawk, emergency;
  final LatLng position;
  final int? altM, altFt, speedKt, trackDeg, lastContact;
  /// OpenSky category (null, 0 or 1: not transmitted; 8 = rotorcraft).
  final int? category;
  /// OpenSky time of the position (epoch seconds), else [lastContact].
  final double? positionTime;
  final double? verticalRateMps;
  final bool onGround, rotorcraft;
  final List<LatLng> trail;
  const Aircraft({required this.icao24,required this.position,this.callsign,this.country,this.squawk,this.emergency,
    this.altM,this.altFt,this.speedKt,this.trackDeg,this.lastContact,this.verticalRateMps,this.onGround=false,
    this.rotorcraft=false,this.trail=const [],this.category,this.positionTime});

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
      category:(j['category'] is int)?j['category'] as int:null,
      positionTime:(j['position_time'] as num?)?.toDouble()??(j['last_contact'] as num?)?.toDouble(),
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

/// Label on the map: « SAMU75 · 3 100 ft · 100 kt » (feet only on the map,
/// 1 Nov 2026, 7 h 40; metres stay in the sheet).
String aircraftLabel(Aircraft a)=>[
  a.name,
  if(a.onGround)S.t('adsb.onGround')
  else if(a.altFt!=null)'${_grouped(a.altFt!)} ft',
  if(a.speedKt!=null&&!a.onGround)'${a.speedKt} kt',
].join(' · ');

/// Altitude band of an aircraft: the three colours, plus grey (on the
/// ground or altitude unknown).
enum AdsbBand{low,mid,high,ground}

/// Filters of the layer. Lot 17 (1 Nov 2026, 11 h 38): one slider over
/// 0 → ∞ whose two handles are the thresholds between Bas, Moyen and Haut
/// (500 ft steps, 0 to 45 000 ft; 3 000 and 10 000 ft by default), and one
/// switch per band; by default Bas and Moyen shown, Haut hidden (the former
/// 0 → 10 000 ft). Aircraft on the ground and callsigns unchanged (#181).
/// An emergency squawk is always shown; an aircraft without altitude
/// follows Bas.
class AdsbFilters {
  final int lowFt, highFt;
  final bool showLow, showMid, showHigh, ground, labels;
  const AdsbFilters({this.lowFt=3000,this.highFt=10000,this.showLow=true,this.showMid=true,this.showHigh=false,
    this.ground=false,this.labels=false});
  static const stepFt=500, topFt=45000;
  /// « Tout afficher »: the three bands and the aircraft on the ground.
  AdsbFilters get all=>copyWith(showLow:true,showMid:true,showHigh:true,ground:true);
  /// « Valeurs par défaut »: thresholds and bands (callsigns kept).
  AdsbFilters get defaults=>AdsbFilters(labels:labels);
  AdsbFilters copyWith({int? lowFt,int? highFt,bool? showLow,bool? showMid,bool? showHigh,bool? ground,bool? labels})=>AdsbFilters(
    lowFt:lowFt??this.lowFt,highFt:highFt??this.highFt,showLow:showLow??this.showLow,showMid:showMid??this.showMid,
    showHigh:showHigh??this.showHigh,ground:ground??this.ground,labels:labels??this.labels);
  /// Thresholds moved together: kept on the 500 ft steps, low ≤ high.
  AdsbFilters withThresholds(int low,int high){
    int step(int v)=>((v/stepFt).round()*stepFt).clamp(0,topFt);
    final lo=step(low), hi=step(high);
    return copyWith(lowFt:math.min(lo,hi),highFt:math.max(lo,hi));
  }
  bool shown(AdsbBand b)=>switch(b){AdsbBand.low=>showLow,AdsbBand.mid=>showMid,AdsbBand.high=>showHigh,AdsbBand.ground=>ground};
  AdsbFilters withBand(AdsbBand b,bool v)=>switch(b){AdsbBand.low=>copyWith(showLow:v),AdsbBand.mid=>copyWith(showMid:v),
    AdsbBand.high=>copyWith(showHigh:v),AdsbBand.ground=>copyWith(ground:v)};
  /// The upper threshold belongs to the lower band (3 000 ft is Bas).
  AdsbBand bandOf(Aircraft a){
    final f=a.altFt;
    if(a.onGround||f==null)return AdsbBand.ground;
    return f<=lowFt?AdsbBand.low:(f<=highFt?AdsbBand.mid:AdsbBand.high);
  }
  bool shows(Aircraft a){
    if(a.urgent)return true;
    if(a.onGround)return ground;
    if(a.altFt==null)return showLow;
    return shown(bandOf(a));
  }
  /// « 0 – 3 000 ft », « 3 000 – 10 000 ft », « au-delà de 10 000 ft ».
  String rangeOf(AdsbBand b)=>switch(b){
    AdsbBand.low=>'0 – ${_grouped(lowFt)} ft',
    AdsbBand.mid=>'${_grouped(lowFt)} – ${_grouped(highFt)} ft',
    AdsbBand.high=>S.t('adsb.above',{'v':'${_grouped(highFt)} ft'}),
    AdsbBand.ground=>'',
  };
  Map<String,dynamic> toJson()=>{'low_ft':lowFt,'high_ft':highFt,'bands':{'low':showLow,'mid':showMid,'high':showHigh},
    'ground':ground,'labels':labels};
  /// Stored on the device; a value of #181 (range « min » → « max », null =
  /// ∞) is converted: a band is shown if it meets the range.
  static AdsbFilters fromJson(Object? j){
    if(j is! Map)return const AdsbFilters();
    final ground=j['ground']==true, labels=j['labels']==true;
    var f=AdsbFilters(ground:ground,labels:labels);
    final lo=j['low_ft'], hi=j['high_ft'];
    if(lo is int&&hi is int&&lo>=0&&lo<=hi&&hi<=topFt)f=f.copyWith(lowFt:lo,highFt:hi);
    final bands=j['bands'];
    if(bands is Map){
      return f.copyWith(showLow:(bands['low'] is bool)?bands['low'] as bool:null,showMid:(bands['mid'] is bool)?bands['mid'] as bool:null,
        showHigh:(bands['high'] is bool)?bands['high'] as bool:null);
    }
    if(j.containsKey('min')||j.containsKey('max')){
      final min=(j['min'] is int)?(j['min'] as int).clamp(0,topFt):0;
      final max=(j['max'] is int)?(j['max'] as int).clamp(min,topFt):null;
      return f.copyWith(showLow:min<=f.lowFt,showMid:min<=f.highFt&&(max==null||max>f.lowFt),showHigh:max==null||max>f.highFt);
    }
    return f;
  }
  /// Options pushed to a TV with the view (no ADS-B setting of its own).
  Map<String,dynamic> tvJson()=>{'aircraft_low_ft':lowFt,'aircraft_high_ft':highFt,
    'aircraft_bands':{'low':showLow,'mid':showMid,'high':showHigh},'aircraft_ground':ground,'aircraft_labels':labels};
  @override bool operator==(Object other)=>other is AdsbFilters&&other.lowFt==lowFt&&other.highFt==highFt&&other.showLow==showLow
    &&other.showMid==showMid&&other.showHigh==showHigh&&other.ground==ground&&other.labels==labels;
  @override int get hashCode=>Object.hash(lowFt,highFt,showLow,showMid,showHigh,ground,labels);
}

/// Palette shared with the TV page (same values): Bas orange, Moyen blue,
/// Haut grey-blue, ground or unknown grey, emergency red, followed violet.
const adsbLowValue=0xFFF57C00, adsbMidValue=0xFF1565C0, adsbHighValue=0xFF607D8B, adsbGroundValue=0xFF78909C,
  adsbUrgentValue=0xFFD32F2F, adsbFollowValue=0xFF8E24AA;
int adsbBandColorValue(AdsbBand b)=>switch(b){AdsbBand.low=>adsbLowValue,AdsbBand.mid=>adsbMidValue,
  AdsbBand.high=>adsbHighValue,AdsbBand.ground=>adsbGroundValue};

/// Colour by altitude band, readable without labels; emergency in red.
int aircraftColorValue(Aircraft a,[AdsbFilters f=const AdsbFilters()])=>a.urgent?adsbUrgentValue:adsbBandColorValue(f.bandOf(a));

/// Estimated position (1 Nov 2026, 11 h 55): from the OpenSky time of the
/// last position, the speed and the track, as flight tracking sites do,
/// [adsbEstimateMaxS] at most; beyond, the icon turns grey (« position
/// ancienne »). [now] is the server clock (same reference as the TV).
const adsbEstimateMaxS=60;
double? aircraftAgeS(Aircraft a,DateTime now)=>a.positionTime==null?null:now.millisecondsSinceEpoch/1000-a.positionTime!;
bool aircraftStale(Aircraft a,DateTime now){
  final age=aircraftAgeS(a,now);
  return !a.urgent&&age!=null&&age>adsbEstimateMaxS;
}
/// Seconds by which [aircraftEstimated] moves the aircraft forward: 0 when
/// the position is shown as received (on the ground, no speed or track).
double aircraftEstimateS(Aircraft a,DateTime now){
  final kt=a.speedKt;
  if(a.onGround||kt==null||kt<=0||a.trackDeg==null)return 0;
  return (aircraftAgeS(a,now)??0).clamp(0,adsbEstimateMaxS).toDouble();
}
LatLng aircraftEstimated(Aircraft a,DateTime now){
  final age=aircraftEstimateS(a,now);
  if(age<=0)return a.position;
  final m=a.speedKt!*0.514444*age, t=a.trackDeg!*math.pi/180, lat=a.position.latitude;
  return LatLng(lat+m*math.cos(t)/111320,a.position.longitude+m*math.sin(t)/(111320*math.cos(lat*math.pi/180)));
}

/// Diagnostic line of the sheet (lot 18, card « ADS-B : avions de la TV 5 à
/// 10 km plus au sud… », choice 2): age of the OpenSky position by the
/// server clock, and the advance of the estimate when there is one;
/// « Position reçue il y a 42 s · estimée +42 s ». Null without position time.
String? aircraftPositionDiag(Aircraft a,DateTime now){
  final age=aircraftAgeS(a,now);
  if(age==null)return null;
  final received=S.t('adsb.position.received',{'n':'${math.max(0,age.round())}'});
  final ahead=aircraftEstimateS(a,now).round();
  return ahead<1?received:'$received · ${S.t('adsb.position.estimated',{'n':'$ahead'})}';
}

/// Icons by OpenSky category (1 Nov 2026, 12 h 04); many aircraft do not
/// send it (0 or 1): generic aeroplane.
enum AircraftKind{plane,light,airliner,glider,ulm,heli,balloon,drone,parachute}
AircraftKind aircraftKind(Aircraft a)=>switch(a.category){
  2||3=>AircraftKind.light,
  4||5||6=>AircraftKind.airliner,
  8=>AircraftKind.heli,
  9=>AircraftKind.glider,
  10=>AircraftKind.balloon,
  11=>AircraftKind.parachute,
  12=>AircraftKind.ulm,
  14=>AircraftKind.drone,
  _=>a.rotorcraft?AircraftKind.heli:AircraftKind.plane,
};
/// Text of a kind in the legend.
String aircraftKindText(AircraftKind k)=>S.t(k==AircraftKind.heli?'adsb.kind.rotorcraft':'adsb.kind.${k.name}');
/// Type in words in the sheet: « Hélicoptère », « Catégorie non transmise ».
String aircraftTypeText(Aircraft a){
  final c=a.category;
  if(c==null||c<=1)return S.t(a.rotorcraft?'adsb.kind.rotorcraft':'adsb.kind.unknown');
  final k=aircraftKind(a);
  return k==AircraftKind.plane?S.t('adsb.kind.other',{'n':'$c'}):aircraftKindText(k);
}

/// Lists of Outils › ADS-B (1 Nov 2026, 11 h 35): emergencies first, out of
/// the sections; the aircraft followed; one section per band shown (by
/// increasing altitude), empty sections left out; count of the aircraft
/// hidden by the filters.
typedef AdsbSections=({List<Aircraft> urgent,List<Aircraft> followed,Map<AdsbBand,List<Aircraft>> bands,int hidden});
AdsbSections adsbSections(List<Aircraft> all,AdsbFilters f,{Set<String> followed=const {}}){
  final urgent=<Aircraft>[], fol=<Aircraft>[], bands=<AdsbBand,List<Aircraft>>{};
  var hidden=0;
  for(final a in all){
    if(followed.contains(a.icao24))fol.add(a);
    if(a.urgent){urgent.add(a);continue;}
    if(!f.shows(a)){hidden++;continue;}
    (bands[f.bandOf(a)]??=[]).add(a);
  }
  int byAlt(Aircraft x,Aircraft y)=>(x.altFt??-1).compareTo(y.altFt??-1);
  urgent.sort((x,y)=>x.name.compareTo(y.name));
  fol.sort((x,y)=>x.name.compareTo(y.name));
  return (urgent:urgent,followed:fol,
    bands:{for(final b in AdsbBand.values)if(bands[b] case final l?)b:(l..sort(byAlt))},hidden:hidden);
}

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
    if(a.altFt!=null)('adsb.field.altitude','${_grouped(a.altFt!)} ft · ${_grouped(a.altM??(a.altFt!/3.28084).round())} m'),
    ('adsb.field.kind',aircraftTypeText(a)),
    if(a.speedKt!=null)('adsb.field.speed','${a.speedKt} kt · ${(a.speedKt!*1.852).round()} km/h'),
    if(a.trackDeg!=null)('adsb.field.track','${a.trackDeg}°'),
    if(a.verticalRateMps!=null)('adsb.field.vertical','${a.verticalRateMps!>0?'+':''}${(a.verticalRateMps!*196.85).round()} ft/min'),
    if(a.squawk!=null)('adsb.field.squawk',a.urgent?'${a.squawk} · ${emergencyText(a.emergency!)}':a.squawk!),
    if(age!=null)('adsb.field.seen',S.t('adsb.secondsAgo',{'n':'${age<0?0:age}'})),
  ];
}
