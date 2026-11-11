// Card « Diagnostic : rendre l'affichage du disque lisible », validated on
// 11 Nov 2026: French numbers, To from 1 000 Go, same rule for the memory,
// one line on an iPhone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/settings/diagnostics_panel.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

const nb = ' ';

Map<String, DiagLine> lines(Map<String, dynamic> res) =>
    {for (final l in serverLines({'status': 'ok', 'resources': res})) l.label: l};

void main() {
  setUp(() => S.setLanguage('fr'));

  test('choice 1: decimal comma and narrow no-break space for thousands', () {
    expect(diagNumber(36841.7), '36 841,7');
    expect(diagNumber(69.0), '69');
    expect(diagNumber(1234567, decimals: 0), '1 234 567');
    S.setLanguage('en');
    expect(diagNumber(36841.7), '36,841.7');
  });

  test('choice 2: the disk of the card in To', () {
    final disk = lines({'disk': {'used_gb': 36841.7, 'total_gb': 69063.1, 'pct': 53.3}})['Disque']!;
    expect(disk.value, '53$nb%$nb·${nb}36,8$nb/${nb}69,1${nb}To');
    expect(lines({'disk': {'used_gb': 40.1, 'total_gb': 100.0, 'pct': 40.0}})['Disque']!.value, '40$nb%$nb·${nb}40$nb/${nb}100${nb}Go');
    expect(lines({'disk': {'used_gb': 12.3, 'total_gb': 58.6, 'pct': 21.0}})['Disque']!.value, '21$nb%$nb·${nb}12,3$nb/${nb}58,6${nb}Go');
  });

  test('choice 3: same rule for the memory (Mo then Go)', () {
    expect(lines({'memory': {'used_mb': 6500, 'total_mb': 8000, 'pct': 81.2}})['Mémoire']!.value, '81$nb%$nb⚠$nb·${nb}6,3$nb/${nb}7,8${nb}Go');
    expect(lines({'memory': {'used_mb': 410, 'total_mb': 512, 'pct': 80.0}})['Mémoire']!.value, '80$nb%$nb·${nb}410$nb/${nb}512${nb}Mo');
  });

  testWidgets('choice 4: one line on an iPhone', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final disk = lines({'disk': {'used_gb': 36841.7, 'total_gb': 69063.1, 'pct': 53.3}})['Disque']!;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [DiagLineRow(line: disk)]))));
    expect(find.byKey(const ValueKey('diag-value-one-line')), findsOneWidget);
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.maxLines, 1);
    final para = tester.renderObject<RenderBox>(find.byType(SelectableText));
    expect(tester.getSize(find.byType(DiagLineRow)).height, lessThan(60), reason: 'a single line, ${para.size}');
  });

  test('a long value still wraps', () {
    expect(isUnbreakable('vigilance refusée (clé non abonnée)'), isFalse);
    expect(isUnbreakable(unbreakable('53 % · 36,8 / 69,1 To')), isTrue);
  });
}
