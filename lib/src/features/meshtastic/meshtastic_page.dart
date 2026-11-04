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
import 'meshtastic_link.dart';
import 'meshtastic_link_card.dart';
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

class MeshtasticPage extends StatefulWidget {
  const MeshtasticPage({super.key});
  @override State<MeshtasticPage> createState()=>_MeshtasticPageState();
}

class _MeshtasticPageState extends State<MeshtasticPage> {
  final link=MeshtasticLink.instance;
  @override void initState(){super.initState();meshtasticScreensOpen.value++;link.addListener(_changed);unawaited(link.refresh());}
  @override void dispose(){meshtasticScreensOpen.value--;link.removeListener(_changed);super.dispose();}
  void _changed(){if(mounted)setState((){});}

  Widget _metric(String label,String value)=>Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
    SizedBox(width:150,child:Text(label,style:Theme.of(context).textTheme.bodySmall)),Expanded(child:Text(value))]));

  @override Widget build(BuildContext context){
    final t=Theme.of(context), now=DateTime.now();
    final me=link.me;
    return Scaffold(
      appBar:LinkedAppBar(title:Text(S.t('meshtastic.tool')),actions:[
        IconButton(tooltip:S.t('mesh.refresh'),onPressed:link.connected?()=>unawaited(link.refresh()):null,icon:const Icon(Icons.refresh)),
        TextButton.icon(key:const ValueKey('meshtastic-diagnostic'),onPressed:()=>openMeshtasticDiagnostic(context),
          icon:const Icon(Icons.troubleshoot),label:Text(S.t('mesh.diagnostic'))),
      ]),
      body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:760),child:ListView(padding:const EdgeInsets.all(16),children:[
        const MeshtasticReconnectBanner(inScreen:true),
        if(!link.remembered)...[
          Text(S.t('meshtastic.noModule')),
          const MeshtasticLinkCard(),
        ]else Card(key:const ValueKey('meshtastic-module'),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text(me!=null&&me.longName.isNotEmpty?me.longName:link.deviceName??link.deviceId??'',style:t.textTheme.titleMedium),
          for(final (k,v) in meshtasticModuleLines(link,now))_metric(k,v),
          const Padding(padding:EdgeInsets.only(top:10),child:Align(alignment:Alignment.centerLeft,child:MeshtasticConnectButton())),
        ]))),
        if(link.remembered)...[
          // Same thresholds as MeshCore (lot 25): one setting per device.
          const LoraBatteryThresholdsTile(),
          Padding(padding:const EdgeInsets.fromLTRB(4,16,4,6),child:Text(S.t('mesh.nodes',{'n':'${link.others.length}'}),
            key:const ValueKey('meshtastic-nodes-title'),style:t.textTheme.titleSmall)),
          Padding(padding:const EdgeInsets.all(4),child:Text(S.t('mesh.local'),style:t.textTheme.bodySmall)),
        ],
      ]))),
    );
  }
}
