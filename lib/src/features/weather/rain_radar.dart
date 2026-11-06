/// Rain radar (card « Météo : radar de pluie, aussi en calque sur la
/// carte », lot 29): the mosaic of Météo-France served as map tiles by the
/// SARCADE server; the device never contacts Météo-France.
///
/// While the layer is shown, the device asks the state every 2 minutes (the
/// server fetches only while someone looks); the tiles of an image never
/// change and stay in the cache of the map. Offline: the last image stays,
/// marked « ancienne » with its time.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../access/access_manager.dart';
import '../../l10n/strings.dart';
import '../../services/sarcade_api.dart';

const radarPollEvery=Duration(minutes:2);
const radarStaleAfter=Duration(minutes:20);

typedef RadarFrame=({String id,DateTime time});
typedef RadarClass=({double min,double? max,Color color});

class RadarState{
  final String state, source; final List<RadarFrame> frames; final List<RadarClass> legend;
  final bool stale; final String? error;
  const RadarState({required this.state,this.source='Météo-France',this.frames=const [],this.legend=const [],this.stale=false,this.error});

  factory RadarState.fromJson(Map j)=>RadarState(
    state:'${j['state']??'off'}',source:'${j['source']??'Météo-France'}',
    frames:[for(final f in (j['frames'] as List?)??const [])
      if(f is Map&&DateTime.tryParse('${f['time']}')!=null)(id:'${f['id']}',time:DateTime.parse('${f['time']}'))],
    legend:[for(final c in (j['legend'] as List?)??const [])
      if(c is Map)(min:(c['min'] as num).toDouble(),max:(c['max'] as num?)?.toDouble(),color:_hex('${c['color']}'))],
    stale:j['stale']==true,error:j['error'] as String?);

  RadarFrame? get latest=>frames.isEmpty?null:frames.last;

  /// Older than 20 minutes (the server says so, or the device is offline).
  bool staleAt(DateTime now)=>stale||(latest!=null&&now.toUtc().difference(latest!.time.toUtc())>radarStaleAfter);
}

Color _hex(String s){
  final v=int.tryParse(s.replaceFirst('#',''),radix:16)??0x888888;
  return Color(0xFF000000|v);
}

/// « 0,1 », « 64+ »: the bounds of a class in mm/h, French decimals.
String radarClassLabel(RadarClass c){
  String n(double v)=>(v==v.roundToDouble()?v.toInt().toString():v.toString()).replaceAll('.',S.lang=='fr'?',':'.');
  return c.max==null?'${n(c.min)}+':n(c.min);
}

/// Template of the tiles of one image, on the SARCADE server.
String radarTileUrl(String server,String frameId)=>'${server.replaceAll(RegExp(r'/+$'),'')}/api/v0.1/weather/radar/$frameId/{z}/{x}/{y}.png';

class RainRadar extends ChangeNotifier{
  final SarcadeApi api;
  RainRadar(this.api);
  RadarState? state; bool _on=false; Timer? _timer; bool offline=false;

  bool get on=>_on;

  void setOn(bool v){
    if(v==_on)return;
    _on=v;
    _timer?.cancel(); _timer=null;
    if(v){unawaited(refresh());_timer=Timer.periodic(radarPollEvery,(_)=>unawaited(refresh()));}
    notifyListeners();
  }

  /// A state known otherwise (tests, the TV).
  void apply(RadarState s){state=s;notifyListeners();}

  Future<void> refresh() async {
    try{
      state=RadarState.fromJson(await api.rainRadar());
      offline=false;
    }catch(_){offline=true;}
    notifyListeners();
  }

  @override
  void dispose(){_timer?.cancel();super.dispose();}
}

/// The layer of the map, under the markers; nothing until a first image.
Widget? rainRadarLayer(RainRadar radar,{required String server,required double opacity}){
  final frame=radar.state?.latest;
  if(!radar.on||frame==null)return null;
  final url=radarTileUrl(server,frame.id);
  return Opacity(opacity:opacity.clamp(0.0,1.0),child:TileLayer(key:ValueKey('radar-${frame.id}'),urlTemplate:url,userAgentPackageName:'org.sarcade.app',
    maxNativeZoom:11,maxZoom:20,tileProvider:NetworkTileProvider(headers:AccessManager.instance.headersFor(Uri.parse(url.split('{').first)))));
}

/// Under the switch of the layer: image time (« ancienne » when old), state
/// and legend, source.
class RainRadarDetail extends StatelessWidget{
  final RainRadar radar;
  const RainRadarDetail({super.key,required this.radar});

  String _hm(DateTime t){final l=t.toLocal();String two(int v)=>v.toString().padLeft(2,'0');return '${two(l.hour)}:${two(l.minute)}';}

  @override
  Widget build(BuildContext context)=>ListenableBuilder(listenable:radar,builder:(c,_){
    final t=Theme.of(c); final s=t.colorScheme;
    final st=radar.state;
    final frame=st?.latest;
    final String line;
    if(st==null){line=S.t(radar.offline?'radar.offline':'radar.loading');}
    else if(st.state=='no_key'){line=S.t('radar.noKey');}
    else if(frame==null){line=S.t(st.state=='error'?'radar.error':'radar.waiting');}
    else{line=S.t(st.staleAt(DateTime.now())||radar.offline?'radar.timeOld':'radar.time',{'time':_hm(frame.time)});}
    return Padding(padding:const EdgeInsets.fromLTRB(8,0,8,6),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(line,key:const ValueKey('radar-time'),style:t.textTheme.bodySmall),
      if(st!=null&&st.legend.isNotEmpty)Padding(padding:const EdgeInsets.only(top:4),child:Wrap(spacing:2,runSpacing:2,crossAxisAlignment:WrapCrossAlignment.center,children:[
        for(final k in st.legend)Container(padding:const EdgeInsets.symmetric(horizontal:4,vertical:1),color:k.color,
          child:Text(radarClassLabel(k),style:TextStyle(fontSize:10,color:k.color.computeLuminance()>0.5?Colors.black:Colors.white))),
        Padding(padding:const EdgeInsets.only(left:4),child:Text(S.t('radar.unit'),style:t.textTheme.bodySmall)),
      ])),
      Padding(padding:const EdgeInsets.only(top:2),child:Text(S.t('radar.source',{'source':st?.source??'Météo-France'}),
        style:t.textTheme.bodySmall?.copyWith(color:s.onSurfaceVariant))),
    ]));
  });
}
