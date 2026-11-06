import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/ui/car_mode.dart';

void main(){
  test('Tesla browser is a car screen',(){
    expect(teslaUserAgent('Mozilla/5.0 (X11; GNU/Linux) AppleWebKit/537.36 (KHTML, like Gecko) Chromium/108 Chrome/108 Safari/537.36 Tesla/2024.20'),isTrue);
    expect(teslaUserAgent('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)'),isFalse);
  });
  test('round map buttons: 44 px, 56 px on a car screen',(){
    expect(mapButtonSize(car:false),44);
    expect(mapButtonSize(car:true),56);
    carModeOverride=true; expect(mapButtonSize(),56);
    carModeOverride=false; expect(mapButtonSize(),44);
    carModeOverride=null;
  });
}
