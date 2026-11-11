// Card « Outils : fermer chaque écran avec la flèche retour en haut à
// gauche, plus de croix à droite », validated on 11 Nov 2026 (Itinéraire
// only, choices 1 to 3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/routes/routes_controller.dart';
import 'package:sarcade_app/src/features/routes/routes_panel.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/offline/local_store.dart';
import 'package:sarcade_app/src/offline/sync_service.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';
import 'package:sarcade_app/src/ui/edge_swipe_back.dart';

class _Store extends LocalStore {
  @override List<Map<String, dynamic>> pending() => [];
  @override List<Map<String, dynamic>> pendingUploads() => [];
  @override String cursor(String eventId) => '0';
  @override Future<void> setCursor(String eventId, String cursor) async {}
  @override List<Map<String, dynamic>> routeObjects(String eventId) => [
    {'id': 'r1', 'kind': 'route', 'name': 'Battue nord', 'created_by': 'me', 'color': 0xFF2E7D32},
  ];
}

void main() {
  setUp(() => S.setLanguage('fr'));

  Future<({List<String> calls})> pump(WidgetTester t, {String? selected, bool phone = true}) async {
    final calls = <String>[];
    final store = _Store();
    final api = SarcadeApi(baseUrl: 'https://s');
    final c = RoutesController(api: api, store: store, sync: OfflineSyncService(api: api, store: store, eventId: 'e1'), eventId: 'e1', actorId: 'me');
    await t.pumpWidget(MaterialApp(home: Scaffold(body: RoutesPanel(controller: c, api: api, actorId: 'me', selectedRouteId: selected,
      drawingRouteId: null, groups: const [], onSelect: (id) => calls.add('select:$id'), onDraw: (_) {}, onDrawClosure: () {},
      onNavigate: (_, _) {}, onFocus: (_) {}, onClose: phone ? () => calls.add('close') : null))));
    await t.pump();
    return (calls: calls);
  }

  testWidgets('choice 1: ← at the top left, no more ✕', (t) async {
    final r = await pump(t);
    final back = find.byKey(const ValueKey('routes-back'));
    expect(back, findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(t.getTopLeft(back).dx, lessThan(t.getTopLeft(find.text('Itinéraires')).dx), reason: 'before the title');
    expect(t.getTopLeft(back).dx, lessThan(20));
    await t.tap(back);
    expect(r.calls, ['close']);
  });

  testWidgets('one step back: the route shown → the list, a single ←', (t) async {
    final r = await pump(t, selected: 'r1');
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('routes-back')));
    expect(r.calls, ['select:null']);
  });

  testWidgets('computer (side panel): no ← in the header, the one of the route stays', (t) async {
    await pump(t, phone: false);
    expect(find.byKey(const ValueKey('routes-back')), findsNothing);
    await pump(t, selected: 'r1', phone: false);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  testWidgets('choice 2: swipe from the left edge goes back (iPhone)', (t) async {
    var back = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: EdgeSwipeBack(onBack: () => back++, child: const SizedBox.expand()))));
    await t.dragFrom(const Offset(5, 300), const Offset(400, 0));
    await t.pumpAndSettle();
    expect(back, 1);
    await t.dragFrom(const Offset(200, 300), const Offset(400, 0));
    await t.pumpAndSettle();
    expect(back, 1, reason: 'only from the edge');
  });
}
