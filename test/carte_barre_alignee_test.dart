import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/link_weather_pill.dart';

void main(){
  // 9 Nov 2026, capture iPhone: pencil, search and pill aligned top and
  // bottom; on the map the pill takes the height of the pencil.
  testWidgets('the pill takes the height it is given',(tester) async {
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Align(alignment:Alignment.topLeft,
      child:LinkWeatherPill(dot:Colors.green,linkTooltip:'Liaison',onLinks:(){},onWeather:(){},height:44)))));
    expect(tester.getSize(find.byType(LinkWeatherPill)).height,44);
  });
  testWidgets('without a height, the usual 48 px touch area',(tester) async {
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Align(alignment:Alignment.topLeft,
      child:LinkWeatherPill(dot:Colors.green,linkTooltip:'Liaison',onLinks:(){},onWeather:(){})))));
    expect(tester.getSize(find.byType(LinkWeatherPill)).height,pillTouch);
  });
}
