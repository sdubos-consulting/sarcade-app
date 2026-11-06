import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_node_list.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_protocol.dart';

MeshCoreContact _n(String name,{Duration? age,double? lat,double? lon})=>MeshCoreContact(key:'${name}0011223344',type:2,name:name,
  lastAdvert:age==null?null:DateTime.utc(2026,11,5,20).subtract(age),lat:lat,lon:lon);

void main(){
  final now=DateTime.utc(2026,11,5,20);
  test('today, older, hidden after 30 days',(){
    final s=meshCoreSections([_n('a',age:const Duration(minutes:2)),_n('b',age:const Duration(days:3)),_n('c',age:const Duration(days:901)),_n('d')],now);
    expect(s.today.map((n)=>n.name),['a']);
    expect(s.older.map((n)=>n.name),['b','d']);
    expect(s.hidden,1);
  });
  test('distance and direction from me, order by distance',(){
    expect(meshCoreRelative(48.80,2.13,48.89,2.13),'10 km N');
    expect(meshCoreRelative(48.80,2.13,48.80,2.12),matches(RegExp(r'^7\d\d m O$')));
    final near=_n('near',lat:48.81,lon:2.13), far=_n('far',lat:49.5,lon:2.13), none=_n('none');
    expect(sortMeshCoreNodes([far,none,near],MeshCoreSort.distance,me:const LatLng(48.80,2.13)).map((n)=>n.name),['near','far','none']);
  });
}
