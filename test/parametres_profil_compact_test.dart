import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/settings/settings_page.dart';

// Card « Paramètres › Profil : onglet compact » (validated on 5 Nov 2026):
// applied at once, no save bar unless a change waits.
void main(){
  test('no save bar in Profil unless a change waits; always at the first run',(){
    expect(settingsShowsSaveBar(tab:'profile',firstRun:false,dirty:false),isFalse);
    expect(settingsShowsSaveBar(tab:'profile',firstRun:false,dirty:true),isTrue);
    expect(settingsShowsSaveBar(tab:'profile',firstRun:true,dirty:false),isTrue);
  });
}
