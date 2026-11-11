import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/settings/settings_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

// Card « Paramètres › Événement : onglet compact » (validated on 5 Nov 2026):
// applied at once for everyone, no save bar, modules on one line.
void main(){
  setUp(()=>S.setLanguage('fr'));
  test('no save bar in Événement; modules counted on one line',(){
    expect(settingsShowsSaveBar(tab:'event',firstRun:false,dirty:false),isFalse);
    expect(S.t('event.modulesActive',{'n':1}),'1 actif');
    expect(S.t('event.modulesActive',{'n':2}),'2 actifs');
    expect(S.t('event.appliedForAll'),'Appliqué aussitôt pour tous · inscrit en main courante');
  });
}
