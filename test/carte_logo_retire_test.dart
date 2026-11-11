import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/map_bottom_line.dart';

void main(){
  // Card « Carte : ⓘ et logo en bas à gauche » (9 Nov 2026, option B): the
  // flutter_map logo goes, the ⓘ with the licence of the base map stays.
  test('no flutter_map logo, the licence of the base map stays',(){
    final w=mapAttribution(compact:true,fullBleed:false,text:'© OpenStreetMap contributors') as SafeArea;
    final rich=(w.child as Padding).child as RichAttributionWidget;
    expect(rich.showFlutterMapAttribution,isFalse);
    expect((rich.attributions.single as TextSourceAttribution).text,'© OpenStreetMap contributors');
  });
}
