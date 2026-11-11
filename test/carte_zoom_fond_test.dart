// Card « Carte : fond gris quand on zoome trop » (validated on 9 Nov 2026):
// beyond the zoom of its base map, the last images are enlarged.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/basemaps/basemap_models.dart';

void main(){
  test('every base map keeps its own zoom, the map goes to 20',(){
    expect(mapMaxZoom,20);
    for(final b in builtInBasemaps){
      expect(basemapNativeZoom(b),lessThanOrEqualTo(20),reason:b.id);
      expect(basemapNativeZoom(b),b.maxZoom.clamp(1,20),reason:b.id);
    }
    final topo=builtInBasemaps.firstWhere((b)=>b.id=='topo');
    expect(basemapNativeZoom(topo),17);
  });

  testWidgets('zoom 20 on Topographique: the base layer still asks for tiles (enlarged from 17)',(t) async {
    final topo=builtInBasemaps.firstWhere((b)=>b.id=='topo');
    final asked=<String>[];
    await t.pumpWidget(MaterialApp(home:FlutterMap(
      options:const MapOptions(initialCenter:LatLng(48.8,2.0),initialZoom:20,maxZoom:mapMaxZoom),
      children:[TileLayer(urlTemplate:'https://t/{z}/{x}/{y}.png',maxNativeZoom:basemapNativeZoom(topo),maxZoom:mapMaxZoom,
        tileProvider:_Recorder(asked))])));
    await t.pump();
    expect(asked,isNotEmpty,reason:'the base map is drawn at zoom 20');
    expect(asked.every((u)=>u.startsWith('https://t/17/')),isTrue,reason:asked.take(3).join(' '));
  });
}

class _Recorder extends TileProvider {
  final List<String> asked;
  _Recorder(this.asked);
  @override ImageProvider getImage(TileCoordinates c,TileLayer o){
    asked.add(getTileUrl(c,o));
    return MemoryImage(_png);
  }
}

// 1×1 transparent PNG.
final _png=Uint8List.fromList(const [137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,1,0,0,0,1,8,6,0,0,0,31,21,196,137,0,0,0,13,73,68,65,84,120,156,99,0,1,0,0,5,0,1,13,10,45,180,0,0,0,0,73,69,78,68,174,66,96,130]);
