import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/tab_retap.dart';
import 'package:sarcade_app/src/features/messages/messages_nav.dart';

void main() {
  test('Messages touched three times from a conversation: the list stays, never the map', () {
    final nav = MessagesNavigator();
    var chatOpen = true;
    nav.attach(() { if (!chatOpen) return false; chatOpen = false; return true; });
    var tops = 0;
    for (var i = 0; i < 3; i++) {
      messagesTouchedAgain(nav, toTop: () => tops++);
    }
    expect(chatOpen, isFalse, reason: 'first touch: back to the list');
    expect(tops, 2, reason: 'next touches: the list to its top');
  });

  testWidgets('a tab touched again: vertical lists back to the top, horizontal ones unchanged', (tester) async {
    final key = GlobalKey();
    final down = ScrollController(), across = ScrollController();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: KeyedSubtree(key: key, child: Column(children: [
      SizedBox(height: 60, child: ListView(controller: across, scrollDirection: Axis.horizontal,
          children: [for (var i = 0; i < 30; i++) SizedBox(width: 80, child: Text('chip $i'))])),
      Expanded(child: ListView(controller: down, children: [for (var i = 0; i < 100; i++) SizedBox(height: 50, child: Text('row $i'))])),
    ])))));
    down.jumpTo(1200);
    across.jumpTo(400);
    await tester.pump();
    scrollTabToTop(key.currentContext);
    await tester.pumpAndSettle();
    expect(down.offset, 0);
    expect(across.offset, 400);
    // Already at the top, or no screen built yet: nothing happens.
    scrollTabToTop(key.currentContext);
    scrollTabToTop(null);
    await tester.pumpAndSettle();
    expect(down.offset, 0);
  });
}
