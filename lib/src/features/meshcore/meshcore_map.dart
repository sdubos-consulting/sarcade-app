/// « Nœuds MeshCore » on the map (lot 17, card « MeshCore : nœuds sur la
/// carte et discussion directe avec un nœud », validated on 1 Nov 2026,
/// 11 h 58): off by default, set in Outils › MeshCore (« Afficher les
/// nœuds sur la carte ») and under Fond et affichage. One icon per kind
/// (companion, repeater, room), grey when the last advert is older than
/// 24 h; a click opens a small floating card (name, kind, last advert,
/// distance, SNR, hops, « Écrire » for a companion, « Centrer »). Only the
/// nodes that publish their position are drawn: the positions are the
/// announced ones, not necessarily the current ones.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../../ui/theme.dart' show glass;
import '../map/drawing/geometry.dart' show formatDistance;
import 'meshcore_chat.dart';
import 'meshcore_chat_page.dart';
import 'meshcore_link.dart';
import 'meshcore_page.dart' show meshCoreAge, meshCoreHops;
import 'meshcore_protocol.dart';

/// A node not heard for more than 24 h is drawn grey.
const meshCoreStaleAfter=Duration(hours:24);
bool meshCoreStale(MeshCoreContact c,DateTime now)=>c.lastAdvert==null||now.difference(c.lastAdvert!)>meshCoreStaleAfter;

/// Only a companion reads private messages (repeaters and rooms do not).
bool meshCoreWritable(MeshCoreContact c)=>c.kind=='companion';

bool meshCoreHasPosition(MeshCoreContact c)=>c.lat!=null&&c.lon!=null;

/// The nodes that can be placed: those publishing their position.
List<MeshCoreContact> meshCoreOnMap(Iterable<MeshCoreContact> all)=>all.where(meshCoreHasPosition).toList();

IconData meshCoreMapIcon(String kind)=>switch(kind){
  'companion'=>Icons.person,'repeater'=>Icons.cell_tower,'room'=>Icons.forum,'sensor'=>Icons.sensors,_=>Icons.hub};

Color meshCoreKindColor(String kind)=>switch(kind){
  'companion'=>const Color(0xFF00838F),'repeater'=>const Color(0xFF6A1B9A),'room'=>const Color(0xFFEF6C00),_=>const Color(0xFF455A64)};

/// Node shown in the floating card (its key), null when closed.
final meshCoreSelected=ValueNotifier<String?>(null);

/// Distance from [from] to the node, or null when one of them has no position.
String? meshCoreDistance(MeshCoreContact c,LatLng? from){
  if(from==null||!meshCoreHasPosition(c))return null;
  return formatDistance(const Distance().as(LengthUnit.Meter,from,LatLng(c.lat!,c.lon!)));
}

/// Shows a node on the map: the layer on, the map on the node, its card open.
Future<void> meshCoreShowOnMap(MapController map,MeshCoreContact c) async {
  if(!meshCoreHasPosition(c))return;
  final link=MeshCoreLink.instance;
  if(!link.showOnMap)await link.setShowOnMap(true);
  meshCoreSelected.value=c.key;
  try{map.move(LatLng(c.lat!,c.lon!),math.max(map.camera.zoom,14));}catch(_){/* map not ready */}
}

/// Icon of a node on the map.
Widget meshCoreNodeMarker(MeshCoreContact c,{required DateTime now,bool selected=false,VoidCallback? onTap}){
  final stale=meshCoreStale(c,now);
  final colour=stale?const Color(0xFF9E9E9E):meshCoreKindColor(c.kind);
  return GestureDetector(key:ValueKey('mesh-marker-${c.shortKey}'),onTap:onTap,child:Tooltip(message:c.name.isEmpty?c.shortKey:c.name,
    child:Container(decoration:BoxDecoration(color:Colors.white.withValues(alpha:stale?0.75:0.95),shape:BoxShape.circle,
      border:Border.all(color:selected?const Color(0xFF8E24AA):colour,width:selected?3:2),
      boxShadow:const [BoxShadow(blurRadius:3,color:Colors.black26)]),
      child:Center(child:Icon(meshCoreMapIcon(c.kind),size:18,color:colour)))));
}

/// The « Nœuds MeshCore » layer (a child of the map).
class MeshCoreNodesLayer extends StatelessWidget {
  const MeshCoreNodesLayer({super.key});
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:Listenable.merge([MeshCoreLink.instance,meshCoreSelected]),builder:(context,_){
    final link=MeshCoreLink.instance;
    if(!link.showOnMap||!link.remembered)return const SizedBox.shrink();
    final now=DateTime.now();
    return MarkerLayer(markers:[for(final c in meshCoreOnMap(link.contacts))Marker(point:LatLng(c.lat!,c.lon!),width:34,height:34,
      child:meshCoreNodeMarker(c,now:now,selected:meshCoreSelected.value==c.key,onTap:()=>meshCoreSelected.value=c.key))]);
  });
}

/// The floating card of a node.
class MeshCoreNodeCard extends StatelessWidget {
  final MeshCoreContact node;
  final DateTime now;
  final String? distance;
  final double? snr;
  final VoidCallback onClose;
  /// Null for a repeater or a room: no « Écrire ».
  final VoidCallback? onWrite;
  /// Null for a node without position.
  final VoidCallback? onCenter;
  const MeshCoreNodeCard({super.key,required this.node,required this.now,this.distance,this.snr,required this.onClose,this.onWrite,this.onCenter});

  @override Widget build(BuildContext context){
    final t=Theme.of(context), small=t.textTheme.bodySmall;
    final stale=meshCoreStale(node,now);
    Widget line(String label,String value)=>Padding(padding:const EdgeInsets.only(top:3),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      SizedBox(width:120,child:Text(label,style:small)),Expanded(child:Text(value))]));
    return Container(key:const ValueKey('mesh-card'),width:300,padding:const EdgeInsets.fromLTRB(14,6,6,12),decoration:glass(context,radius:16),
      child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[
          Icon(meshCoreMapIcon(node.kind),color:stale?t.disabledColor:meshCoreKindColor(node.kind)),const SizedBox(width:8),
          Expanded(child:Text(node.name.isEmpty?node.shortKey:node.name,maxLines:2,overflow:TextOverflow.ellipsis,style:t.textTheme.titleMedium)),
          IconButton(key:const ValueKey('mesh-card-close'),tooltip:S.t('common.close'),onPressed:onClose,icon:const Icon(Icons.close)),
        ]),
        line(S.t('mesh.card.kind'),S.t('mesh.kind.${node.kind}')),
        line(S.t('mesh.card.advert'),[meshCoreAge(node.lastAdvert,now),if(stale&&node.lastAdvert!=null)S.t('mesh.stale')].join(' · ')),
        if(distance!=null)line(S.t('mesh.card.distance'),distance!),
        if(snr!=null)line(S.t('mesh.card.snr'),'${snr!.toStringAsFixed(1)} dB'),
        line(S.t('mesh.card.hops'),meshCoreHops(node.hops)),
        if(!meshCoreHasPosition(node))line(S.t('mesh.field.position'),S.t('mesh.noPosition')),
        if(onWrite!=null||onCenter!=null)Padding(padding:const EdgeInsets.only(top:10,right:8),child:Wrap(spacing:8,runSpacing:8,children:[
          if(onWrite!=null)FilledButton.icon(key:const ValueKey('mesh-card-write'),onPressed:onWrite,icon:const Icon(Icons.edit_outlined),label:Text(S.t('mesh.write'))),
          if(onCenter!=null)OutlinedButton.icon(key:const ValueKey('mesh-card-center'),onPressed:onCenter,icon:const Icon(Icons.center_focus_strong),label:Text(S.t('mesh.center'))),
        ])),
      ]));
  }
}

/// The card of the selected node over the map: top left on a large
/// screen, at the bottom (a third of the screen at most) on a phone.
/// [me]: my position for the distance, else the one of the module.
class MeshCoreNodeOverlay extends StatelessWidget {
  final MapController map;
  final LatLng? me;
  final bool compact;
  const MeshCoreNodeOverlay({super.key,required this.map,this.me,this.compact=false});

  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:Listenable.merge([MeshCoreLink.instance,meshCoreSelected,MeshCoreChats.instance]),builder:(context,_){
    final key=meshCoreSelected.value, link=MeshCoreLink.instance;
    final node=key==null||!link.showOnMap?null:link.contacts.where((c)=>c.key==key).firstOrNull;
    if(node==null)return const SizedBox.shrink();
    final from=me??(link.info.lat==null?null:LatLng(link.info.lat!,link.info.lon!));
    final card=MeshCoreNodeCard(node:node,now:DateTime.now(),distance:meshCoreDistance(node,from),
      snr:MeshCoreChats.instance.snr[meshCorePrefix(node.key)],
      onClose:()=>meshCoreSelected.value=null,
      onWrite:meshCoreWritable(node)?()=>unawaited(openMeshCoreChat(context,node.key,node.name)):null,
      onCenter:meshCoreHasPosition(node)?()=>unawaited(meshCoreShowOnMap(map,node)):null);
    if(compact){
      return Positioned(left:8,right:8,bottom:140,child:Align(alignment:Alignment.bottomCenter,
        child:ConstrainedBox(constraints:BoxConstraints(maxHeight:MediaQuery.sizeOf(context).height/3),child:SingleChildScrollView(child:card))));
    }
    return Positioned(left:8,top:64,child:card);
  });
}
