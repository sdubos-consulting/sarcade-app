// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/settings/settings_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

import 'parametres_liste_test.dart' show config, size;

// Card « Paramètres : retoucher le bouton Paramètres revient à la liste »
// (validated on 9 Nov 2026): Paramètres touched again in the bottom bar,
// a page open (Mon profil) goes back to the list, without the ← top left.
void main() {
  setUp(() => S.setLanguage('fr'));

  testWidgets('iPhone: Mon profil, Paramètres touched again: the list', (t) async {
    await size(t, 390, 844);
    await t.pumpWidget(MaterialApp(home: SettingsPage(initial: config, onSave: (_) async {})));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('settings-row-profile')));
    await t.pumpAndSettle();
    expect(find.text('Mon profil'), findsOneWidget);
    settingsBackToList.notifyListeners();
    await t.pumpAndSettle();
    expect(find.text('Paramètres'), findsOneWidget);
    expect(find.text('Mon profil'), findsNothing);
    // Already on the list: nothing changes.
    settingsBackToList.notifyListeners();
    await t.pumpAndSettle();
    expect(find.text('Paramètres'), findsOneWidget);
  });

  testWidgets('computer: the list stays on the left, the page on the right', (t) async {
    await size(t, 1280, 800);
    await t.pumpWidget(MaterialApp(home: SettingsPage(initial: config, onSave: (_) async {})));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('settings-row-about')));
    await t.pumpAndSettle();
    settingsBackToList.notifyListeners();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-list')), findsOneWidget);
    expect(find.text('SDUBOS Consulting'), findsOneWidget);
  });
}
