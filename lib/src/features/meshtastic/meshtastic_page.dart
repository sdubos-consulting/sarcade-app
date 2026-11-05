// SPDX-License-Identifier: MPL-2.0
// © SDUBOS Consulting et contributeurs SARCADE

/// Outils › Meshtastic (lot 28, card « Module Meshtastic, sur le modèle de
/// MeshCore », point 1): the module, its diagnostic (name, model,
/// firmware, LoRa region and preset, battery, channel) and the nodes of the
/// Meshtastic network it knows. Core, like MeshCore.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../ui/link_status.dart';
import '../../ui/overlay_page.dart';
import '../lora/lora_battery_view.dart' show LoraBatteryThresholdsTile;
import '../lora/lora_link.dart';
import 'meshtastic_chat_page.dart';
import 'meshtastic_link.dart';
import 'meshtastic_link_card.dart';
import 'meshtastic_nodes.dart';
import 'meshtastic_protocol.dart';

/// « Diagnostic » of Outils › Meshtastic: the card of the module (search,
/// choice, state, journal, « Oublier ce module »).
Future<void> openMeshtasticDiagnostic(BuildContext context)=>showOverlayPage<void>(context,(_)=>Scaffold(
  appBar:LinkedAppBar(title:Text('${S.t('meshtastic.tool')} · ${S.t('mesh.diagnostic')}')),
  body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:760),
    child:ListView(padding:const EdgeInsets.all(16),children:const [MeshtasticLinkCard()])))));

/// Lines of the module in Outils › Meshtastic, label already translated.
List<(String,String)> meshtasticModuleLines(MeshtasticLink link,DateTime now)=>[
  (S.t('mesh.field.state'),loraStateText(link.state)),
  for(final (k,v) in meshtasticLines(link.info,link.me,powered:S.t('meshtastic.powered')))if(k!='name')(S.t('meshtastic.field.$k'),v),
  if(link.linkRssi!=null)(S.t('mesh.field.link'),'${link.linkRssi} dBm'),
  if(link.connectedSince!=null)(S.t('mesh.field.since'),loraAge(link.connectedSince,now)),
  (S.t('mesh.field.frames'),S.t('mesh.framesValue',{'in':'${link.framesIn}','out':'${link.framesOut}'})),
  if(link.lastFrameAt!=null)(S.t('mesh.field.lastFrame'),loraAge(link.lastFrameAt,now)),
];

/// Text put in the search field for a node chosen elsewhere.
String? meshtasticFocusQuery(MeshtasticNode? n)=>n?.name;

class MeshtasticPage extends StatefulWidget {
  /// « Voir sur la carte »: the map shows the node (point 2).
  final void Function(MeshtasticNode)? onShowOnMap;
  /// Opened on this node (search of the map, point 5).
  final MeshtasticNode? focus;
  const MeshtasticPage({super.key,this.onShowOnMap,this.focus});
  @override State<MeshtasticPage> createState()=>_MeshtasticPageState();
}

class _MeshtasticPageState extends State<MeshtasticPage> {
  final link=MeshtasticLink.instance;
  @override void initState(){super.initState();meshtasticScreensOpen.value++;link.addListener(_changed);unawaited(link.refresh());}
  @override void dispose(){meshtasticScreensOpen.value--;link.removeListener(_changed);super.dispose();}
  void _changed(){if(mounted)setState((){});}

  Widget _metric(String label,String value)=>Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
    SizedBox(width:150,child:Text(label,style:Theme.of(context).textTheme.bodySmall)),Expanded(child:Text(value))]));

  /// The module on one coloured line (card « MeshCore (et Meshtastic) :
  /// écran compact », lot 29.5); its detail in a sheet.
  Widget _moduleLine(){
    final t=Theme.of(context); final me=link.me;
    final ok=link.connected;
    final color=ok?Colors.green.shade700:switch(link.state){LoraLinkState.none||LoraLinkState.disconnected=>Colors.grey,
      LoraLinkState.failed||LoraLinkState.unavailable=>Colors.red.shade700,_=>Colors.orange.shade800};
    final name=me!=null&&me.longName.isNotEmpty?me.longName:link.deviceName??link.deviceId??'';
    return Card(key:const ValueKey('meshtastic-module'),elevation:0,color:color.withValues(alpha:0.12),margin:const EdgeInsets.symmetric(vertical:4),
      child:ListTile(dense:true,leading:Icon(Icons.circle,size:12,color:color),
        title:Text([name,loraStateText(link.state),if(link.linkRssi!=null)'${link.linkRssi} dBm'].join(' · '),maxLines:1,overflow:TextOverflow.ellipsis,
          style:t.textTheme.bodyMedium?.copyWith(fontWeight:FontWeight.w600)),
        trailing:const Icon(Icons.chevron_right),onTap:_moduleDetail));
  }

  void _moduleDetail(){
    showModalBottomSheet<void>(context:context,showDragHandle:true,isScrollControlled:true,builder:(c)=>SafeArea(child:ListenableBuilder(listenable:link,
      builder:(c,_){final me=link.me;final now=DateTime.now();
        return ListView(shrinkWrap:true,padding:const EdgeInsets.fromLTRB(16,0,16,16),children:[
        Text(me!=null&&me.longName.isNotEmpty?me.longName:link.deviceName??link.deviceId??'',style:Theme.of(c).textTheme.titleMedium),
        for(final (k,v) in meshtasticModuleLines(link,now))_metric(k,v),
        const Padding(padding:EdgeInsets.only(top:10),child:Align(alignment:Alignment.centerLeft,child:MeshtasticConnectButton())),
      ]);})));
  }

  @override Widget build(BuildContext context){
    final t=Theme.of(context), now=DateTime.now();
    return Scaffold(
      appBar:LinkedAppBar(title:Text(S.t('meshtastic.tool')),actions:[
        // Diagnostic and refresh in the ⋮ (lot 29.5).
        PopupMenuButton<String>(key:const ValueKey('meshtastic-menu'),onSelected:(v){
            if(v=='diag')unawaited(openMeshtasticDiagnostic(context));
            if(v=='refresh'&&link.connected)unawaited(link.refresh());
          },
          itemBuilder:(_)=>[
            PopupMenuItem(key:const ValueKey('meshtastic-diagnostic'),value:'diag',child:ListTile(leading:const Icon(Icons.troubleshoot),title:Text(S.t('mesh.diagnostic')))),
            PopupMenuItem(value:'refresh',enabled:link.connected,child:ListTile(leading:const Icon(Icons.refresh),title:Text(S.t('mesh.refresh')))),
          ]),
      ]),
      body:RefreshIndicator(onRefresh:()async{if(link.connected)await link.refresh();},child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:760),
        child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.fromLTRB(12,8,12,16),children:[
        const MeshtasticReconnectBanner(inScreen:true),
        if(!link.remembered)...[
          Text(S.t('meshtastic.noModule')),
          const MeshtasticLinkCard(),
        ]else _moduleLine(),
        if(link.remembered)...[
          // Same thresholds as MeshCore (lot 25): one setting per device.
          const LoraBatteryThresholdsTile(),
          // Point 3: the primary channel.
          ListTile(key:const ValueKey('meshtastic-channel'),dense:true,contentPadding:const EdgeInsets.symmetric(horizontal:4),leading:const Icon(Icons.groups_outlined),
            title:Text(S.t('meshtastic.channel')),subtitle:link.channelName==null?null:Text(link.channelName!),
            trailing:const Icon(Icons.chevron_right),onTap:()=>unawaited(openMeshtasticChannel(context))),
          // Point 2: the nodes on the map, also under the panel « Carte ».
          SwitchListTile(key:const ValueKey('meshtastic-show-map'),dense:true,contentPadding:const EdgeInsets.symmetric(horizontal:4),
            title:Text(S.t('mesh.showOnMap')),value:link.showOnMap,onChanged:(v)=>unawaited(link.setShowOnMap(v))),
          MeshtasticNodeList(nodes:link.others,initialQuery:meshtasticFocusQuery(widget.focus),tile:(n)=>ListTile(key:ValueKey('meshtastic-node-${n.id}'),
            dense:true,contentPadding:const EdgeInsets.symmetric(horizontal:4),
            leading:Icon(meshtasticKindIcon(n.kind)),
            title:Text(n.name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:15,fontWeight:FontWeight.w600)),
            subtitle:Text(meshtasticNodeSubtitle(n,now),maxLines:1,overflow:TextOverflow.ellipsis),
            trailing:Row(mainAxisSize:MainAxisSize.min,children:[
              IconButton(key:ValueKey('meshtastic-write-${n.id}'),tooltip:S.t('mesh.write'),visualDensity:VisualDensity.compact,
                onPressed:()=>unawaited(openMeshtasticNodeChat(context,n)),icon:const Icon(Icons.chat_bubble_outline)),
              if(n.placed&&widget.onShowOnMap!=null)IconButton(key:ValueKey('meshtastic-see-${n.id}'),tooltip:S.t('mesh.seeOnMap'),visualDensity:VisualDensity.compact,
                onPressed:()=>widget.onShowOnMap!(n),icon:const Icon(Icons.map_outlined)),
            ]),
            onTap:n.placed&&widget.onShowOnMap!=null?()=>widget.onShowOnMap!(n):null)),
          Padding(padding:const EdgeInsets.all(4),child:Text(S.t('mesh.local'),style:t.textTheme.bodySmall)),
        ],
      ]))))),
    );
  }
}
