/// Card « Convertisseur de coordonnées : écran compact » (lot 29.5): title
/// « Coordonnées », one field « Coller, saisir ou chercher un lieu » (text,
/// links, typed coordinates, address), two sources (Ma position, Toucher la
/// carte), one line per format (a touch copies, ⋮ reads aloud or shows big),
/// « En clair » first and following the pin, actions on one row, « Effacer »
/// the history in the ⋮ of the header.
///
/// Convertisseur de coordonnées (menu Outils, 29 Oct 2026; étoffé par le
/// lot 5, validated on 30 Oct 2026, 2 h 11): source of the position (my
/// position live by default, touch the map, an operator / high point /
/// relay / point of interest or an address by search, typed text), guided
/// input (recognised format, separate fields per format, dictation),
/// every output format (Lambert 93 and DFCI included, MGRS precision),
/// draggable mini map, radio reading, big characters, actions, history of
/// the last 10 conversions. Same presentation of the formats as the fiche
/// « Infos du point ».
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../../offline/local_store.dart';
import '../../services/location_service.dart';
import '../dictation/dictation_button.dart';
import '../measure/coordinate_rows.dart';
import '../measure/coordinates.dart';
import '../search/map_search.dart';
import 'converter_input.dart' show pushHistory;
import 'paste_locations.dart';
import '../../ui/link_status.dart';
import '../../ui/theme.dart' show searchInputBorder;

enum ConverterSource { me, map, search, input }

/// Delay after the pin stops before the « En clair » line is asked again.
const plainDelay=Duration(milliseconds:500);

/// Actions handed back to the map (the converter closes first).
class ConverterActions {
  final void Function(LatLng)? show, measure, poi, bearing, order;
  final void Function(String text)? message;
  /// « Toucher la carte »: the converter closes, the map is touched, the
  /// converter opens again on that point.
  final VoidCallback? pickOnMap;
  const ConverterActions({this.show,this.measure,this.poi,this.bearing,this.order,this.message,this.pickOnMap});
}

class CoordinateConverterPage extends StatefulWidget {
  final LatLng? initial;
  final void Function(LatLng)? onShow, onMeasure;
  final ConverterActions actions;
  final LocationService? location; final LocalStore? store;
  /// Operators, high points, relays, points of interest of the event.
  final Iterable<Searchable> Function()? items;
  final Future<List<SearchResult>> Function(String query,LatLng? near)? addresses;
  final String tileUrl;
  /// « En clair » (lot 29.5): « 850 m au nord-est de Marnes-la-Coquette ·
  /// Rue de la Gare », from the server (readable_place.dart); null: no line.
  final Future<String?> Function(LatLng p)? describe;
  const CoordinateConverterPage({super.key,this.initial,this.onShow,this.onMeasure,this.actions=const ConverterActions(),
    this.location,this.store,this.items,this.addresses,this.tileUrl='',this.describe});
  @override State<CoordinateConverterPage> createState()=>_CoordinateConverterPageState();
}

class _CoordinateConverterPageState extends State<CoordinateConverterPage> {
  late final TextEditingController _text=TextEditingController(text:widget.initial==null?'':formatDd(widget.initial!,decimal:'.'));
  late ConverterSource _source=widget.initial!=null?ConverterSource.input:widget.location!=null?ConverterSource.me:ConverterSource.input;
  LatLng? _picked, _live; String? _pickedLabel; StreamSubscription? _gps;
  int _mgrsDigits=4;
  List<SearchResult> _results=const []; List<FoundLocation> _found=const []; Timer? _debounce; bool _looking=false;
  final _mini=MapController();
  List<Map<String,dynamic>> _history=[];
  static const _historyKey='converter_history';
  // « En clair »: text of the last point asked, « … » while the pin moves.
  String? _plain; LatLng? _plainFor; bool _plainMoving=false; Timer? _plainTimer;
  final Map<String,String?> _plainCache={};

  @override void initState(){
    super.initState();
    _history=_readHistory();
    if(_source==ConverterSource.me)_startGps();
  }
  @override void dispose(){_gps?.cancel();_debounce?.cancel();_plainTimer?.cancel();_text.dispose();super.dispose();}

  List<Map<String,dynamic>> _readHistory(){
    try{final v=widget.store?.preference(_historyKey);if(v==null)return [];
      return [for(final e in jsonDecode(v) as List)Map<String,dynamic>.from(e as Map)];}catch(_){return [];}
  }
  void _remember(LatLng p,String label){
    final list=pushHistory(_history,p,label);
    setState(()=>_history=list);
    unawaited(widget.store?.setPreference(_historyKey,jsonEncode(list)));
  }

  Future<void> _startGps() async {
    final loc=widget.location; if(loc==null)return;
    if(!await loc.ensurePermission())return;
    final first=await loc.current();
    if(mounted&&first!=null)setState(()=>_live=LatLng(first.latitude,first.longitude));
    _gps?.cancel();
    _gps=loc.positions().listen((p){if(mounted&&_source==ConverterSource.me)setState(()=>_live=LatLng(p.latitude,p.longitude));},onError:(_){});
  }

  void _setSource(ConverterSource s){
    setState(()=>_source=s);
    if(s==ConverterSource.me){_startGps();}else{_gps?.cancel();_gps=null;}
    if(s==ConverterSource.map){
      final pick=widget.actions.pickOnMap;
      if(pick!=null){final nav=Navigator.of(context);if(nav.canPop())nav.pop();pick();}
    }
  }

  LatLng? get _point=>switch(_source){
    ConverterSource.me=>_live,
    ConverterSource.map||ConverterSource.search=>_picked,
    ConverterSource.input=>parseCoordinates(_text.text),
  };

  String get _label=>switch(_source){
    ConverterSource.me=>S.t('info.myPosition'),
    ConverterSource.map||ConverterSource.search=>_pickedLabel??S.t('nav.point'),
    ConverterSource.input=>_text.text.trim(),
  };

  /// The one field: coordinates typed, else positions found in the text
  /// (links, message), else a place by its name (event, then address).
  void _changed(String q){
    _debounce?.cancel();
    if(q.trim().isEmpty){setState((){_source=widget.location!=null?ConverterSource.me:ConverterSource.input;_results=const [];_found=const [];});
      if(_source==ConverterSource.me)_startGps();return;}
    _gps?.cancel();_gps=null;
    if(parseCoordinates(q)!=null){setState((){_source=ConverterSource.input;_results=const [];_found=const [];});return;}
    final found=findLocations(q);
    if(found.length==1){_useFound(found.first);return;}
    final local=widget.items==null?const <SearchResult>[]:searchLocal(q,widget.items!());
    setState((){_source=ConverterSource.search;_picked=null;_found=found;_results=local;});
    final addr=widget.addresses;
    if(addr==null||q.trim().length<3||q.trim().length>200)return;
    _debounce=Timer(const Duration(milliseconds:400),() async {
      setState(()=>_looking=true);
      try{final r=await addr(q.trim(),_live);if(mounted&&_text.text==q)setState(()=>_results=[...local,...r]);}catch(_){/* offline: local only */}
      if(mounted)setState(()=>_looking=false);
    });
  }

  Future<void> _paste() async {
    final d=await Clipboard.getData(Clipboard.kTextPlain);
    final text=d?.text??'';
    if(text.trim().isEmpty){if(mounted)ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content:Text(S.t('paste.empty'))));return;}
    _text.text=text.trim();
    _changed(_text.text);
  }

  void _useFound(FoundLocation f){
    setState((){_source=ConverterSource.search;_picked=f.point;_pickedLabel=f.excerpt;_results=const [];_found=const [];});
    _remember(f.point,f.excerpt);
    _moveMini(f.point);
  }

  void _pickResult(SearchResult r){
    FocusScope.of(context).unfocus();
    setState((){_source=ConverterSource.search;_picked=r.point;_pickedLabel=r.title;_results=const [];_found=const [];});
    _remember(r.point,r.title);
    _moveMini(r.point);
  }

  void _moveMini(LatLng p){try{_mini.move(p,_mini.camera.zoom);}catch(_){/* not built yet */}}

  void _act(void Function(LatLng)? f){
    final p=_point; if(p==null||f==null)return;
    _remember(p,_label);
    final nav=Navigator.of(context);
    if(nav.canPop())nav.pop();
    f(p);
  }

  /// The mini map was dragged: the point becomes a typed position.
  void _dragged(LatLng p){
    setState((){_source=ConverterSource.input;_text.text=formatDd(p,decimal:'.');_results=const [];_found=const [];});
    _gps?.cancel();_gps=null;
  }

  /// « En clair » follows the pin: « … » while it moves, the answer 0.5 s
  /// after it stops; answers kept per point (~10 m).
  void _followPlain(LatLng? p){
    final describe=widget.describe;
    if(describe==null||p==null)return;
    final key='${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}';
    if(_plainFor!=null&&'${_plainFor!.latitude.toStringAsFixed(4)},${_plainFor!.longitude.toStringAsFixed(4)}'==key)return;
    _plainFor=p;
    if(_plainCache.containsKey(key)){_plainTimer?.cancel();_plain=_plainCache[key];_plainMoving=false;return;}
    _plainMoving=true;
    _plainTimer?.cancel();
    _plainTimer=Timer(plainDelay,() async {
      final text=await describe(p);
      _plainCache[key]=text;
      if(!mounted||_plainFor!=p)return;
      setState((){_plain=text;_plainMoving=false;});
    });
  }

  Widget _field(ThemeData t){
    final q=_text.text.trim();
    final detected=q.isEmpty?null:detectFormat(q);
    return TextField(key:const ValueKey('converter-input'),controller:_text,onChanged:_changed,
      autofocus:widget.initial==null&&widget.location==null,textInputAction:TextInputAction.search,
      decoration:InputDecoration(isDense:true,prefixIcon:const Icon(Icons.search),hintText:S.t('converter.oneField'),
        border:searchInputBorder,
        helperText:detected==null?null:S.t('converter.recognised',{'f':formatLabel(detected)}),
        suffixIcon:Row(mainAxisSize:MainAxisSize.min,children:[
          if(_text.text.isNotEmpty)IconButton(tooltip:S.t('search.clear'),onPressed:(){_text.clear();_changed('');},icon:const Icon(Icons.close)),
          DictationButton(controller:_text,onChanged:()=>_changed(_text.text)),
          IconButton(key:const ValueKey('paste-button'),tooltip:S.t('paste.button'),onPressed:_paste,icon:const Icon(Icons.content_paste)),
        ])));
  }

  Widget _sourceChips(){
    Widget chip(ConverterSource s,IconData icon,String key)=>ChoiceChip(key:ValueKey('src-${s.name}'),avatar:Icon(icon,size:18),
      label:Text(S.t(key)),selected:_source==s,onSelected:(_)=>_setSource(s));
    return Wrap(spacing:8,runSpacing:8,children:[
      if(widget.location!=null)chip(ConverterSource.me,Icons.my_location,'converter.src.me'),
      if(widget.actions.pickOnMap!=null)chip(ConverterSource.map,Icons.touch_app_outlined,'converter.src.map'),
    ]);
  }

  String _formatName(String f)=>switch(f){
    'link'=>S.t('paste.link'),'address'=>S.t('paste.address'),
    _=>formatLabel(CoordFormat.values.firstWhere((c)=>c.name==f,orElse:()=>CoordFormat.dd))};

  List<Widget> _choices(){
    return [
      if(_looking)const Padding(padding:EdgeInsets.only(top:6),child:LinearProgressIndicator()),
      for(final f in _found)ListTile(dense:true,leading:const Icon(Icons.place_outlined),
        title:Text(S.t('paste.read1',{'what':f.excerpt}),maxLines:2,overflow:TextOverflow.ellipsis),
        subtitle:Text('${_formatName(f.format)} · ${formatDd(f.point)}'),onTap:()=>_useFound(f)),
      for(final r in _results.take(8))ListTile(dense:true,leading:const Icon(Icons.place_outlined),title:Text(r.title,maxLines:1,overflow:TextOverflow.ellipsis),
        subtitle:Text([S.t('search.kind.${r.kind.name}'),if(r.subtitle.isNotEmpty)r.subtitle].join(' · '),maxLines:1,overflow:TextOverflow.ellipsis),onTap:()=>_pickResult(r)),
    ];
  }

  Widget _miniMap(LatLng p){
    if(widget.tileUrl.isEmpty)return const SizedBox.shrink();
    return ClipRRect(borderRadius:BorderRadius.circular(14),child:SizedBox(height:180,child:Stack(children:[
      FlutterMap(mapController:_mini,options:MapOptions(initialCenter:p,initialZoom:14,
          onPositionChanged:(camera,gesture){if(gesture)_dragged(camera.center);}),
        children:[TileLayer(urlTemplate:widget.tileUrl,userAgentPackageName:'org.sarcade.app')]),
      const IgnorePointer(child:Center(child:Padding(padding:EdgeInsets.only(bottom:30),child:Icon(Icons.location_on,size:36,color:Colors.red)))),
      Positioned(left:8,bottom:6,child:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),
        decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(8)),
        child:Text(S.t('converter.drag'),style:const TextStyle(color:Colors.white,fontSize:11)))),
    ])));
  }

  /// One action: icon and short label, on one row.
  Widget _action(IconData icon,String label,VoidCallback onTap,{bool main=false,Key? key}){
    final s=Theme.of(context).colorScheme;
    return Padding(padding:const EdgeInsets.only(right:4),child:InkWell(key:key,borderRadius:BorderRadius.circular(12),onTap:onTap,child:SizedBox(width:64,
      child:Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Column(mainAxisSize:MainAxisSize.min,children:[
        CircleAvatar(radius:20,backgroundColor:main?s.primary:s.surfaceContainerHigh,child:Icon(icon,size:20,color:main?s.onPrimary:s.onSurface)),
        const SizedBox(height:4),
        Text(label,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:11,color:s.onSurface)),
      ])))));
  }

  @override
  Widget build(BuildContext context){
    final t=Theme.of(context); final p=_point;
    if(p!=null&&_source!=ConverterSource.input)WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_moveMini(p);});
    _followPlain(p);
    final a=widget.actions;
    final show=a.show??widget.onShow, measure=a.measure??widget.onMeasure;
    const formats=converterFormats;
    String allText()=>[_label,if(_plain!=null)'${S.t('converter.plain')} : $_plain',coordinatesText(p!,formats,mgrsDigits:_mgrsDigits)].where((s)=>s.isNotEmpty).join('\n');
    return Scaffold(
      appBar:LinkedAppBar(title:Text(S.t('converter.screenTitle')),actions:[
        PopupMenuButton<String>(key:const ValueKey('converter-menu'),onSelected:(v){
            if(v=='clear'){setState(()=>_history=[]);unawaited(widget.store?.setPreference(_historyKey,null));}
            if(v.startsWith('mgrs'))setState(()=>_mgrsDigits=int.parse(v.substring(4)));
          },
          itemBuilder:(_)=>[
            for(final d in const [2,3,4,5])CheckedPopupMenuItem(value:'mgrs$d',checked:d==_mgrsDigits,
              child:Text(S.t('converter.mgrsDigits',{'m':const {2:'1 km',3:'100 m',4:'10 m',5:'1 m'}[d]}))),
            if(_history.isNotEmpty)...[const PopupMenuDivider(),PopupMenuItem(value:'clear',child:Text(S.t('converter.historyClear')))],
          ]),
      ]),
      body:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,24),children:[
        _field(t),
        ..._choices(),
        const SizedBox(height:10),
        _sourceChips(),
        if(_source==ConverterSource.me&&_live==null)ListTile(leading:const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)),title:Text(S.t('converter.waitingGps'))),
        if(_source==ConverterSource.map&&_picked==null)ListTile(leading:const Icon(Icons.touch_app_outlined),title:Text(S.t('converter.touchMap'))),
        if(_source==ConverterSource.input&&_text.text.trim().isNotEmpty&&p==null)Padding(padding:const EdgeInsets.only(top:6),
          child:Text(S.t('converter.invalid'),style:TextStyle(color:t.colorScheme.error))),
        const SizedBox(height:12),
        if(p!=null)...[
          _miniMap(p),
          const SizedBox(height:12),
          InfoBlock(title:S.t('info.coordinates'),children:[
            if(widget.describe!=null)InfoRow(key:const ValueKey('coord-plain'),label:S.t('converter.plain'),
              value:_plainMoving?'…':(_plain??'—'),spell:true),
            ...coordinateRows(p,formats,mgrsDigits:_mgrsDigits),
          ]),
          SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
            if(a.message!=null)_action(Icons.send_outlined,S.t('converter.a.message'),(){final text=allText();_act((_)=>a.message!(text));},main:true,key:const ValueKey('converter-message')),
            _action(Icons.copy_all,S.t('converter.a.copyAll'),(){_remember(p,_label);copyText(context,allText());}),
            if(show!=null)_action(Icons.center_focus_strong,S.t('converter.a.show'),()=>_act(show)),
            if(measure!=null)_action(Icons.straighten,S.t('converter.a.measure'),()=>_act(measure)),
            if(a.poi!=null)_action(Icons.add_location_alt_outlined,S.t('converter.a.poi'),()=>_act(a.poi)),
            if(a.order!=null)_action(Icons.flag_outlined,S.t('converter.a.order'),()=>_act(a.order)),
            if(a.bearing!=null)_action(Icons.track_changes,S.t('converter.a.bearing'),()=>_act(a.bearing)),
          ])),
        ],
        if(_history.isNotEmpty)...[
          const SizedBox(height:16),
          Text(S.t('converter.history'),style:t.textTheme.titleSmall),
          for(final h in _history)ListTile(dense:true,contentPadding:EdgeInsets.zero,leading:const Icon(Icons.history),
            title:Text('${h['label']??''}',maxLines:1,overflow:TextOverflow.ellipsis),
            subtitle:Text(formatDd(LatLng((h['lat'] as num).toDouble(),(h['lon'] as num).toDouble()))),
            onTap:()=>setState((){_source=ConverterSource.input;_gps?.cancel();_gps=null;_results=const [];_found=const [];
              _text.text=formatDd(LatLng((h['lat'] as num).toDouble(),(h['lon'] as num).toDouble()),decimal:'.');})),
        ],
      ]),
    );
  }
}
