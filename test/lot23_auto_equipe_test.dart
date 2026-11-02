// Android Auto, lot 23, Équipe tab:
// - card « Android Auto : SOS dans la barre du haut, opérateurs anciens
//   masqués dans l'onglet Équipe », choice 2: only the operators seen
//   within 24 h, else « Personne d'autre en ligne »;
// - card « Android Auto, onglet Équipe : naviguer vers un opérateur »: last
//   known position sent to the car, its age rounded, « position de 20 h 05 »
//   beyond 15 min.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/position.dart';

final now=DateTime.utc(2026,11,2,20,30);
const here=LatLng(48.80,1.95);

SarcadePosition pos(String device,Duration age,{double lat=48.81})=>SarcadePosition(id:'p-$device',eventId:'e',deviceId:device,
  lat:lat,lon:1.95,time:now.subtract(age));

List<Map<String,Object?>> team(List<SarcadePosition> positions)=>carTeam(
  CarScreenInput(me:'TEL-1',eventId:'e',now:now,here:here,positions:positions));

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>S.setLanguage('fr'));

  test('Équipe: operators seen more than 24 h ago are not shown',(){
    final t=team([
      pos('PC-demo',const Duration(days:8)),
      pos('PCO-Web',const Duration(hours:42)),
      pos('PCO',const Duration(days:2)),
      pos('TEL-2',const Duration(hours:23,minutes:59)),
      pos('TEL-3',const Duration(minutes:3),lat:48.82),
    ]);
    expect(t.map((x)=>x['id']),['TEL-2','TEL-3']);
  });

  test('Équipe: exactly 24 h is too old',(){
    expect(team([pos('TEL-2',carTeamMaxAge)]),isEmpty);
  });

  test('Équipe empty: « Personne d’autre en ligne »',(){
    expect(team([pos('PCO',const Duration(days:2))]),isEmpty);
    expect(carLabels()['empty.team'],'Personne d’autre en ligne');
    S.setLanguage('en');
    expect(carLabels()['empty.team'],'Nobody else online');
  });

  test('Équipe: last known position sent, for « Naviguer »',(){
    final t=team([pos('TEL-2',const Duration(minutes:3),lat:48.83)]).single;
    expect(t['lat'],48.83); expect(t['lon'],1.95);
  });

  test('Équipe: age by 5 min up to 15 min, then the time of the position',(){
    String seen(Duration age)=>carSeen(now.subtract(age),now);
    expect(seen(Duration.zero),'vu il y a moins de 5 min');
    expect(seen(const Duration(minutes:4,seconds:59)),'vu il y a moins de 5 min');
    expect(seen(const Duration(minutes:5)),'vu il y a 5\u00A0min');
    expect(seen(const Duration(minutes:9,seconds:30)),'vu il y a 5\u00A0min');
    expect(seen(const Duration(minutes:14)),'vu il y a 10\u00A0min');
    expect(seen(const Duration(minutes:15)),'vu il y a 15\u00A0min');
    final old=now.subtract(const Duration(minutes:25)).toLocal();
    final hm='${old.hour} h ${old.minute.toString().padLeft(2,'0')}';
    expect(seen(const Duration(minutes:25)),'position de $hm');
    S.setLanguage('en');
    expect(seen(const Duration(minutes:25)),'position at ${old.hour}:${old.minute.toString().padLeft(2,'0')}');
    expect(seen(const Duration(minutes:2)),'seen less than 5 min ago');
  });

  test('Équipe: the text does not change with every write (lot 20 rule)',(){
    // Same operator, written 40 s apart: same line, the car does not redraw.
    final a=carTeam(CarScreenInput(me:'TEL-1',eventId:'e',now:now,here:here,positions:[pos('TEL-2',const Duration(minutes:6))]));
    final b=carTeam(CarScreenInput(me:'TEL-1',eventId:'e',now:now.add(const Duration(seconds:40)),here:here,positions:[pos('TEL-2',const Duration(minutes:6))]));
    expect(a.single['text'],b.single['text']);
    final c=carTeam(CarScreenInput(me:'TEL-1',eventId:'e',now:now.add(const Duration(minutes:30)),here:here,positions:[pos('TEL-2',const Duration(minutes:6))]));
    final d=carTeam(CarScreenInput(me:'TEL-1',eventId:'e',now:now.add(const Duration(minutes:50)),here:here,positions:[pos('TEL-2',const Duration(minutes:6))]));
    expect(c.single['text'],d.single['text']);
  });
}
