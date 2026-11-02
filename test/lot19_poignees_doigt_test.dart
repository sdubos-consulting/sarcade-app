import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_layers.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';

// Card « Dessin au doigt : poignées trop petites pour redimensionner et
// déplacer » (lot 19, choices 1 to 6).

MapFeature _f(String id,FeatureKind kind,List<LatLng> points,{double? radiusM})=>MapFeature(id:id,eventId:'e',kind:kind,points:points,radiusM:radiusM,
  color:0xFFE53935,strokeWidth:4,createdBy:'T1',updatedBy:'T1',updatedAt:DateTime.utc(2026));

final _rect=_f('r',FeatureKind.rectangle,const [LatLng(48.796,2.094),LatLng(48.804,2.106)]);
final _zone=_f('z',FeatureKind.zone,const [LatLng(48.795,2.09),LatLng(48.795,2.11),LatLng(48.805,2.10)]);
final _circle=_f('c',FeatureKind.circle,const [LatLng(48.8,2.1)],radiusM:400);

/// A map with drag allowed (the worst case): the handle has to win anyway.
class _Harness {
  final c=DrawingController(eventId:'e',actorId:'T1',initial:[_rect,_zone,_circle]);
  final m=MapController();
  final box=GlobalKey();
  LatLng toLatLng(Offset global){final r=box.currentContext!.findRenderObject() as RenderBox;return m.camera.screenOffsetToLatLng(r.globalToLocal(global));}
  Offset toGlobal(LatLng p){final r=box.currentContext!.findRenderObject() as RenderBox;return r.localToGlobal(m.camera.latLngToScreenOffset(p));}
  Widget build()=>MaterialApp(home:Scaffold(body:SizedBox(key:box,width:800,height:600,child:ListenableBuilder(listenable:c,builder:(_,_)=>FlutterMap(mapController:m,
    options:const MapOptions(initialCenter:LatLng(48.8,2.1),initialZoom:14),
    children:[...buildDrawingLayers(c),buildHandleLayer(c,toLatLng)])))));
}

/// Finger drag in small steps, like a real touch.
Future<void> _fingerDrag(WidgetTester t,Offset from,Offset by,{void Function()? during}) async {
  final g=await t.startGesture(from,kind:PointerDeviceKind.touch);
  await t.pump();
  for(var i=0;i<8;i++){await g.moveBy(by/8);await t.pump();}
  during?.call();
  await g.up();
  await t.pump();
}

void main() {
  setUp(()=>fingerHandles.value=true);

  test('sizes: mouse as before, bigger for the finger', () {
    expect(mouseHandleSizes, (vertex:8.0,mid:6.0,move:12.0,touch:44.0));
    expect(fingerHandleSizes, (vertex:18.0,mid:12.0,move:28.0,touch:56.0));
  });

  test('the last pointer decides: touch or stylus = finger, mouse = mouse', () {
    notePointerForHandles(const PointerDownEvent(kind:PointerDeviceKind.mouse));
    expect(fingerHandles.value, isFalse);
    notePointerForHandles(const PointerDownEvent(kind:PointerDeviceKind.touch));
    expect(fingerHandles.value, isTrue);
    notePointerForHandles(const PointerHoverEvent(kind:PointerDeviceKind.mouse));
    expect(fingerHandles.value, isFalse);
    notePointerForHandles(const PointerDownEvent(kind:PointerDeviceKind.stylus));
    expect(fingerHandles.value, isTrue);
    expect(isTouchPlatform(TargetPlatform.iOS), isTrue);
    expect(isTouchPlatform(TargetPlatform.android), isTrue);
    expect(isTouchPlatform(TargetPlatform.windows), isFalse);
  });

  test('rectangle: 4 corners, still stored as 2 opposite corners', () {
    final c=DrawingController(eventId:'e',actorId:'T1',initial:[_rect]);
    c.select('r');
    c.beginEdit();
    c.moveRectangleCorner(1,const LatLng(48.799,2.110));
    c.endEdit();
    var p=c.selected!.points;
    expect(p, hasLength(2));
    expect(p[0], const LatLng(48.799,2.094), reason:'corner 1 moves the side of a and the side of b');
    expect(p[1], const LatLng(48.804,2.110));
    c.beginEdit();
    c.moveRectangleCorner(3,const LatLng(48.806,2.090));
    c.endEdit();
    p=c.selected!.points;
    expect(p[0], const LatLng(48.799,2.090));
    expect(p[1], const LatLng(48.806,2.110));
    c.moveRectangleCorner(0,const LatLng(48.79,2.08));
    expect(c.selected!.points[0], const LatLng(48.79,2.08));
    c.moveRectangleCorner(2,const LatLng(48.81,2.12));
    expect(c.selected!.points[1], const LatLng(48.81,2.12));
  });

  testWidgets('finger: 56 px touch area, 4 corner handles on a rectangle; mouse: 44 px', (t) async {
    final h=_Harness()..c.select('r');
    await t.pumpWidget(h.build());
    await t.pump();
    for(var i=0;i<4;i++){expect(find.byKey(ValueKey('corner-$i')), findsOneWidget);}
    expect(t.getSize(find.byKey(const ValueKey('move-handle'))), const Size(56,56));
    fingerHandles.value=false;
    await t.pump();
    expect(t.getSize(find.byKey(const ValueKey('move-handle'))), const Size(44,44));
  });

  testWidgets('finger on a corner of a rectangle: the rectangle changes, not the map', (t) async {
    final h=_Harness()..c.select('r');
    await t.pumpWidget(h.build());
    await t.pump();
    final centre=h.m.camera.center;
    final corner=t.getCenter(find.byKey(const ValueKey('corner-1')));
    var held=false;
    await _fingerDrag(t,corner,const Offset(40,30),during:()=>held=h.c.handleHeld);
    expect(held, isTrue, reason:'the map is locked while the finger holds the handle');
    expect(h.c.handleHeld, isFalse);
    expect(h.m.camera.center, centre, reason:'the map did not move');
    final r=h.c.feature('r')!;
    expect(r.points, hasLength(2));
    expect(r.points[1].longitude, greaterThan(2.106), reason:'the east side moved right');
    expect(r.points[0].latitude, lessThan(48.796), reason:'the south side moved down');
    expect(r.points[0].longitude, closeTo(2.094,1e-9));
    expect(r.points[1].latitude, closeTo(48.804,1e-9));
    expect(h.c.canUndo, isTrue);
  });

  testWidgets('finger on a vertex of a zone: the vertex moves, not the map', (t) async {
    final h=_Harness()..c.select('z');
    await t.pumpWidget(h.build());
    await t.pump();
    final centre=h.m.camera.center;
    await _fingerDrag(t,h.toGlobal(_zone.points[2]),const Offset(0,-40));
    expect(h.m.camera.center, centre);
    final z=h.c.feature('z')!;
    expect(z.points, hasLength(3));
    expect(z.points[2].latitude, greaterThan(48.805));
    expect(z.points[0], _zone.points[0]);
  });

  testWidgets('finger on the radius handle of a circle: the radius grows, not the map', (t) async {
    final h=_Harness()..c.select('c');
    await t.pumpWidget(h.build());
    await t.pump();
    final centre=h.m.camera.center;
    await _fingerDrag(t,t.getCenter(find.byKey(const ValueKey('radius-handle'))),const Offset(50,0));
    expect(h.m.camera.center, centre);
    expect(h.c.feature('c')!.radiusM, greaterThan(500));
  });

  testWidgets('finger on the move cross: the object moves, not the map; same for a multiple selection', (t) async {
    final h=_Harness()..c.select('r');
    await t.pumpWidget(h.build());
    await t.pump();
    final centre=h.m.camera.center;
    await _fingerDrag(t,t.getCenter(find.byKey(const ValueKey('move-handle'))),const Offset(60,0));
    expect(h.m.camera.center, centre);
    expect(h.c.feature('r')!.points[0].longitude, greaterThan(2.094));
    expect(h.c.feature('r')!.points[0].latitude, closeTo(48.796,1e-6));

    h.c.select('z');
    h.c.toggle('c');
    await t.pump();
    final zBefore=h.c.feature('z')!.points[0], cBefore=h.c.feature('c')!.points[0];
    await _fingerDrag(t,t.getCenter(find.byKey(const ValueKey('move-handle'))),const Offset(0,40));
    expect(h.m.camera.center, centre);
    expect(h.c.feature('z')!.points[0].latitude, lessThan(zBefore.latitude));
    expect(h.c.feature('c')!.points[0].latitude, lessThan(cBefore.latitude));
  });

  testWidgets('without a handle under the finger, the map still pans', (t) async {
    final h=_Harness();
    await t.pumpWidget(h.build());
    await t.pump();
    final centre=h.m.camera.center;
    await _fingerDrag(t,const Offset(100,100),const Offset(80,0));
    expect(h.m.camera.center, isNot(centre));
  });
}
