// Android Auto, lot 23 (card « Android Auto : SOS dans la barre du haut,
// opérateurs anciens masqués dans l'onglet Équipe », choice 2): only the
// operators seen within 24 h, else « Personne d'autre en ligne ».
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
}
