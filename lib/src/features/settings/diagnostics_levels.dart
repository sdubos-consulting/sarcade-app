/// Paramètres › Diagnostic in three levels (lot 28, card « Diagnostic :
/// trois niveaux de vue selon les droits, et test de Brevo », decided on
/// 4 Nov 2026, 7 h 19): the server computes the level from the rights of
/// lot 26 and sends only what it allows; the application shows what it
/// received. Also the « Échéances » of the administrator (card « Diagnostic
/// administrateur : Échéances », 7 h 26) and the versions of the
/// application and of the server (card « Consolidation : version de
/// référence et versions déployées »). Pure functions, tested.
library;

import 'package:flutter/material.dart';

import '../../config/version.dart';
import '../../l10n/strings.dart';

typedef DiagLevelLine=({String block,String label,String value,String? state});

/// `user`, `organizer`, `admin`, `transition` (device without account
/// during the transition: the view of before), or `legacy` (server older
/// than lot 28, or not reached: the view of before).
String diagLevel(Map<String,dynamic>? server){
  final l='${server?['level']??''}';
  return const ['user','organizer','admin','transition'].contains(l)?l:'legacy';
}

/// The view of before (all lines of the device and of the links).
bool diagFullView(String level)=>level=='admin'||level=='transition'||level=='legacy';

/// Services of the event (APRS, MeshCore, aircraft, itineraries): PCO and up.
bool diagShowsServices(String level)=>level!='user';

/// Bright red of an expired deadline.
const expiredRed=Color(0xFFFF1744);

String _two(int v)=>v.toString().padLeft(2,'0');

/// « 23/11/2027 ».
String diagDay(Object? iso){
  final t=DateTime.tryParse('${iso??''}');
  if(t==null)return '—';
  final l=t.isUtc?t.toLocal():t;
  return '${_two(l.day)}/${_two(l.month)}/${l.year}';
}

/// « 23/11 14:05 ».
String diagWhen(Object? iso){
  final t=DateTime.tryParse('${iso??''}')?.toLocal();
  if(t==null)return '—';
  return '${_two(t.day)}/${_two(t.month)} ${_two(t.hour)}:${_two(t.minute)}';
}

/// Line « Serveur » of a user when the server is down: the problem in
/// clear words and what to do.
DiagLevelLine? serverDownLine(String block,Map<String,dynamic>? server){
  if(server==null||server['status']!='down')return null;
  return (block:block,label:S.t('diag.server'),value:S.t('diag.serverDown'),state:'red');
}

/// Block « Services de l'événement » of the PCO: APRS, weather,
/// notifications, itineraries and devices connected.
List<DiagLevelLine> eventServiceLines(Map<String,dynamic> d){
  final block=S.t('diag.eventServices');
  final s=Map<String,dynamic>.from(d['services'] as Map? ?? const {});
  DiagLevelLine line(String label,String key)=>(block:block,label:label,value:S.t('diag.c.${s[key]??'off'}'),state:'${s[key]??'off'}');
  return [
    line(S.t('diag.comp.aprs'),'aprs'),
    line(S.t('diag.comp.weather'),'weather'),
    line(S.t('diag.notificationsService'),'wakeup'),
    line(S.t('diag.routing'),'routes'),
    (block:block,label:S.t('diag.devicesConnected'),value:'${d['devices_connected']??'—'}',state:null),
  ];
}

/// « sha256:1a2b3c4d5e6f… »: enough to compare by eye.
String shortDigest(Object? v){
  final s='${v??''}';
  if(s.isEmpty||s=='null')return '—';
  final hex=s.startsWith('sha256:')?s.substring(7):s;
  return hex.length<=12?'sha256:$hex':'sha256:${hex.substring(0,12)}…';
}

/// Lines added to the block « Serveur » of the administrator: addresses,
/// commit, digests of the web client and of the SBOM.
List<DiagLevelLine> adminBuildLines(Map<String,dynamic> d){
  final block=S.t('diag.server');
  final b=Map<String,dynamic>.from(d['build'] as Map? ?? const {});
  final addresses=[for(final a in (d['addresses'] as List?)??const [])'$a'];
  return [
    (block:block,label:S.t('diag.addresses'),value:addresses.isEmpty?'—':addresses.join(', '),state:null),
    (block:block,label:S.t('version.commit'),value:'${b['commit_short']??'—'}',state:null),
    (block:block,label:S.t('version.web'),value:shortDigest(b['web_sha256']),state:null),
    (block:block,label:S.t('version.sbom'),value:shortDigest(b['sbom_sha256']),state:null),
  ];
}

/// Block « Envoi des e-mails (Brevo) » of the administrator.
List<DiagLevelLine> mailLines(Map<String,dynamic> m){
  final block=S.t('diag.mail');
  final smtp=m['delivery']=='smtp';
  final probe=m['probe'] is Map?Map<String,dynamic>.from(m['probe'] as Map):null;
  final ok=DateTime.tryParse('${m['last_success_at']??''}'), fail=DateTime.tryParse('${m['last_failure_at']??''}');
  final failLast=fail!=null&&(ok==null||fail.isAfter(ok));
  return [
    (block:block,label:S.t('diag.mailConfig'),
      value:smtp?S.t('admin.mailSmtp',{'host':'${m['host']??''}:${m['port']??''}','from':m['sender']??''}):S.t('diag.mailSimulated'),
      state:smtp?'green':'orange'),
    (block:block,label:S.t('diag.mailProbe'),
      value:probe==null?'—':probe['ok']==true?S.t('diag.mailProbeOk'):'${probe['error']??S.t('diag.unknown')}',
      state:probe==null?'off':probe['ok']==true?'green':'red'),
    (block:block,label:S.t('diag.mailLastOk'),value:ok==null?S.t('diag.never'):diagWhen(ok.toIso8601String()),state:null),
    (block:block,label:S.t('diag.mailLastFail'),
      value:fail==null?S.t('diag.noFailure'):'${diagWhen(fail.toIso8601String())} · ${m['last_failure']??''}',
      state:failLast?'red':null),
  ];
}

/// « 23/11/2027 · dans 19 j », « Aujourd'hui », « Expirée le … », « Date à saisir ».
String deadlineValue(Map<String,dynamic> item){
  final left=(item['days_left'] as num?)?.toInt();
  final day=diagDay(item['date']);
  if(left==null)return S.t('deadline.noDate');
  if(left<0)return S.t('deadline.expired',{'date':day,'n':-left});
  if(left==0)return S.t('deadline.today',{'date':day});
  return S.t('deadline.left',{'date':day,'n':left});
}

/// green, orange, red, expired; null (grey) without date.
String? deadlineState(Map<String,dynamic> item){
  final l='${item['level']??''}';
  return const ['green','orange','red','expired'].contains(l)?l:null;
}

List<Map<String,dynamic>> deadlineItems(Map<String,dynamic>? deadlines)=>
  [for(final x in (deadlines?['items'] as List?)??const [])if(x is Map)Map<String,dynamic>.from(x)];

/// Block « Échéances » of the administrator, most urgent first.
List<DiagLevelLine> deadlineLines(Map<String,dynamic>? deadlines){
  final block=S.t('deadline.title');
  return [for(final i in deadlineItems(deadlines))(block:block,label:'${i['name']??''}',value:deadlineValue(i),state:deadlineState(i))];
}

/// Items of the banner: orange, red or expired.
List<Map<String,dynamic>> deadlineAlerts(Map<String,dynamic>? deadlines)=>
  [for(final i in deadlineItems(deadlines))if(const ['orange','red','expired'].contains(i['level']))i];

// --- Versions -----------------------------------------------------------------------

bool _isLabel(String? r)=>r!=null&&RegExp(r'^v\d').hasMatch(r);

/// `same`, `different`, `none` (no label on either side: development
/// builds), `unknown` (server older than lot 28).
String referenceMatch(String app,String? server){
  if(server==null||server.isEmpty)return 'unknown';
  if(!_isLabel(app)&&!_isLabel(server))return 'none';
  return app==server?'same':'different';
}

/// « Version du serveur » and « Version de référence », with a warning
/// when the application and the server do not come from the same
/// reference version.
List<DiagLevelLine> versionLines(String block,Map<String,dynamic>? server,{String? app}){
  final mine=app??appReference();
  final ref=server?['reference'] as String?;
  final match=referenceMatch(mine,ref);
  return [
    if(server!=null)(block:block,label:S.t('version.server'),
      value:[if(server['version']!=null)'${server['version']}',?ref].join(' · '),state:null),
    (block:block,label:S.t('version.reference'),value:switch(match){
        'same'=>S.t('version.same',{'ref':mine}),
        'different'=>S.t('version.different',{'app':mine,'server':ref}),
        'none'=>S.t('version.none',{'app':mine,'server':ref}),
        _=>S.t('version.app',{'app':mine}),
      },state:switch(match){'same'=>'green','different'=>'orange',_=>null}),
  ];
}

/// Section « SIEM » of the administrator (card « Diagnostic : ligne SIEM »,
/// lot 29, group 8): state, destination, entries sent and waiting, last
/// error. Orange when entries wait for more than 15 min, red after 24 h
/// (the colour computed by the server).
List<DiagLevelLine> siemLines(Map<String,dynamic> m){
  final block=S.t('diag.siem');
  final st='${m['state']??'off'}';
  final tone=m['tone'] as String?;
  final waiting=(m['waiting'] as num?)?.toInt()??0;
  final dest=m['host']!=null
    ?S.t('diag.siemDest',{'host':'${m['host']}:${m['port']??''}','tls':S.t(m['tls']==true?'diag.siemTlsOn':'diag.siemTlsOff'),'format':'${m['format']??''}'})
    :m['file']==true?S.t('diag.siemFile',{'format':'${m['format']??''}'}):'—';
  return [
    (block:block,label:S.t('diag.siemState'),value:S.t('diag.siemState.$st'),state:st=='off'?'off':tone??(st=='connected'?'green':'orange')),
    if(st!='off')...[
      (block:block,label:S.t('diag.siemDestination'),value:dest,state:null),
      (block:block,label:S.t('diag.siemSent'),value:'${m['sent']??0}',state:null),
      (block:block,label:S.t('diag.siemWaiting'),
        value:waiting==0?'0':S.t('diag.siemWaitingSince',{'n':waiting,'when':diagWhen(m['oldest_waiting_at'])}),
        state:waiting==0?'green':tone),
      (block:block,label:S.t('diag.siemLastError'),
        value:m['last_error']==null?S.t('diag.noFailure'):'${diagWhen(m['last_error_at'])} · ${m['last_error']}',
        state:st=='unreachable'?'orange':null),
    ],
  ];
}

/// « Main courante intègre », or the entry where it breaks (card « Main
/// courante infalsifiable », lot 29, group 8).
DiagLevelLine logbookLine(Map<String,dynamic> v){
  final block=S.t('diag.logbook');
  if(v['ok']==true){
    return (block:block,label:S.t('diag.logbookChain'),
      value:S.t('diag.logbookOk',{'n':(v['chained'] as num?)?.toInt()??0,'before':(v['before_chaining'] as num?)?.toInt()??0}),state:'green');
  }
  return (block:block,label:S.t('diag.logbookChain'),value:S.t('diag.logbookBroken',{'seq':'${v['broken_at']??'?'}'}),state:'red');
}

/// Lines « Météo-France », « Prévisions (Open-Meteo) » and « Appels météo du
/// jour » added to the block « Serveur » of the administrator (card « Météo :
/// limiter les appels à Météo-France », choices 4 and 5, 10 Nov 2026), when
/// the server sends `weather_sources`; nothing with an older server.
List<DiagLevelLine> weatherSourceLines(Map<String,dynamic> d){
  if(d['weather_sources'] is! Map)return const [];
  final w=Map<String,dynamic>.from(d['weather_sources'] as Map);
  final src=Map<String,dynamic>.from(w['sources'] as Map? ?? const {});
  Map<String,dynamic> of(String k)=>Map<String,dynamic>.from(src[k] as Map? ?? const {});
  String clock(Object? iso){final t=DateTime.tryParse('${iso??''}')?.toLocal();return t==null?'—':'${_two(t.hour)}:${_two(t.minute)}';}
  String text(String k){
    final s=of(k);
    var st='${s['state']??'idle'}';
    // Card « Météo-France : vigilance refusée (clé non abonnée) », 11 Nov
    // 2026, choice 4: say which API to subscribe on the portal.
    if(st=='refused'&&s['refused_reason']=='not_subscribed'&&k!='forecast')st='not_subscribed';
    return S.t('diag.mf.$k.${const ['ok','idle','refused','not_subscribed','rate_limited','error'].contains(st)?st:'idle'}',
      {'at':clock(s['paused_until']),'e':'${s['last_error']??''}'});
  }
  String? tone(List<String> keys){
    final states=[for(final k in keys)'${of(k)['state']??'idle'}'];
    if(states.contains('refused'))return 'red';
    if(states.contains('rate_limited')||states.contains('error'))return 'orange';
    return states.contains('ok')?'green':null;
  }
  final block=S.t('diag.server');
  final calls=[for(final k in const ['radar','vigilance'])DateTime.tryParse('${of(k)['last_call_at']??''}')].whereType<DateTime>().toList()..sort();
  final key=w['key']!=false;
  int n(String k)=>(of(k)['calls_today'] as num?)?.toInt()??0;
  return [
    (block:block,label:S.t('diag.meteoFrance'),
      value:!key?S.t('diag.mf.noKey'):[text('radar'),text('vigilance'),if(calls.isNotEmpty)S.t('diag.mf.lastCall',{'at':clock(calls.last.toIso8601String())})].join(', '),
      state:!key?'off':tone(const ['radar','vigilance'])),
    (block:block,label:S.t('diag.forecastSource'),value:text('forecast'),state:tone(const ['forecast'])),
    (block:block,label:S.t('diag.weatherCalls'),
      value:S.t('diag.weatherCallsValue',{'r':n('radar'),'v':n('vigilance'),'f':n('forecast'),'n':(w['active_events'] as num?)?.toInt()??0}),state:null),
  ];
}
