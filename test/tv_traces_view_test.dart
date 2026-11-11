// The view sent to a TV carries the traces of the map (1 Nov 2026).
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/tv/tv_view.dart';

void main() {
  test('traces window and pinned traces go with the layers', () {
    currentMapTraces = () => (windowMin: 0, pinned: ['TEL-02']);
    final j = tvViewJson((center: const LatLng(48.8, 2.1), zoom: 13, basemapId: 'osm', tileUrl: null, attribution: '', basemapName: 'OSM'),
        options: (layers: {'traces': true}, opacity: {'traces': 0.5}, messages: true));
    currentMapTraces = null;
    expect(j['traces_window'], 1440);
    expect(j['traces_ids'], ['TEL-02']);
    expect((j['layers'] as Map)['traces'], isTrue);
    expect(tvOpacityKeys, contains('traces'));
  });
}
