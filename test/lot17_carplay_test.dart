// CarPlay, lot 17 step 2b: same channel as Android Auto, opened on iPhone
// too (CarPlay inactive until Apple grants its entitlement).
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/features/car/car_screen_channel.dart';

CarScreenBridge bridge()=>CarScreenBridge(read:()=>null,actions:CarScreenActions(order:(o,s) async {},ack:(a,m) async {},
  send:(m) async {},sos:() async {},sosEnd:() async {}));

void main(){
  tearDown(()=>debugDefaultTargetPlatformOverride=null);

  test('channel on Android and iPhone only',(){
    for(final p in TargetPlatform.values){
      debugDefaultTargetPlatformOverride=p;
      expect(bridge().enabled,p==TargetPlatform.android||p==TargetPlatform.iOS,reason:'$p');
    }
  });
}
