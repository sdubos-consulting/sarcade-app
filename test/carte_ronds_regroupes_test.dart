// Card « Carte : regrouper les ronds des nœuds MeshCore et Meshtastic »
// (validated on 9 Nov 2026): one round with the number where they touch,
// each node alone from zoom 14, the selected node and a node heard in the
// last 15 minutes never grouped.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/node_clusters.dart';

typedef N=({String id,LatLng at,bool alone});

void main(){
  // 30 nodes around Versailles, a few hundred metres apart.
  final nodes=<N>[for(var i=0;i<30;i++)(id:'n$i',at:LatLng(48.80+i*0.002,2.13+i*0.002),alone:false)];

  MapCamera cam(double zoom)=>MapCamera(crs:const Epsg3857(),center:const LatLng(48.83,2.16),zoom:zoom,rotation:0,
    nonRotatedSize:const Size(390,700));

  test('Île-de-France scale: a few rounds instead of the cloud',(){
    final g=groupNodes(cam(9),nodes,(n)=>n.at,(n)=>n.alone);
    expect(g.length,lessThan(5));
    expect(g.expand((x)=>x).length,30);
  });

  test('from zoom 14 every node alone; without camera every node alone',(){
    expect(groupNodes(cam(14),nodes,(n)=>n.at,(n)=>n.alone).every((g)=>g.length==1),isTrue);
    expect(groupNodes<N>(null,nodes,(n)=>n.at,(n)=>n.alone).length,30);
  });

  test('selected or heard recently: never grouped',(){
    final some=[...nodes.skip(1),(id:'heard',at:nodes.first.at,alone:true)];
    final g=groupNodes(cam(9),some,(n)=>n.at,(n)=>n.alone);
    expect(g.where((x)=>x.length==1&&x.first.id=='heard'),hasLength(1));
    expect(g.where((x)=>x.length>1).expand((x)=>x).any((n)=>n.id=='heard'),isFalse);
  });

  test('icon of the most frequent kind; centre of the group',(){
    expect(mostFrequent(['repeater','companion','repeater']),'repeater');
    final c=groupCentre(const [LatLng(48,2),LatLng(50,4)]);
    expect(c.latitude,49);expect(c.longitude,3);
  });

  testWidgets('a round shows the number; a touch zooms in',(t) async {
    final map=MapController();
    final pts=[for(final n in nodes)n.at];
    await t.pumpWidget(MaterialApp(home:FlutterMap(mapController:map,options:const MapOptions(initialCenter:LatLng(48.83,2.16),initialZoom:9),
      children:[Builder(builder:(c)=>MarkerLayer(markers:[nodeGroupMarker(key:const ValueKey('grp'),points:pts,colour:Colors.grey,icon:Icons.cell_tower,map:map)]))])));
    await t.pump();
    expect(find.text('30'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('grp')));
    await t.pump();
    expect(map.camera.zoom,greaterThan(9));
  });
}
