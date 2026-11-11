import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/map_bottom_line.dart';
import 'package:sarcade_app/src/features/map/locate_button.dart' show northUp;

void main(){
  // Card « Carte : la faire tourner à deux doigts » (validated on 9 Nov 2026).
  test('two fingers and Ctrl + drag are manual, the compass and the « N » are not',(){
    expect(manualMapRotation(MapEventSource.onMultiFinger),isTrue);
    expect(manualMapRotation(MapEventSource.cursorKeyboardRotation),isTrue);
    expect(manualMapRotation(MapEventSource.mapController),isFalse);
    expect(manualMapRotation(MapEventSource.nonRotatedSizeChange),isFalse);
  });
  test('rotation starts after 20° of twist, so a pinch does not turn the map',(){
    expect(mapRotationThreshold,20);
  });
  test('a turned map is no longer north up (the « N » appears)',(){
    expect(northUp(0),isTrue);
    expect(northUp(35),isFalse);
  });
}
