// Left bar: tools pinned from the Tools tiles (1 Nov 2026).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/operational_map_page.dart' show railMaxPins;
import 'package:sarcade_app/src/features/tools/tools_page.dart';

void main() {
  testWidgets('each tile has a pin when the bar can be customised', (t) async {
    final toggled = <String>[];
    final items = [
      ToolItem(id: 'files', icon: Icons.folder, title: 'Fichiers', subtitle: 's', color: Colors.teal, onTap: () {}),
      ToolItem(id: 'weather', icon: Icons.cloud, title: 'Météo', subtitle: 's', color: Colors.orange, onTap: () {}),
    ];
    await t.pumpWidget(MaterialApp(home: ToolsPage(items: items, pinned: const {'files'}, onTogglePin: toggled.add)));
    expect(find.byKey(const ValueKey('pin-files')), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('pin-weather')));
    expect(toggled, ['weather']);
    expect(railMaxPins, 6);
  });

  testWidgets('phone: no pin', (t) async {
    await t.pumpWidget(MaterialApp(home: ToolsPage(items: [
      ToolItem(id: 'files', icon: Icons.folder, title: 'Fichiers', subtitle: 's', color: Colors.teal, onTap: () {}),
    ])));
    expect(find.byKey(const ValueKey('pin-files')), findsNothing);
  });
}
