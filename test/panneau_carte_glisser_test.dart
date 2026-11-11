import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/basemaps/basemap_models.dart';
import 'package:sarcade_app/src/features/basemaps/basemap_sheet.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/ui/app_sheet.dart';

// Card « Carte : fermer le panneau « Carte » en le glissant vers le bas, et
// vignette du fond deux fois plus large » (validated on 10 Nov 2026, choices
// 1 to 6).
Widget _app(void Function(BuildContext c) open,{NavigationMode mode=NavigationMode.traditional})=>MaterialApp(
  builder:(c,child)=>MediaQuery(data:MediaQuery.of(c).copyWith(navigationMode:mode),child:child!),
  home:Scaffold(body:Builder(builder:(c)=>TextButton(onPressed:()=>open(c),child:const Text('open')))));

void _openPanel(BuildContext c)=>showBasemapSheet(c,catalog:builtInBasemaps,current:builtInBasemaps.first,eventDefault:'',
  preferOffline:false,onChoose:(_){},onPreferOffline:(_){},
  tileUrlOf:(b)=>'https://tile.openstreetmap.org/{z}/{x}/{y}.png',around:(lat:48.8,lon:2.13),
  // Room enough for the list to scroll, as on a phone.
  layers:(c,_)=>[for(var i=0;i<20;i++)SwitchListTile(value:true,onChanged:(_){},title:Text('Couche $i'))]);

void main(){
  setUp(()=>S.setLanguage('fr'));

  test('thumbnail of the panel: 4 × 2 tiles of the same place, the point in the middle (choice 3)',(){
    final u=thumbTileUrls('https://tile.openstreetmap.org/{z}/{x}/{y}.png',48.8,2.13,columns:4)!;
    expect(u,[for(final y in [2819,2820])for(final x in [4142,4143,4144,4145])'https://tile.openstreetmap.org/13/$x/$y.png']);
    // The page « Fond de carte » keeps its 2 × 2.
    expect(thumbTileUrls('https://tile.openstreetmap.org/{z}/{x}/{y}.png',48.8,2.13)!.length,4);
  });

  testWidgets('panel « Carte »: handle at the top, thumbnail 144 × 72; the page keeps 96 × 96 (choices 1, 3, 4)',(t) async {
    await t.pumpWidget(_app(_openPanel));
    await t.tap(find.text('open')); await t.pumpAndSettle();
    expect(t.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,isTrue);
    final thumb=find.descendant(of:find.byKey(const ValueKey('basemap-current')),matching:find.byKey(const ValueKey('basemap-thumb')));
    expect(t.getSize(thumb),const Size(144,72));
    expect(find.descendant(of:thumb,matching:find.byType(Image)),findsNWidgets(8));
    // Square tiles of 36, cropped by the border, never stretched.
    final tile=t.getSize(find.descendant(of:thumb,matching:find.byType(Image)).first);
    expect(tile.width,closeTo(tile.height,2));
    expect(t.widgetList<Image>(find.descendant(of:thumb,matching:find.byType(Image))).every((i)=>i.fit==BoxFit.cover),isTrue);
    await t.tap(find.byKey(const ValueKey('basemap-current'))); await t.pumpAndSettle();
    expect(t.getSize(find.descendant(of:find.byKey(const ValueKey('basemap-osm')),matching:find.byKey(const ValueKey('basemap-thumb')))),const Size(96,96));
  });

  testWidgets('a swipe down on the panel closes it; a short one lets it go back up (choices 1 and 6)',(t) async {
    await t.pumpWidget(_app(_openPanel));
    await t.tap(find.text('open')); await t.pumpAndSettle();
    // A short, slow swipe: the panel comes back.
    await t.timedDrag(find.text('Carte'),const Offset(0,40),const Duration(seconds:1)); await t.pumpAndSettle();
    expect(find.text('Changer de fond'),findsOneWidget);
    // The list scrolled down: the swipe first brings it back to its top,
    // then pulls the panel down.
    await t.drag(find.text('OpenStreetMap'),const Offset(0,-300)); await t.pumpAndSettle();
    expect(find.text('Changer de fond').hitTestable(),findsNothing);
    await t.timedDrag(find.byType(SwitchListTile).hitTestable().first,const Offset(0,900),const Duration(milliseconds:900)); await t.pumpAndSettle();
    expect(find.text('Changer de fond'),findsNothing);
    expect(find.text('open'),findsOneWidget);
  });

  testWidgets('the handle alone also closes the panel',(t) async {
    await t.pumpWidget(_app(_openPanel));
    await t.tap(find.text('open')); await t.pumpAndSettle();
    final top=t.getTopLeft(find.byType(BottomSheet));
    await t.timedDragFrom(top+Offset(t.getSize(find.byType(BottomSheet)).width/2,20),const Offset(0,400),const Duration(milliseconds:500));
    await t.pumpAndSettle();
    expect(find.text('Changer de fond'),findsNothing);
  });

  testWidgets('no cross on Android and iPhone, « Fermer » kept for TalkBack / VoiceOver (choice 2)',(t) async {
    for(final p in [TargetPlatform.android,TargetPlatform.iOS]){
      debugDefaultTargetPlatformOverride=p;
      final semantics=t.ensureSemantics();
      await t.pumpWidget(_app(_openPanel));
      await t.tap(find.text('open')); await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('basemap-close')),findsNothing,reason:'$p');
      expect(find.byIcon(Icons.close),findsNothing,reason:'$p');
      final node=t.getSemantics(find.text('Carte'));
      expect(node.getSemanticsData().customSemanticsActionIds,isNotEmpty,reason:'$p');
      final close=CustomSemanticsAction.getAction(node.getSemanticsData().customSemanticsActionIds!.first)!;
      expect(close.label,'Fermer');
      semantics.dispose();
      Navigator.pop(t.element(find.text('Carte')));
      await t.pumpAndSettle();
      expect(find.text('Changer de fond'),findsNothing);
    }
    debugDefaultTargetPlatformOverride=null;
  });

  testWidgets('the cross stays on Windows and on the TV (choice 2)',(t) async {
    debugDefaultTargetPlatformOverride=TargetPlatform.windows;
    await t.pumpWidget(_app(_openPanel));
    await t.tap(find.text('open')); await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('basemap-close')),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('basemap-close'))); await t.pumpAndSettle();
    expect(find.text('Changer de fond'),findsNothing);
    // TV (Android moved by its remote): directional navigation.
    debugDefaultTargetPlatformOverride=TargetPlatform.android;
    await t.pumpWidget(_app(_openPanel,mode:NavigationMode.directional));
    await t.tap(find.text('open')); await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('basemap-close')),findsOneWidget);
    debugDefaultTargetPlatformOverride=null;
  });

  testWidgets('every sheet of the app: handle, and a swipe down closes it even when it scrolls (choice 5)',(t) async {
    String? got='none';
    await t.pumpWidget(_app((c) async {got=await showAppSheet<String>(context:c,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      ListTile(title:const Text('Un'),onTap:()=>Navigator.pop(c,'1')),
    ])));}));
    await t.tap(find.text('open')); await t.pumpAndSettle();
    expect(t.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,isTrue);
    await t.timedDrag(find.text('Un'),const Offset(0,300),const Duration(milliseconds:500)); await t.pumpAndSettle();
    expect(find.text('Un'),findsNothing);
    expect(got,isNull);
    // A long list (isScrollControlled): scrolled, back to the top, then closed.
    await t.pumpWidget(_app((c)=>showAppSheet<void>(context:c,isScrollControlled:true,builder:(c)=>ConstrainedBox(
      constraints:BoxConstraints(maxHeight:MediaQuery.sizeOf(c).height*0.8),
      child:ListView(shrinkWrap:true,children:[for(var i=0;i<40;i++)ListTile(title:Text('Ligne $i'))])))));
    await t.tap(find.text('open')); await t.pumpAndSettle();
    await t.drag(find.text('Ligne 3'),const Offset(0,-300)); await t.pumpAndSettle();
    expect(find.text('Ligne 0'),findsNothing);
    await t.timedDrag(find.text('Ligne 8'),const Offset(0,900),const Duration(milliseconds:900)); await t.pumpAndSettle();
    expect(find.text('Ligne 0'),findsNothing,reason:'closed after going back to the top');
    expect(find.byType(BottomSheet),findsNothing);
  });
}
