import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_toolbar.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  setUp(()=>S.setLanguage('fr'));
  testWidgets('two rows of five, no « Fermer », Annuler and Rétablir labelled',(t) async {
    // The size the code reads (MediaQuery), not only the surface.
    t.view.physicalSize=const Size(390,844); t.view.devicePixelRatio=1;
    addTearDown(t.view.reset);
    final c=DrawingController(eventId:'e',actorId:'T1'); var closed=0;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Align(alignment:Alignment.topLeft,child:DrawingToolbar(controller:c,onClose:()=>closed++)))));
    expect(find.byKey(const ValueKey('draw-close')),findsNothing);
    expect(find.text('Annuler'),findsOneWidget); expect(find.text('Rétablir'),findsOneWidget);
    final y1=t.getCenter(find.byKey(const ValueKey('draw-tool-line'))).dy;
    expect(t.getCenter(find.byKey(const ValueKey('draw-tool-zone'))).dy,y1);
    final y2=t.getCenter(find.byKey(const ValueKey('draw-tool-freehand'))).dy;
    expect(y2,greaterThan(y1));
    expect(t.getCenter(find.byKey(const ValueKey('draw-redo'))).dy,y2);
    expect(t.takeException(),isNull,reason:'fits an iPhone in portrait');
    // Touching the chosen tool again closes the palette.
    await t.tap(find.byKey(const ValueKey('draw-tool-line'))); await t.pump();
    expect(c.tool,FeatureKind.line);
    await t.tap(find.byKey(const ValueKey('draw-tool-line'))); await t.pump();
    expect(closed,1);
  });
}
