import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/weather/weather_models.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

WeatherHour _h(DateTime t,double c,int code)=>WeatherHour(time:t,temperatureC:c,weatherCode:code);

void main(){
  setUp(()=>S.setLanguage('fr'));
  test('short hours, days and the next days',(){
    expect(hourShort(DateTime(2026,11,5,21)),'21 h');
    final now=DateTime(2026,11,5,20);
    expect(dayShort(DateTime(2026,11,5),now),'Aujourd’hui');
    expect(dayShort(DateTime(2026,11,6),now),'Demain');
    expect(dayShort(DateTime(2026,11,12),now),'jeu. 12');
    final hours=[
      _h(DateTime(2026,11,5,21),8,3),_h(DateTime(2026,11,5,22),7,3),
      _h(DateTime(2026,11,6,6),3,0),_h(DateTime(2026,11,6,12),12,61),_h(DateTime(2026,11,6,15),13,61),
      _h(DateTime(2026,11,6,20),9,61),
    ];
    final days=dailySummaries(hours,now);
    expect(days.length,2);
    expect(days[1].min,3); expect(days[1].max,13); expect(days[1].code,61);
  });
}
