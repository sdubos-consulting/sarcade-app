import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/phone_tab_item.dart';
import 'package:sarcade_app/src/ui/theme.dart';

// Card « Menu du bas : surligner seulement l'icône, pas le texte » (validated
// on 5 Nov 2026): pill around the icon only, label below without background,
// chosen tab: icon in blue, label in the dark ink (white in dark mode), never blue.

Widget _bar(ThemeData theme, {int selected = 0, double width = 390}) => MaterialApp(theme: theme,
  home: Scaffold(body: Center(child: SizedBox(width: width, child: Row(children: [
    for (final (i, label) in ['Carte', 'Messages', 'Équipes', 'Outils', 'Paramètres'].indexed)
      Expanded(child: PhoneTabItem(key: ValueKey('tab-$i'), id: 'tab$i', label: label, selected: i == selected, onTap: () {},
        icon: Badge(isLabelVisible: i == 1, label: const Text('3'), child: const Icon(Icons.map_outlined)))),
  ])))));

BoxDecoration? _pill(WidgetTester tester, int i) => tester.widget<Container>(
  find.descendant(of: find.byKey(ValueKey('tab-$i')), matching: find.byKey(const ValueKey('tab-pill')))).decoration as BoxDecoration?;

Text _label(WidgetTester tester, String label) => tester.widget<Text>(find.text(label));

void main() {
  for (final (name, theme) in [('day', dayTheme()), ('night', nightTheme())]) {
    testWidgets('$name: pill around the icon only, night blue icon, label below it', (tester) async {
      await tester.pumpWidget(_bar(theme));
      final scheme = theme.colorScheme;
      final pill = find.descendant(of: find.byKey(const ValueKey('tab-0')), matching: find.byKey(const ValueKey('tab-pill')));
      final rect = tester.getRect(pill);
      expect(rect.size, const Size(phoneTabPillWidth, phoneTabPillHeight));
      // Night blue of the logo (9 Nov 2026).
      final chosen = phoneTabSelectedColors(scheme.brightness);
      expect(_pill(tester, 0)!.color, chosen.pill);
      // The label is below the pill, outside of it.
      final label = tester.getRect(find.text('Carte'));
      expect(label.top, greaterThanOrEqualTo(rect.bottom));
      // The icon is inside the pill.
      final icon = tester.getRect(find.descendant(of: find.byKey(const ValueKey('tab-0')), matching: find.byType(Icon)));
      expect(rect.contains(icon.center), isTrue);
      // Chosen: label in dark ink (white at night), bold, never blue; icon in blue (8 Nov 2026).
      expect(_label(tester, 'Carte').style!.color, scheme.onSurface);
      expect(_label(tester, 'Carte').style!.color, isNot(scheme.primary));
      expect(_label(tester, 'Carte').style!.fontWeight, FontWeight.w700);
      final iconTheme = IconTheme.of(tester.element(find.descendant(of: find.byKey(const ValueKey('tab-0')), matching: find.byType(Icon))));
      expect(iconTheme.color, chosen.icon);
      // The others: grey, no pill.
      expect(_pill(tester, 2)!.color, isNull);
      expect(_label(tester, 'Équipes').style!.color, scheme.onSurfaceVariant);
      expect(_label(tester, 'Équipes').style!.fontWeight, FontWeight.w500);
    });
  }

  testWidgets('Messages chosen: its pill, unread badge kept on the icon', (tester) async {
    await tester.pumpWidget(_bar(dayTheme(), selected: 1));
    expect(_pill(tester, 1)!.color, const Color(0xFFDCE3EE));
    expect(_pill(tester, 0)!.color, isNull);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('narrow phone (320): the pill shrinks, nothing overflows', (tester) async {
    await tester.pumpWidget(_bar(dayTheme(), width: 296));
    expect(tester.takeException(), isNull);
    final pill = find.descendant(of: find.byKey(const ValueKey('tab-0')), matching: find.byKey(const ValueKey('tab-pill')));
    expect(tester.getSize(pill).width, lessThanOrEqualTo(296 / 5));
  });

  // Card « Menu du bas : couleur de l'onglet choisi tirée du logo » (9 Nov 2026).
  test('night blue of the logo: pale pill and night blue icon by day, night blue pill and white icon by night', () {
    expect(phoneTabSelectedColors(Brightness.light).pill, const Color(0xFFDCE3EE));
    expect(phoneTabSelectedColors(Brightness.light).icon, logoNightBlue);
    expect(phoneTabSelectedColors(Brightness.dark).pill, const Color(0xFF1C3A66));
    expect(phoneTabSelectedColors(Brightness.dark).icon, Colors.white);
  });
}
