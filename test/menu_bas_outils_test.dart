import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/tab_navigator.dart';

// Card « Menu du bas toujours visible (outils et Paramètres compris) »,
// validated on 8 Nov 2026: a tool opens inside its tab, the bottom bar stays.

class _Shell extends StatefulWidget {
  final GlobalKey<NavigatorState> tools;
  const _Shell(this.tools);
  @override State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int tab = 1;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: tab, children: [
      const Center(child: Text('Carte')),
      TabNavigator(navigatorKey: widget.tools, root: Scaffold(body: ListView(children: [
        ListTile(title: const Text('Météo'), onTap: () => widget.tools.open(() => Scaffold(
          appBar: AppBar(title: const Text('Météo du point')),
          body: Builder(builder: (c) => TextButton(
            onPressed: () => Navigator.push(c, MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Détail')))),
            child: const Text('Ouvrir le détail'))),
        ))),
      ]))),
    ]),
    bottomNavigationBar: Row(children: [
      TextButton(key: const ValueKey('bar-map'), onPressed: () => setState(() => tab = 0), child: const Text('Carte')),
      TextButton(key: const ValueKey('bar-tools'), onPressed: () => setState(() {
        if (tab == 1) { widget.tools.backToFirst(); } else { tab = 1; }
      }), child: const Text('Outils')),
    ]),
  );
}

void main() {
  testWidgets('a tool opens in the tab, the bottom bar stays visible', (tester) async {
    final tools = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(home: _Shell(tools)));
    await tester.tap(find.text('Météo'));
    await tester.pumpAndSettle();
    expect(find.text('Météo du point'), findsOneWidget);
    expect(find.byKey(const ValueKey('bar-map')), findsOneWidget);
    expect(find.byKey(const ValueKey('bar-tools')), findsOneWidget);
    // A page opened from the tool stays in the tab too.
    await tester.tap(find.text('Ouvrir le détail'));
    await tester.pumpAndSettle();
    expect(find.text('Détail'), findsOneWidget);
    expect(find.byKey(const ValueKey('bar-map')), findsOneWidget);
  });

  testWidgets('Back closes the screen on top, then nothing is left to close', (tester) async {
    final tools = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(home: _Shell(tools)));
    await tester.tap(find.text('Météo'));
    await tester.pumpAndSettle();
    expect(tools.hasOpen, isTrue);
    expect(tools.back(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Météo'), findsOneWidget);
    expect(tools.hasOpen, isFalse);
    expect(tools.back(), isFalse);
  });

  testWidgets('Outils touched again comes back to the list', (tester) async {
    final tools = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(home: _Shell(tools)));
    await tester.tap(find.text('Météo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ouvrir le détail'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bar-tools')));
    await tester.pumpAndSettle();
    expect(find.text('Météo'), findsOneWidget);
    expect(find.text('Détail'), findsNothing);
    expect(tools.hasOpen, isFalse);
  });

  testWidgets('switching tabs keeps the tool open', (tester) async {
    final tools = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(home: _Shell(tools)));
    await tester.tap(find.text('Météo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bar-map')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bar-tools')));
    await tester.pumpAndSettle();
    expect(find.text('Météo du point'), findsOneWidget);
  });

  testWidgets('open() replaces the tool already open', (tester) async {
    final tools = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(home: _Shell(tools)));
    tools.open(() => const Scaffold(body: Text('Fichiers')));
    await tester.pumpAndSettle();
    tools.open(() => const Scaffold(body: Text('ADS-B')));
    await tester.pumpAndSettle();
    expect(find.text('ADS-B'), findsOneWidget);
    expect(tools.back(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Météo'), findsOneWidget);
  });
}
