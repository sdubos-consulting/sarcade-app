import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/weather/rain_radar.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';

final _json={'state':'ok','source':'Météo-France','stale':false,'error':null,
  'frames':[{'id':'202611060110','time':'2026-11-06T01:10:00Z'},{'id':'202611060115','time':'2026-11-06T01:15:00Z'}],
  'legend':[{'min':0.1,'max':1.0,'color':'#9BD7FF'},{'min':64.0,'max':null,'color':'#C81EC8'}]};

void main(){
  setUp(()=>S.setLanguage('fr'));
  test('state read from the server, last image first in line',(){
    final s=RadarState.fromJson(_json);
    expect(s.latest!.id,'202611060115');
    expect(s.legend.first.color,const Color(0xFF9BD7FF));
    expect(radarClassLabel(s.legend.first),'0,1');
    expect(radarClassLabel(s.legend.last),'64+');
  });
  test('an image older than 20 minutes is « ancienne »',(){
    final s=RadarState.fromJson(_json);
    expect(s.staleAt(DateTime.utc(2026,11,6,1,30)),isFalse);
    expect(s.staleAt(DateTime.utc(2026,11,6,1,40)),isTrue);
    expect(RadarState.fromJson({..._json,'stale':true}).staleAt(DateTime.utc(2026,11,6,1,16)),isTrue);
  });
  test('tiles of the SARCADE server, never of Météo-France',(){
    expect(radarTileUrl('https://app.sarcade.org/','202611060115'),'https://app.sarcade.org/api/v0.1/weather/radar/202611060115/{z}/{x}/{y}.png');
  });
  test('no layer while hidden or before a first image',(){
    final r=RainRadar(SarcadeApi(baseUrl:'https://x.test'));
    expect(rainRadarLayer(r,server:'https://x.test',opacity:1),isNull);
    r.state=RadarState.fromJson(_json);
    expect(rainRadarLayer(r,server:'https://x.test',opacity:1),isNull);
  });
  testWidgets('time of the image, legend and source under the switch',(t) async {
    final r=RainRadar(SarcadeApi(baseUrl:'https://x.test'))..state=RadarState.fromJson({..._json,'stale':true});
    await t.pumpWidget(MaterialApp(home:Scaffold(body:RainRadarDetail(radar:r))));
    expect(find.textContaining('Image ancienne de'),findsOneWidget);
    expect(find.text('Source : Météo-France'),findsOneWidget);
    expect(find.text('mm/h'),findsOneWidget);
    r.apply(const RadarState(state:'no_key'));
    await t.pump();
    expect(find.text('Radar non réglé sur le serveur (clé Météo-France)'),findsOneWidget);
  });
}
