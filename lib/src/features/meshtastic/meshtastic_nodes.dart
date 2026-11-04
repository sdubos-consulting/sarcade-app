// SPDX-License-Identifier: MPL-2.0
// © SDUBOS Consulting et contributeurs SARCADE

/// Nodes of the Meshtastic network (lot 28, card « Module Meshtastic, sur
/// le modèle de MeshCore », points 2 and 5), as for MeshCore:
/// - the list of Outils › Meshtastic with a search field (long name, short
///   name, id « !a1b2c3d4 », accents and capitals ignored), filters Tous /
///   Clients / Routeurs / Trackers and « Avec position », heard most
///   recently first, the count following the filter;
/// - the « Nœuds Meshtastic » layer of the map (off by default), grey when
///   not heard for 24 h, and the floating card of a node (short and long
///   name, hardware, last heard, SNR, hops, battery, distance);
/// - the nodes in the search of the map.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../../ui/theme.dart' show glass;
import '../lora/lora_link.dart';
import '../map/drawing/geometry.dart' show formatDistance;
import '../search/map_search.dart';
import 'meshtastic_link.dart';
import 'meshtastic_protocol.dart';

/// Kind filter of the list; [all] keeps the sensors too.
enum MeshtasticKindFilter { all, client, router, tracker }

/// The node answers [query]: every word in its long or short name, or the
/// query is the start of its id (« !a1b2 » or « a1b2 »).
bool meshtasticNodeMatches(MeshtasticNode n,String query){
  final q=query.trim();
  if(q.isEmpty)return true;
  final code=q.replaceAll(RegExp(r'\s+'),'').toLowerCase();
  final id=n.id.toLowerCase();
  if(code.isNotEmpty&&(id.startsWith(code)||id.substring(1).startsWith(code)))return true;
  return matchesQuery(q,'${n.longName} ${n.shortName}');
}

/// The nodes kept by the search and the filters, heard most recently first.
List<MeshtasticNode> filterMeshtasticNodes(Iterable<MeshtasticNode> all,{String query='',
    MeshtasticKindFilter kind=MeshtasticKindFilter.all,bool withPosition=false})=>sortedMeshtasticNodes([
  for(final n in all)
    if((kind==MeshtasticKindFilter.all||n.kind==kind.name)&&(!withPosition||n.placed)&&meshtasticNodeMatches(n,query))n]);

/// A node not heard for more than 24 h is drawn grey.
const meshtasticStaleAfter=Duration(hours:24);
bool meshtasticStale(MeshtasticNode n,DateTime now)=>n.lastHeard==null||now.difference(n.lastHeard!)>meshtasticStaleAfter;

IconData meshtasticKindIcon(String kind)=>switch(kind){
  'router'=>Icons.cell_tower,'tracker'=>Icons.gps_fixed,'sensor'=>Icons.sensors,_=>Icons.person};

Color meshtasticKindColor(String kind)=>switch(kind){
  'router'=>const Color(0xFF6A1B9A),'tracker'=>const Color(0xFFEF6C00),'sensor'=>const Color(0xFF455A64),_=>const Color(0xFF2E7D32)};

/// « Client · il y a 3 min · 2 sauts · 82 % » for the list and the search.
String meshtasticNodeSubtitle(MeshtasticNode n,DateTime now)=>[
  S.t('meshtastic.kind.${n.kind}'),
  if(n.shortName.isNotEmpty&&n.shortName!=n.name)n.shortName,
  loraAge(n.lastHeard,now),loraHops(n.hops),
  if(n.battery!=null||n.voltage!=null)meshtasticBatteryText(n.battery,n.voltage,powered:S.t('meshtastic.powered')),
  if(!n.placed)S.t('mesh.noPosition')].join(' · ');

/// Node shown in the floating card (its number), null when closed.
final meshtasticSelected=ValueNotifier<int?>(null);

/// Distance from [from] to the node, null when one has no position.
String? meshtasticDistance(MeshtasticNode n,LatLng? from){
  if(from==null||!n.placed)return null;
  return formatDistance(const Distance().as(LengthUnit.Meter,from,LatLng(n.lat!,n.lon!)));
}

/// Shows a node on the map: the layer on, the map on the node, its card open.
Future<void> meshtasticShowOnMap(MapController map,MeshtasticNode n) async {
  if(!n.placed)return;
  final link=MeshtasticLink.instance;
  if(!link.showOnMap)await link.setShowOnMap(true);
  meshtasticSelected.value=n.num;
  try{map.move(LatLng(n.lat!,n.lon!),math.max(map.camera.zoom,14));}catch(_){/* map not ready */}
}

/// Icon of a node on the map.
Widget meshtasticNodeMarker(MeshtasticNode n,{required DateTime now,bool selected=false,VoidCallback? onTap}){
  final stale=meshtasticStale(n,now);
  final colour=stale?const Color(0xFF9E9E9E):meshtasticKindColor(n.kind);
  return GestureDetector(key:ValueKey('meshtastic-marker-${n.id}'),onTap:onTap,child:Tooltip(message:n.name,
    child:Container(decoration:BoxDecoration(color:Colors.white.withValues(alpha:stale?0.75:0.95),borderRadius:BorderRadius.circular(8),
      border:Border.all(color:selected?const Color(0xFF8E24AA):colour,width:selected?3:2),
      boxShadow:const [BoxShadow(blurRadius:3,color:Colors.black26)]),
      child:Center(child:n.shortName.isEmpty
        ?Icon(meshtasticKindIcon(n.kind),size:18,color:colour)
        :Text(n.shortName,maxLines:1,overflow:TextOverflow.clip,style:TextStyle(fontSize:10,fontWeight:FontWeight.w700,color:colour))))));
}

/// The « Nœuds Meshtastic » layer (a child of the map): the other nodes
/// that give their position.
class MeshtasticNodesLayer extends StatelessWidget {
  const MeshtasticNodesLayer({super.key});
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:Listenable.merge([MeshtasticLink.instance,meshtasticSelected]),builder:(context,_){
    final link=MeshtasticLink.instance;
    if(!link.showOnMap||!link.remembered)return const SizedBox.shrink();
    final now=DateTime.now();
    return MarkerLayer(markers:[for(final n in link.others)if(n.placed)Marker(point:LatLng(n.lat!,n.lon!),width:40,height:28,
      child:meshtasticNodeMarker(n,now:now,selected:meshtasticSelected.value==n.num,onTap:()=>meshtasticSelected.value=n.num))]);
  });
}

/// The floating card of a node.
class MeshtasticNodeCard extends StatelessWidget {
  final MeshtasticNode node;
  final DateTime now;
  final String? distance;
  final VoidCallback onClose;
  /// « Écrire » (messages, lot 28 3/3); null when not offered.
  final VoidCallback? onWrite;
  final VoidCallback? onCenter;
  const MeshtasticNodeCard({super.key,required this.node,required this.now,this.distance,required this.onClose,this.onWrite,this.onCenter});

  @override Widget build(BuildContext context){
    final t=Theme.of(context), small=t.textTheme.bodySmall;
    final stale=meshtasticStale(node,now);
    final hw=meshtasticHardwareName(node.hwModel);
    final battery=meshtasticBatteryText(node.battery,node.voltage,powered:S.t('meshtastic.powered'));
    Widget line(String label,String value)=>Padding(padding:const EdgeInsets.only(top:3),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      SizedBox(width:120,child:Text(label,style:small)),Expanded(child:Text(value))]));
    return Container(key:const ValueKey('meshtastic-card'),width:300,padding:const EdgeInsets.fromLTRB(14,6,6,12),decoration:glass(context,radius:16),
      child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[
          Icon(meshtasticKindIcon(node.kind),color:stale?t.disabledColor:meshtasticKindColor(node.kind)),const SizedBox(width:8),
          Expanded(child:Text(node.name,maxLines:2,overflow:TextOverflow.ellipsis,style:t.textTheme.titleMedium)),
          IconButton(key:const ValueKey('meshtastic-card-close'),tooltip:S.t('common.close'),onPressed:onClose,icon:const Icon(Icons.close)),
        ]),
        if(node.shortName.isNotEmpty)line(S.t('meshtastic.field.shortName'),node.shortName),
        line(S.t('meshtastic.field.id'),node.id),
        line(S.t('mesh.card.kind'),S.t('meshtastic.kind.${node.kind}')),
        if(hw.isNotEmpty)line(S.t('meshtastic.field.model'),hw),
        line(S.t('meshtastic.card.heard'),[loraAge(node.lastHeard,now),if(stale&&node.lastHeard!=null)S.t('mesh.stale')].join(' · ')),
        if(distance!=null)line(S.t('mesh.card.distance'),distance!),
        if(node.snr!=null)line(S.t('mesh.card.snr'),'${node.snr!.toStringAsFixed(1)} dB'),
        line(S.t('mesh.card.hops'),loraHops(node.hops)),
        if(battery.isNotEmpty)line(S.t('meshtastic.field.battery'),battery),
        if(node.viaMqtt)line(S.t('meshtastic.card.via'),'MQTT'),
        if(!node.placed)line(S.t('meshtastic.field.position'),S.t('mesh.noPosition')),
        if(onWrite!=null||onCenter!=null)Padding(padding:const EdgeInsets.only(top:10,right:8),child:Wrap(spacing:8,runSpacing:8,children:[
          if(onWrite!=null)FilledButton.icon(key:const ValueKey('meshtastic-card-write'),onPressed:onWrite,icon:const Icon(Icons.edit_outlined),label:Text(S.t('mesh.write'))),
          if(onCenter!=null)OutlinedButton.icon(key:const ValueKey('meshtastic-card-center'),onPressed:onCenter,icon:const Icon(Icons.center_focus_strong),label:Text(S.t('mesh.center'))),
        ])),
      ]));
  }
}

/// « Écrire » to a node from its card or the list (set by the messages,
/// meshtastic_chat_page.dart); null while they are not there.
void Function(BuildContext context,MeshtasticNode node)? meshtasticWriteTo;

/// The card of the selected node over the map: top left on a large
/// screen, at the bottom on a phone. [me]: my position for the distance,
/// else the one of the module.
class MeshtasticNodeOverlay extends StatelessWidget {
  final MapController map;
  final LatLng? me;
  final bool compact;
  const MeshtasticNodeOverlay({super.key,required this.map,this.me,this.compact=false});

  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:Listenable.merge([MeshtasticLink.instance,meshtasticSelected]),builder:(context,_){
    final selected=meshtasticSelected.value, link=MeshtasticLink.instance;
    final node=selected==null||!link.showOnMap?null:link.node(selected);
    if(node==null)return const SizedBox.shrink();
    final mine=link.me;
    final from=me??(mine!=null&&mine.placed?LatLng(mine.lat!,mine.lon!):null);
    final write=meshtasticWriteTo;
    final card=MeshtasticNodeCard(node:node,now:DateTime.now(),distance:meshtasticDistance(node,from),
      onClose:()=>meshtasticSelected.value=null,
      onWrite:write==null?null:()=>write(context,node),
      onCenter:node.placed?()=>unawaited(meshtasticShowOnMap(map,node)):null);
    if(compact){
      return Positioned(left:8,right:8,bottom:140,child:Align(alignment:Alignment.bottomCenter,
        child:ConstrainedBox(constraints:BoxConstraints(maxHeight:MediaQuery.sizeOf(context).height/3),child:SingleChildScrollView(child:card))));
    }
    return Positioned(left:8,top:64,child:card);
  });
}

/// Title of the list: « Nœuds connus (48) », or « (5 sur 48) » when a
/// search or a filter is on.
String meshtasticNodesTitle({required int shown,required int total,required bool filtered})=>
  filtered?S.t('mesh.find.count',{'n':'$shown','total':'$total'}):S.t('mesh.nodes',{'n':'$total'});

/// The list of the nodes with its search field and its filters; [tile]
/// draws one node.
class MeshtasticNodeList extends StatefulWidget {
  final List<MeshtasticNode> nodes;
  final Widget Function(MeshtasticNode) tile;
  /// Text put in the field at the opening (a node chosen elsewhere).
  final String? initialQuery;
  const MeshtasticNodeList({super.key,required this.nodes,required this.tile,this.initialQuery});
  @override State<MeshtasticNodeList> createState()=>_MeshtasticNodeListState();
}

class _MeshtasticNodeListState extends State<MeshtasticNodeList> {
  late final _ctrl=TextEditingController(text:widget.initialQuery??'');
  MeshtasticKindFilter _kind=MeshtasticKindFilter.all;
  bool _withPosition=false;

  @override void dispose(){_ctrl.dispose();super.dispose();}

  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    final query=_ctrl.text;
    final shown=filterMeshtasticNodes(widget.nodes,query:query,kind:_kind,withPosition:_withPosition);
    final filtered=query.trim().isNotEmpty||_kind!=MeshtasticKindFilter.all||_withPosition;
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.fromLTRB(4,16,4,6),child:Text(meshtasticNodesTitle(shown:shown.length,total:widget.nodes.length,filtered:filtered),
        key:const ValueKey('meshtastic-nodes-title'),style:t.textTheme.titleSmall)),
      if(widget.nodes.isNotEmpty)...[
        Padding(padding:const EdgeInsets.symmetric(horizontal:4),child:TextField(key:const ValueKey('meshtastic-find'),controller:_ctrl,
          onChanged:(_)=>setState((){}),textInputAction:TextInputAction.search,
          decoration:InputDecoration(hintText:S.t('mesh.find.hint'),prefixIcon:const Icon(Icons.search),isDense:true,
            border:const OutlineInputBorder(),
            suffixIcon:query.isEmpty?null:IconButton(key:const ValueKey('meshtastic-find-clear'),tooltip:S.t('mesh.find.clear'),
              onPressed:()=>setState(_ctrl.clear),icon:const Icon(Icons.close))))),
        Padding(padding:const EdgeInsets.fromLTRB(4,8,4,4),child:Wrap(spacing:6,runSpacing:6,children:[
          for(final f in MeshtasticKindFilter.values)ChoiceChip(key:ValueKey('meshtastic-find-${f.name}'),label:Text(S.t('meshtastic.find.${f.name}')),
            selected:_kind==f,onSelected:(_)=>setState(()=>_kind=f)),
          FilterChip(key:const ValueKey('meshtastic-find-position'),label:Text(S.t('mesh.find.withPosition')),
            selected:_withPosition,onSelected:(v)=>setState(()=>_withPosition=v)),
        ])),
      ],
      if(widget.nodes.isEmpty)Padding(padding:const EdgeInsets.all(4),child:Text(S.t('mesh.noNodes'),style:t.textTheme.bodySmall))
      else if(shown.isEmpty)Padding(padding:const EdgeInsets.all(4),child:Text(S.t('mesh.find.none'),key:const ValueKey('meshtastic-find-none'),style:t.textTheme.bodySmall)),
      for(final n in shown)widget.tile(n),
    ]);
  }
}

// --- Search of the map (point 5) ------------------------------------------

/// Prefix of the reference of a Meshtastic node in a search result (the
/// MeshCore nodes use their public key).
const meshtasticSearchRef='meshtastic:';

/// Placeholder point of a node without position (never shown).
const _nowhere=LatLng(0,0);

/// The nodes heard by the module of this device, for the search of the map.
List<Searchable> meshtasticSearchables(Iterable<MeshtasticNode> nodes,DateTime now)=>[
  for(final n in nodes)Searchable(SearchKind.meshNode,n.name,'${n.shortName} ${n.id}',n.placed?LatLng(n.lat!,n.lon!):_nowhere,
    prefix:n.id.substring(1),ref:'$meshtasticSearchRef${n.num}',placed:n.placed,subtitle:'Meshtastic · ${meshtasticNodeSubtitle(n,now)}')];

/// What the map does with a Meshtastic node found: false for every other
/// result. A placed node: shown on the map; else Outils › Meshtastic on it.
bool openMeshtasticFound(SearchResult r,{required MapController map,required void Function(MeshtasticNode) openInTool}){
  final ref=r.ref;
  if(r.kind!=SearchKind.meshNode||ref==null||!ref.startsWith(meshtasticSearchRef))return false;
  final n=MeshtasticLink.instance.node(int.tryParse(ref.substring(meshtasticSearchRef.length))??-1);
  if(n==null)return true;
  if(r.placed&&n.placed){unawaited(meshtasticShowOnMap(map,n));}else{openInTool(n);}
  return true;
}
