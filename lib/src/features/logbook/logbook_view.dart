/// What the Main courante shows (card « Main courante : lisible, filtrable,
/// du plus récent au plus ancien », lot 29.5): kind of each entry, filters,
/// short labels, grouping of consecutive actions and the CSV export. Only
/// the display changes; the server keeps every entry (point 8).
library;

import '../../l10n/strings.dart';
import '../../models/message.dart';

/// Families of the filter row, in its order (« Tout » = null).
enum LogKind { sos, order, message, drawing, link, access, note, other }
/// « Liaisons » (8 Nov 2026): losses and recoveries of contact, apart from Accès.
const logFilters=[LogKind.sos,LogKind.order,LogKind.message,LogKind.drawing,LogKind.link,LogKind.access];

final _sos=RegExp(r'\bSOS\b|détresse|distress',caseSensitive:false);
final _order=RegExp(r'\bordre\b',caseSensitive:false);

LogKind logKind(LogbookEntry e)=>switch(e.kind){
  'message' when _sos.hasMatch(e.summary)=>LogKind.sos,
  'route' when _order.hasMatch(e.summary)=>LogKind.order,
  'message'||'ack'||'message_deleted'||'group'=>LogKind.message,
  'map_feature'||'poi'||'point'||'route'||'geofence'||'drawing'||'bearing'=>LogKind.drawing,
  'contact'=>LogKind.link,
  'access'||'device_version'||'user'||'security'=>LogKind.access,
  'note'=>LogKind.note,
  _=>LogKind.other,
};

String logKindLabel(LogKind k)=>S.t('logbook.kind.${k.name}');

/// « Objet cartographique créé : Cercle » → « Cercle créé ».
String shortSummary(String s){
  final m=RegExp(r'^Objet cartographique (créé|modifié|supprimé)\s*:\s*(.+)$').firstMatch(s.trim());
  return m==null?s.trim():'${m.group(2)} ${m.group(1)}';
}

/// Entries kept by the filter and the search (text, author), newest first.
List<LogbookEntry> logbookShown(List<LogbookEntry> all,{LogKind? filter,String query=''}){
  final q=query.trim().toLowerCase();
  final out=all.where((e)=>(filter==null||logKind(e)==filter)&&
    (q.isEmpty||e.summary.toLowerCase().contains(q)||(e.actorId??'').toLowerCase().contains(q))).toList();
  out.sort((a,b){final c=b.time.compareTo(a.time);return c!=0?c:b.seq.compareTo(a.seq);});
  return out;
}

/// A line of the list: one entry, or several consecutive actions of the
/// same kind by the same operator (SOS, orders and notes never grouped).
class LogLine {
  final List<LogbookEntry> entries;
  const LogLine(this.entries);
  LogbookEntry get first=>entries.first;
  bool get grouped=>entries.length>1;
  LogKind get kind=>logKind(first);
}

/// Gap above which two actions are not grouped.
const logGroupGap=Duration(minutes:10);
/// Liaisons of a terminal come every 20 to 30 minutes: grouped over 3 hours
/// (card « Main courante : page trop longue », 8 Nov 2026, choice 3).
const logLinkGroupGap=Duration(hours:3);
const _neverGrouped={LogKind.sos,LogKind.order,LogKind.note};

final _lost=RegExp(r'^\s*(Perte de contact|Contact lost)',caseSensitive:false);

/// [shown] newest first; groups follow each other in time and day. The last
/// « Perte de contact » of a terminal, not followed by its recovery, stays
/// alone: it still matters.
List<LogLine> logbookLines(List<LogbookEntry> shown){
  final out=<List<LogbookEntry>>[];
  final seenLink=<String?>{};
  for(final e in shown){
    final k=logKind(e);
    var alone=_neverGrouped.contains(k);
    if(k==LogKind.link&&seenLink.add(e.actorId)&&_lost.hasMatch(e.summary))alone=true;
    if(out.isNotEmpty&&!alone){
      final last=out.last; final p=last.last;
      final pl=p.time.toLocal(), el=e.time.toLocal();
      final gap=k==LogKind.link?logLinkGroupGap:logGroupGap;
      final pAlone=last.length==1&&k==LogKind.link&&_lost.hasMatch(p.summary)&&identical(p,_firstLinkOf(shown,p.actorId));
      if(!pAlone&&logKind(p)==k&&p.actorId==e.actorId&&p.time.difference(e.time)<=gap&&pl.day==el.day&&pl.month==el.month){last.add(e);continue;}
    }
    out.add([e]);
  }
  return [for(final l in out)LogLine(l)];
}

LogbookEntry? _firstLinkOf(List<LogbookEntry> shown,String? actor){
  for(final e in shown){if(logKind(e)==LogKind.link&&e.actorId==actor)return e;}
  return null;
}

/// Days shown before « Afficher les semaines précédentes » (choice 2).
const logPeriodDays=7;

/// Section of an entry: its day within [logPeriodDays] of today, else the
/// week (Monday) — « 2026-11-08 », « w2026-10-26 ».
String logSectionKey(DateTime t,DateTime now){
  final l=t.toLocal(), n=now.toLocal();
  final day=DateTime(l.year,l.month,l.day), today=DateTime(n.year,n.month,n.day);
  String d(DateTime x)=>'${x.year}-${_two(x.month)}-${_two(x.day)}';
  if(today.difference(day).inDays<logPeriodDays)return d(day);
  return 'w${d(day.subtract(Duration(days:day.weekday-1)))}';
}

/// « Aujourd’hui · 8 novembre », « Hier · 7 novembre », « 3 novembre »,
/// « Semaine du 26 octobre ».
String logSectionLabel(String key,DateTime now){
  if(key.startsWith('w')){
    final p=key.substring(1).split('-').map(int.parse).toList();
    final y=p[0]!=now.toLocal().year?' ${p[0]}':'';
    return S.t('logbook.week',{'d':'${p[2]} ${S.t('month.${p[1]}')}$y'});
  }
  final p=key.split('-').map(int.parse).toList();
  return logDayLabel(DateTime(p[0],p[1],p[2],12),now);
}

/// Entries within the period shown: [days] days back from today.
bool inLogPeriod(DateTime t,DateTime now,int days){
  final l=t.toLocal(), n=now.toLocal();
  final day=DateTime(l.year,l.month,l.day), today=DateTime(n.year,n.month,n.day);
  return today.difference(day).inDays<days;
}

/// « 4 créés, 1 supprimé » from the summaries of a group.
String groupDetail(List<LogbookEntry> entries){
  final n=<String,int>{};
  for(final e in entries){
    final m=RegExp(r'\b(créé|modifié|supprimé)').firstMatch(e.summary);
    final v=m?.group(1)??'other';
    n[v]=(n[v]??0)+1;
  }
  final parts=[for(final v in const ['créé','modifié','supprimé'])if((n[v]??0)>0)'${n[v]} $v${n[v]!>1?'s':''}'];
  if((n['other']??0)>0)parts.add(S.t('logbook.entries',{'n':n['other']}));
  return parts.join(', ');
}

String _two(int v)=>v.toString().padLeft(2,'0');
String logHm(DateTime t){final l=t.toLocal();return '${_two(l.hour)}:${_two(l.minute)}';}
String logHms(DateTime t){final l=t.toLocal();return '${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';}

/// Day header: « Aujourd'hui · 5 novembre », « Hier · 4 novembre », « 23 octobre ».
String logDayLabel(DateTime t,DateTime now){
  final l=t.toLocal(), n=now.toLocal();
  final day=DateTime(l.year,l.month,l.day), today=DateTime(n.year,n.month,n.day);
  final name='${l.day} ${S.t('month.${l.month}')}${l.year!=n.year?' ${l.year}':''}';
  if(day==today)return '${S.t('logbook.today')} · $name';
  if(day==today.subtract(const Duration(days:1)))return '${S.t('logbook.yesterday')} · $name';
  return name;
}

bool sameLogDay(DateTime a,DateTime b){final x=a.toLocal(),y=b.toLocal();return x.year==y.year&&x.month==y.month&&x.day==y.day;}

final _coords=RegExp(r'\((-?\d{1,2}\.\d+),\s*(-?\d{1,3}\.\d+)\)');

/// CSV for Excel in French: « ; », UTF-8 with its mark, one line per entry
/// (date and time to the second, type, operator, text, latitude,
/// longitude, identifier). The position is read from the text when given.
/// Columns of the common event format (card « format d'événement commun »,
/// lot 29, group 8, choice 4): the same, in the same order, as the JSON sent
/// to the SIEM and the export of the server; the fingerprint of each row.
const logbookCsvColumns=['event.id','@timestamp','event.dataset','event.action','user.id','host.id','sarcade.event_id',
  'geo.location.lat','geo.location.lon','event.outcome','message','event.hash'];

/// « 2026-11-05T21:17:04.123Z »: UTC to the millisecond.
String ecsTimestamp(DateTime t){
  final u=t.toUtc();
  String p(int v,[int n=2])=>v.toString().padLeft(n,'0');
  return '${p(u.year,4)}-${p(u.month)}-${p(u.day)}T${p(u.hour)}:${p(u.minute)}:${p(u.second)}.${p(u.millisecond,3)}Z';
}

String logbookCsv(List<LogbookEntry> entries,{required String eventId}){
  String cell(String v)=>v.contains(RegExp(r'[;"\n\r]'))?'"${v.replaceAll('"','""')}"':v;
  final b=StringBuffer('\ufeff')..write('${logbookCsvColumns.join(';')}\r\n');
  for(final e in entries){
    final m=_coords.firstMatch(e.summary);
    final lat=m==null?null:double.tryParse(m.group(1)!), lon=m==null?null:double.tryParse(m.group(2)!);
    b.write('${[
      'log-${e.seq}',ecsTimestamp(e.time),'sarcade.logbook',e.kind,e.actorId??'','',eventId,
      lat?.toString()??'',lon?.toString()??'','unknown',e.summary,e.hash??'',
    ].map(cell).join(';')}\r\n');
  }
  return b.toString();
}
