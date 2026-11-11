import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/settings/settings_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/message.dart';
import 'package:sarcade_app/src/services/notification_actions.dart';

// Card « Paramètres › Notifications : onglet compact » (validated on 5 Nov
// 2026): one line per priority, applied at once, no save bar.
void main(){
  setUp(()=>S.setLanguage('fr'));
  test('no save bar in Notifications unless the Android switch changed',(){
    expect(settingsShowsSaveBar(tab:'notifications',firstRun:false,dirty:false),isFalse);
    expect(settingsShowsSaveBar(tab:'notifications',firstRun:false,dirty:true),isTrue);
  });
  test('one line per priority: short title, sound as the value, Routine silent by default',(){
    expect([for(final p in soundChoices.keys)S.t(priorityKey(p))],['Routine','Urgent','Immédiat']);
    expect(S.t('sound.${soundDefaults['routine']}'),'Silencieux');
    expect(S.t('wakeup.receivedAt',{'time':'19:06'}),'Reçu à 19:06 ✓');
  });
}
