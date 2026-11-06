import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/settings/diagnostics_levels.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  setUp(()=>S.setLanguage('fr'));
  test('SIEM not configured: one grey line',(){
    final l=siemLines({'state':'off','tone':null,'waiting':0});
    expect(l.length,1);
    expect(l.first.value,'Non configuré');
    expect(l.first.state,'off');
  });
  test('SIEM cut: orange with the entries waiting, back to zero on return',(){
    final cut=siemLines({'state':'unreachable','tone':'orange','host':'siem.local','port':6514,'tls':true,'format':'ecs',
      'sent':12,'waiting':4,'oldest_waiting_at':'2026-11-06T01:00:00Z','last_error':'ConnectionRefusedError','last_error_at':'2026-11-06T01:20:00Z'});
    expect(cut.first.value,'Injoignable');
    expect(cut.first.state,'orange');
    final waiting=cut.firstWhere((l)=>l.label=='Entrées en attente');
    expect(waiting.value,startsWith('4 depuis'));
    expect(waiting.state,'orange');
    expect(cut.firstWhere((l)=>l.label=='Destination').value,'siem.local:6514 · TLS oui · ecs');
    final back=siemLines({'state':'connected','tone':'green','host':'siem.local','port':6514,'tls':true,'format':'ecs','sent':16,'waiting':0});
    expect(back.firstWhere((l)=>l.label=='Entrées en attente').value,'0');
    expect(back.first.state,'green');
  });
  test('Main courante intact or changed at an entry',(){
    final ok=logbookLine({'ok':true,'chained':42,'before_chaining':3});
    expect(ok.value,'Intègre · 42 entrées chaînées, 3 avant chaînage');
    expect(ok.state,'green');
    final broken=logbookLine({'ok':false,'broken_at':17,'reason':'content'});
    expect(broken.value,'Modifiée à l’entrée n° 17');
    expect(broken.state,'red');
  });
}
