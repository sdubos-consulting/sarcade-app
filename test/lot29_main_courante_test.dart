import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/logbook/logbook_view.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/message.dart';

LogbookEntry _e(int seq,String kind,String summary,DateTime t,{String actor='device-demo'})=>
  LogbookEntry(seq:seq,kind:kind,summary:summary,time:t,actorId:actor);

void main(){
  setUp(()=>S.setLanguage('fr'));
  final t0=DateTime(2026,11,5,21,17);
  final all=[
    _e(1,'map_feature','Objet cartographique créé : Cercle',t0),
    _e(2,'map_feature','Objet cartographique créé : Zone',t0.add(const Duration(minutes:1))),
    _e(3,'map_feature','Objet cartographique supprimé : Zone',t0.add(const Duration(minutes:3))),
    _e(4,'message','🆘 SOS de TEL-01 (48.80000, 2.13000)',t0.add(const Duration(minutes:4)),actor:'TEL-01'),
    _e(5,'route','📍 Ordre de déplacement : rejoindre « PC »',t0.add(const Duration(minutes:5)),actor:'PCO'),
    _e(6,'access','Accès accordé',DateTime(2026,10,23,9)),
  ];
  test('newest first, kinds and filters',(){
    final shown=logbookShown(all);
    expect(shown.first.seq,5); expect(shown.last.seq,6);
    expect(logKind(all[3]),LogKind.sos); expect(logKind(all[4]),LogKind.order);
    expect(logbookShown(all,filter:LogKind.sos).map((e)=>e.seq),[4]);
    expect(logbookShown(all,query:'tel-01').map((e)=>e.seq),[4]);
  });
  test('short labels and groups (SOS and orders never grouped)',(){
    expect(shortSummary('Objet cartographique créé : Cercle'),'Cercle créé');
    final lines=logbookLines(logbookShown(all));
    expect(lines.map((l)=>l.entries.length),[1,1,3,1]);
    expect(groupDetail(lines[2].entries),'2 créés, 1 supprimé');
  });
  test('day headers',(){
    expect(logDayLabel(t0,DateTime(2026,11,5,23)),'Aujourd’hui · 5 novembre');
    expect(logDayLabel(DateTime(2026,10,23,9),DateTime(2026,11,5)),'23 octobre');
  });
  test('CSV in the common event format, same columns as the server',(){
    final csv=logbookCsv([all[3]],eventId:'e1');
    expect(csv.startsWith('\ufeffevent.id;@timestamp;event.dataset;event.action;user.id;host.id;sarcade.event_id;geo.location.lat;geo.location.lon;event.outcome;message;event.hash\r\n'),isTrue);
    expect(csv,contains(';sarcade.logbook;'));
    expect(csv,contains(';TEL-01;;e1;48.8;2.13;unknown;'));
    expect(ecsTimestamp(DateTime.utc(2026,11,5,21,17,4,123,456)),'2026-11-05T21:17:04.123Z');
  });

  // Card « Main courante : page trop longue », 8 Nov 2026.
  test('liaisons: own filter, grouped over 3 hours, the last unrecovered loss alone',(){
    final d=DateTime(2026,11,8);
    final link=[
      _e(10,'contact','Contact rétabli (après 28 min)',d.add(const Duration(hours:22,minutes:9))),
      _e(11,'contact','Contact rétabli (après 24 min)',d.add(const Duration(hours:22,minutes:21))),
      _e(12,'contact','Perte de contact',d.add(const Duration(hours:22,minutes:27))),
      _e(13,'contact','Contact rétabli (après 30 min)',d.add(const Duration(hours:22,minutes:51))),
      _e(14,'contact','Perte de contact',d.add(const Duration(hours:22,minutes:57))),
      _e(15,'note','Test',d.add(const Duration(hours:23,minutes:4)),actor:'PCO'),
    ];
    expect(logKind(link[0]),LogKind.link);
    expect(logbookShown(link,filter:LogKind.link).length,5);
    final lines=logbookLines(logbookShown(link));
    // Note, the last loss (22:57) alone, then the four others grouped.
    expect(lines.map((l)=>l.entries.map((e)=>e.seq).toList()),[[15],[14],[13,12,11,10]]);
  });
  test('sections: days within 7 days, then weeks; period',(){
    final now=DateTime(2026,11,8,23);
    expect(logSectionKey(DateTime(2026,11,8,9),now),'2026-11-08');
    expect(logSectionKey(DateTime(2026,11,2,9),now),'2026-11-02');
    expect(logSectionKey(DateTime(2026,10,28,9),now),'w2026-10-26');
    expect(logSectionLabel('2026-11-08',now),'Aujourd’hui · 8 novembre');
    expect(logSectionLabel('w2026-10-26',now),'Semaine du 26 octobre');
    expect(inLogPeriod(DateTime(2026,11,2,9),now,7),isTrue);
    expect(inLogPeriod(DateTime(2026,11,1,9),now,7),isFalse);
    expect(inLogPeriod(DateTime(2026,11,1,9),now,14),isTrue);
  });
}
