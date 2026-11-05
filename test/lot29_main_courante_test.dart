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
}
