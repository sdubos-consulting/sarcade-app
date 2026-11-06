// Lot 29, card « Dictée : le micro s'arrête au bout de 2 ou 3 secondes »
// (5 Nov 2026, 17 h 20).
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/dictation/dictation_button.dart';

void main(){
  test('counter and limits of a dictation',(){
    expect(dictationElapsed(const Duration(seconds:12)),'0:12');
    expect(dictationElapsed(const Duration(seconds:65)),'1:05');
    expect(dictationMaxLength,const Duration(seconds:60));
    expect(dictationPause,const Duration(seconds:5));
    expect(dictationActive.value,isFalse);
  });
}
