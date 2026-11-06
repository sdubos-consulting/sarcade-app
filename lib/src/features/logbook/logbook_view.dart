/// What the Main courante shows (card « Main courante : lisible, filtrable,
/// du plus récent au plus ancien », lot 29.5): kind of each entry, filters,
/// short labels, grouping of consecutive actions and the CSV export. Only
/// the display changes; the server keeps every entry (point 8).
library;

import '../../l10n/strings.dart';
import '../../models/message.dart';

/// Families of the filter row, in its order (« Tout » = null).
enum LogKind { sos, order, message, drawing, access, note, other }
const logFilters=[LogKind.sos,LogKind.order,LogKind.message,LogKind.drawing,LogKind.access];

final _sos=RegExp(r'\bSOS\b|détresse|distress',caseSensitive:false);
final _order=RegExp(r'\bordre\b',caseSensitive:false);

LogKind logKind(LogbookEntry e)=>switch(e.kind){
  'message' when _sos.hasMatch(e.summary)=>LogKind.sos,
  'route' when _order.hasMatch(e.summary)=>LogKind.order,
  'message'||'ack'||'message_deleted'||'group'=>LogKind.message,
  'map_feature'||'poi'||'point'||'route'||'geofence'||'drawing'||'bearing'=>LogKind.drawing,
  'access'||'contact'||'device_version'||'user'||'security'=>LogKind.access,
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
const _neverGrouped={LogKind.sos,LogKind.order,LogKind.note};

/// [shown] newest first; groups follow each other in time and day.
List<LogLine> logbookLines(List<LogbookEntry> shown){
  final out=<List<LogbookEntry>>[];
  for(final e in shown){
    final k=logKind(e);
    if(out.isNotEmpty&&!_neverGrouped.contains(k)){
      final last=out.last; final p=last.last;
      final pl=p.time.toLocal(), el=e.time.toLocal();
      if(logKind(p)==k&&p.actorId==e.actorId&&p.time.difference(e.time)<=logGroupGap&&pl.day==el.day&&pl.month==el.month){last.add(e);continue;}
    }
    out.add([e]);
  }
  return [for(final l in out)LogLine(l)];
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
String logbookCsv(List<LogbookEntry> entries){
  String cell(String v)=>v.contains(RegExp(r'[;"\n\r]'))?'"${v.replaceAll('"','""')}"':v;
  final b=StringBuffer('﻿')..writeln(['date','heure','type','operateur','texte','latitude','longitude','identifiant'].join(';'));
  for(final e in entries){
    final l=e.time.toLocal(); final m=_coords.firstMatch(e.summary);
    b.writeln([
      '${l.year}-${_two(l.month)}-${_two(l.day)}',logHms(e.time),logKindLabel(logKind(e)),e.actorId??'',e.summary,
      m?.group(1)??'',m?.group(2)??'',e.objectId??'${e.seq}',
    ].map(cell).join(';'));
  }
  return b.toString();
}
