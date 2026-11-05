/// Outils › MeshCore (lot D, card « MeshCore comme transport », 1 Nov
/// 2026): the module, its metrics and the nodes of the MeshCore network it
/// knows (companions, repeaters, room servers, sensors). Core. Lot 17:
/// « Afficher les nœuds sur la carte », and « Écrire » / « Voir sur la
/// carte » on each node.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../../services/location_service.dart';
import '../../ui/link_status.dart';
import '../../ui/overlay_page.dart';
import '../lora/lora_battery_view.dart' show LoraBatteryThresholdsTile;
import '../lora/lora_link.dart';
import '../remotes/remote.dart';
import '../remotes/remotes_page.dart' show openRemotes;
import 'meshcore_banner.dart';
import 'meshcore_chat_page.dart';
import 'meshcore_link.dart';
import 'meshcore_link_card.dart';
import 'meshcore_map.dart';
import 'meshcore_node_list.dart';
import 'meshcore_protocol.dart';

/// « Diagnostic » of Outils › MeshCore: the card of the module (search,
/// choice, state, journal, « Oublier ce module »).
Future<void> openMeshCoreDiagnostic(BuildContext context)=>showOverlayPage<void>(context,(_)=>Scaffold(
  appBar:LinkedAppBar(title:Text('${S.t('mesh.tool')} · ${S.t('mesh.diagnostic')}')),
  body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:760),
    child:ListView(padding:const EdgeInsets.all(16),children:const [MeshCoreLinkCard()])))));

/// « il y a 3 min », « il y a 2 h », « il y a 4 j » (lora/lora_link.dart).
String meshCoreAge(DateTime? at,DateTime now)=>loraAge(at,now);

/// « direct », « 2 sauts », « route inconnue » (lora/lora_link.dart).
String meshCoreHops(int? hops)=>loraHops(hops);

/// Text put in the search field for a node chosen elsewhere (lot 19).
String? meshCoreFocusQuery(MeshCoreContact? c)=>c==null?null:c.name.isEmpty?c.shortKey:c.name;

IconData meshCoreKindIcon(String kind)=>switch(kind){
  'repeater'=>Icons.cell_tower,'room'=>Icons.forum_outlined,'sensor'=>Icons.sensors,_=>Icons.person_pin_circle_outlined};

/// Outils › MeshCore keeps a simple link to Outils › Télécommandes (lot
/// 21): the remotes are a tool of their own, MeshCore one of their
/// transports.
class MeshCoreRemotesTile extends StatelessWidget {
  const MeshCoreRemotesTile({super.key});
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:Remotes.instance,builder:(context,_){
    final all=Remotes.instance.remotes;
    return Card(key:const ValueKey('remote-tile'),child:ListTile(leading:const Icon(Icons.settings_remote),
      title:Text(S.t('remote.title')),
      subtitle:Text(all.isEmpty?S.t('remote.none'):all.map((r)=>r.name).join(' · '),maxLines:2,overflow:TextOverflow.ellipsis),
      trailing:const Icon(Icons.chevron_right),
      onTap:()=>unawaited(openRemotes(context))));
  });
}

class MeshCorePage extends StatefulWidget {
  /// « Voir sur la carte »: the map shows the node (lot 17).
  final void Function(MeshCoreContact)? onShowOnMap;
  /// Opened on this node (search of the map, lot 19): its name already in
  /// the search field of the list.
  final MeshCoreContact? focus;
  const MeshCorePage({super.key,this.onShowOnMap,this.focus});
  @override State<MeshCorePage> createState()=>_MeshCorePageState();
}

class _MeshCorePageState extends State<MeshCorePage> {
  final link=MeshCoreLink.instance;
  LatLng? _me;
  // Lot 25: one bar on this screen, the one above the map hides meanwhile.
  @override void initState(){super.initState();meshCoreScreensOpen.value++;link.addListener(_changed);unawaited(link.refresh());unawaited(_locate());}
  @override void dispose(){meshCoreScreensOpen.value--;link.removeListener(_changed);super.dispose();}
  void _changed(){if(mounted)setState((){});}
  /// My position for « 10 km N » and the order by distance (lot 29.5).
  Future<void> _locate() async {
    final p=await LocationService().current();
    if(p!=null&&mounted)setState(()=>_me=LatLng(p.latitude,p.longitude));
  }

  Widget _metric(String label,String value)=>Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
    SizedBox(width:150,child:Text(label,style:Theme.of(context).textTheme.bodySmall)),Expanded(child:Text(value))]));

  /// The detail of the module, opened from its summary line.
  void _moduleDetail(){
    final now=DateTime.now();
    showModalBottomSheet<void>(context:context,showDragHandle:true,isScrollControlled:true,builder:(c)=>SafeArea(child:ListenableBuilder(listenable:link,
      builder:(c,_)=>ListView(shrinkWrap:true,padding:const EdgeInsets.fromLTRB(16,0,16,16),children:[
        Text(link.info.name??link.deviceName??link.deviceId??'',style:Theme.of(c).textTheme.titleMedium),
        _metric(S.t('mesh.field.state'),meshCoreStateText(link.state)),
        for(final (k,v) in meshCoreLines(link.info))if(k!='name')_metric(S.t('mesh.field.$k'),v),
        if(link.linkRssi!=null)_metric(S.t('mesh.field.link'),'${link.linkRssi} dBm'),
        if(link.connectedSince!=null)_metric(S.t('mesh.field.since'),meshCoreAge(link.connectedSince,now)),
        _metric(S.t('mesh.field.frames'),S.t('mesh.framesValue',{'in':'${link.framesIn}','out':'${link.framesOut}'})),
        if(link.lastFrameAt!=null)_metric(S.t('mesh.field.lastFrame'),meshCoreAge(link.lastFrameAt,now)),
        // Lot 19: « Déconnecter » / « Se connecter ».
        const Padding(padding:EdgeInsets.only(top:10),child:Align(alignment:Alignment.centerLeft,child:MeshCoreConnectButton())),
      ]))));
  }

  /// « FR78 T1000e · connecté · -72 dBm › » on one coloured line.
  Widget _moduleLine(){
    final t=Theme.of(context);
    final ok=link.state==MeshCoreState.connected;
    final color=ok?Colors.green.shade700:switch(link.state){MeshCoreState.none||MeshCoreState.disconnected=>Colors.grey,MeshCoreState.failed||MeshCoreState.unavailable=>Colors.red.shade700,_=>Colors.orange.shade800};
    final text=[link.info.name??link.deviceName??link.deviceId??'',meshCoreStateText(link.state),if(link.linkRssi!=null)'${link.linkRssi} dBm'].join(' · ');
    return Card(key:const ValueKey('mesh-module-line'),elevation:0,color:color.withValues(alpha:0.12),margin:const EdgeInsets.symmetric(vertical:4),
      child:ListTile(dense:true,leading:Icon(Icons.circle,size:12,color:color),
        title:Text(text,maxLines:1,overflow:TextOverflow.ellipsis,style:t.textTheme.bodyMedium?.copyWith(fontWeight:FontWeight.w600)),
        trailing:const Icon(Icons.chevron_right),onTap:_moduleDetail));
  }

  /// One node on two lines (lot 29.5): name, then « type · 10 km N · age »;
  /// the route only when known; message and map as icons.
  Widget _node(MeshCoreContact n,DateTime now){
    final me=_me;
    final rel=me!=null&&n.lat!=null&&n.lon!=null?meshCoreRelative(me.latitude,me.longitude,n.lat!,n.lon!):null;
    return ListTile(key:ValueKey('mesh-node-${n.shortKey}'),dense:true,contentPadding:const EdgeInsets.symmetric(horizontal:4),
      leading:Icon(meshCoreKindIcon(n.kind)),
      title:Text(n.name.isEmpty?n.shortKey:n.name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:15,fontWeight:FontWeight.w600)),
      subtitle:Text([S.t('mesh.kind.${n.kind}'),?rel,if(n.hops!=null)meshCoreHops(n.hops),meshCoreAge(n.lastAdvert,now)].join(' · '),maxLines:1,overflow:TextOverflow.ellipsis),
      trailing:Row(mainAxisSize:MainAxisSize.min,children:[
        if(meshCoreWritable(n))IconButton(key:ValueKey('mesh-write-${n.shortKey}'),tooltip:S.t('mesh.write'),visualDensity:VisualDensity.compact,
          onPressed:()=>unawaited(openMeshCoreChat(context,n.key,n.name)),icon:const Icon(Icons.chat_bubble_outline)),
        if(meshCoreHasPosition(n)&&widget.onShowOnMap!=null)IconButton(key:ValueKey('mesh-see-${n.shortKey}'),tooltip:S.t('mesh.seeOnMap'),visualDensity:VisualDensity.compact,
          onPressed:()=>widget.onShowOnMap!(n),icon:const Icon(Icons.map_outlined)),
      ]),
      onTap:meshCoreHasPosition(n)&&widget.onShowOnMap!=null?()=>widget.onShowOnMap!(n):null);
  }

  @override Widget build(BuildContext context){
    final t=Theme.of(context), now=DateTime.now();
    final nodes=link.contacts;
    final connected=link.state==MeshCoreState.connected;
    return Scaffold(
      appBar:LinkedAppBar(title:Text(S.t('mesh.tool')),actions:[
        // Diagnostic and refresh in the ⋮ (lot 29.5).
        PopupMenuButton<String>(key:const ValueKey('meshcore-menu'),onSelected:(v){
            if(v=='diag')unawaited(openMeshCoreDiagnostic(context));
            if(v=='refresh'&&connected)unawaited(link.refresh());
          },
          itemBuilder:(_)=>[
            PopupMenuItem(key:const ValueKey('meshcore-diagnostic'),value:'diag',child:ListTile(leading:const Icon(Icons.troubleshoot),title:Text(S.t('mesh.diagnostic')))),
            PopupMenuItem(value:'refresh',enabled:connected,child:ListTile(leading:const Icon(Icons.refresh),title:Text(S.t('mesh.refresh')))),
          ]),
      ]),
      body:RefreshIndicator(onRefresh:()async{if(connected)await link.refresh();},child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:760),
        child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.fromLTRB(12,8,12,16),children:[
        // Web (lot 17): the browser waits for a click to join the module.
        const MeshCoreReconnectBanner(inScreen:true),
        // « Télécommandes » left MeshCore: a tool of its own (lot 29.5).
        if(!link.remembered)...[
          Text(S.t('mesh.noModule')),
          const MeshCoreLinkCard(),
        ]else _moduleLine(),
        if(link.remembered)...[
          // Lot 17: the nodes on the map, also under the panel « Carte ».
          SwitchListTile(key:const ValueKey('mesh-show-map'),dense:true,contentPadding:const EdgeInsets.symmetric(horizontal:4),
            title:Text(S.t('mesh.showOnMap')),value:link.showOnMap,onChanged:(v)=>unawaited(link.setShowOnMap(v))),
          // Lot 25: thresholds of the low battery alert.
          const LoraBatteryThresholdsTile(),
          MeshCoreNodeList(nodes:nodes,me:_me,initialQuery:meshCoreFocusQuery(widget.focus),tile:(n)=>_node(n,now)),
          Padding(padding:const EdgeInsets.all(4),child:Text(S.t('mesh.local'),style:t.textTheme.bodySmall)),
        ],
      ]))))),
    );
  }
}
