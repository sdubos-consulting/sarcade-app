import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/ui/keyboard.dart';

void main(){
  test('emoji button only where there is no touch keyboard',(){
    for(final (p,touch) in [(TargetPlatform.iOS,true),(TargetPlatform.android,true),(TargetPlatform.windows,false),(TargetPlatform.linux,false),(TargetPlatform.macOS,false)]){
      debugDefaultTargetPlatformOverride=p;
      expect(touchKeyboard,touch,reason:'$p');
    }
    debugDefaultTargetPlatformOverride=null;
  });
}
