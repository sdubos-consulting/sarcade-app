/// Outils › MeshCore (lot D, card « MeshCore comme transport », 1 Nov
/// 2026): the module, its metrics and the nodes of the MeshCore network it
/// knows (companions, repeaters, room servers, sensors). Core. Lot 17:
/// « Afficher les nœuds sur la carte », and « Écrire » / « Voir sur la
/// carte » on each node.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../ui/link_status.dart';
import '../../ui/overlay_page.dart';
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

/// « il y a 3 min », « il y a 2 h », « il y a 4 j ».
String meshCoreAge(DateTime? at,DateTime now){
  if(at==null)return S.t('mesh.never');
  final d=now.difference(at);
  if(d.inMinutes<1)return S.t('mesh.ageNow');
  if(d.inHours<1)return S.t('mesh.ageMin',{'n':'${d.inMinutes}'});
  if(d.inDays<1)return S.t('mesh.ageHour',{'n':'${d.inHours}'});
  return S.t('mesh.ageDay',{'n':'${d.inDays}'});
}

/// « direct », « 2 sauts », « route inconnue ».
String meshCoreHops(int? hops)=>hops==null?S.t('mesh.hopsUnknown'):hops==0?S.t('mesh.hopsDirect'):S.t('mesh.hops',{'n':'$hops'});

IconData meshCoreKindIcon(String kind)=>switch(kind){
  'repeater'=>Icons.cell_tower,'room'=>Icons.forum_outlined,'sensor'=>Icons.sensors,_=>Icons.person_pin_circle_outlined};

class MeshCorePage extends StatefulWidget {
  /// « Voir sur la carte »: the map shows the node (lot 17).
  final void Function(MeshCoreContact)? onShowOnMap;
  const MeshCorePage({super.key,this.onShowOnMap});
  @override State<MeshCorePage> createState()=>_MeshCorePageState();
}

class _MeshCorePageState extends State<MeshCorePage> {
  final link=MeshCoreLink.instance;
  @override void initState(){super.initState();link.addListener(_changed);unawaited(link.refresh());}
  @override void dispose(){link.removeListener(_changed);super.dispose();}
  void _changed(){if(mounted)setState((){});}

  Widget _metric(String label,String value)=>Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
    SizedBox(width:150,child:Text(label,style:Theme.of(context).textTheme.bodySmall)),Expanded(child:Text(value))]));

  @override Widget build(BuildContext context){
    final t=Theme.of(context), now=DateTime.now();
    final nodes=link.contacts;
    return Scaffold(
      appBar:LinkedAppBar(title:Text(S.t('mesh.tool')),actions:[
        IconButton(tooltip:S.t('mesh.refresh'),onPressed:link.state==MeshCoreState.connected?()=>unawaited(link.refresh()):null,icon:const Icon(Icons.refresh)),
        // Everything about the module in one place (1 Nov 2026, 8 h 17):
        // search, choose, journal, forget.
        TextButton.icon(key:const ValueKey('meshcore-diagnostic'),onPressed:()=>openMeshCoreDiagnostic(context),
          icon:const Icon(Icons.troubleshoot),label:Text(S.t('mesh.diagnostic'))),
      ]),
      body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:760),child:ListView(padding:const EdgeInsets.all(16),children:[
        // Web (lot 17): the browser waits for a click to join the module.
        const MeshCoreReconnectBanner(),
        if(!link.remembered)...[
          Text(S.t('mesh.noModule')),
          const MeshCoreLinkCard(),
        ]else Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text(link.info.name??link.deviceName??link.deviceId??'',style:t.textTheme.titleMedium),
          _metric(S.t('mesh.field.state'),meshCoreStateText(link.state)),
          for(final (k,v) in meshCoreLines(link.info))if(k!='name')_metric(S.t('mesh.field.$k'),v),
          if(link.linkRssi!=null)_metric(S.t('mesh.field.link'),'${link.linkRssi} dBm'),
          if(link.connectedSince!=null)_metric(S.t('mesh.field.since'),meshCoreAge(link.connectedSince,now)),
          _metric(S.t('mesh.field.frames'),S.t('mesh.framesValue',{'in':'${link.framesIn}','out':'${link.framesOut}'})),
          if(link.lastFrameAt!=null)_metric(S.t('mesh.field.lastFrame'),meshCoreAge(link.lastFrameAt,now)),
          // Lot 19: « Déconnecter » / « Se connecter ».
          const Padding(padding:EdgeInsets.only(top:10),child:Align(alignment:Alignment.centerLeft,child:MeshCoreConnectButton())),
        ]))),
        if(link.remembered)...[
          // Lot 17: the nodes on the map, also under Fond et affichage.
          SwitchListTile(key:const ValueKey('mesh-show-map'),contentPadding:const EdgeInsets.symmetric(horizontal:4),
            title:Text(S.t('mesh.showOnMap')),value:link.showOnMap,onChanged:(v)=>unawaited(link.setShowOnMap(v))),
          // Lot 19: search field and filters above the nodes.
          MeshCoreNodeList(nodes:nodes,tile:(n)=>ListTile(key:ValueKey('mesh-node-${n.shortKey}'),contentPadding:const EdgeInsets.symmetric(horizontal:4),
            leading:Icon(meshCoreKindIcon(n.kind)),
            title:Text(n.name.isEmpty?n.shortKey:n.name),
            subtitle:Text([S.t('mesh.kind.${n.kind}'),meshCoreHops(n.hops),meshCoreAge(n.lastAdvert,now),
              n.lat!=null?'${n.lat!.toStringAsFixed(4)}, ${n.lon!.toStringAsFixed(4)}':S.t('mesh.noPosition')].join(' · ')),
            trailing:Row(mainAxisSize:MainAxisSize.min,children:[
              if(meshCoreWritable(n))TextButton(key:ValueKey('mesh-write-${n.shortKey}'),
                onPressed:()=>unawaited(openMeshCoreChat(context,n.key,n.name)),child:Text(S.t('mesh.write'))),
              if(meshCoreHasPosition(n)&&widget.onShowOnMap!=null)TextButton(key:ValueKey('mesh-see-${n.shortKey}'),
                onPressed:()=>widget.onShowOnMap!(n),child:Text(S.t('mesh.seeOnMap'))),
            ]))),
          Padding(padding:const EdgeInsets.all(4),child:Text(S.t('mesh.local'),style:t.textTheme.bodySmall)),
        ],
      ]))),
    );
  }
}
