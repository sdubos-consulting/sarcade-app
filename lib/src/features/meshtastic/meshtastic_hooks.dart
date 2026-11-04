// SPDX-License-Identifier: MPL-2.0
// © SDUBOS Consulting et contributeurs SARCADE

/// What the map (operational_map_page.dart) takes from the Meshtastic
/// module (lot 28): one short line there for each, the logic here.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../lora/lora_battery_view.dart' show meshCorePillToneWithBattery;
import '../lora/lora_link.dart';
import '../search/map_search.dart' show Searchable;
import '../tools/tools_page.dart';
import 'meshtastic_link.dart';
import 'meshtastic_nodes.dart';
import 'meshtastic_page.dart';
import 'meshtastic_protocol.dart';

export 'meshtastic_link.dart' show MeshtasticLink;
export 'meshtastic_link_card.dart' show MeshtasticReconnectBanner;
export 'meshtastic_nodes.dart' show MeshtasticNodesLayer, MeshtasticNodeOverlay, meshtasticSelected, meshtasticShowOnMap, openMeshtasticFound;
export 'meshtastic_page.dart' show MeshtasticPage;
export 'meshtastic_protocol.dart' show MeshtasticNode;

/// Outils › Meshtastic, in the Core next to MeshCore (point 1);
/// [onShowOnMap]: « Voir sur la carte » of a node.
ToolItem meshtasticToolItem({required void Function(String id,Widget Function() build) open,void Function(MeshtasticNode)? onShowOnMap})=>
  ToolItem(id:'meshtastic',icon:Icons.wifi_tethering,title:S.t('meshtastic.tool'),subtitle:S.t('meshtastic.toolHelp'),
    color:Colors.lightGreen,onTap:()=>open('meshtastic',()=>MeshtasticPage(onShowOnMap:onShowOnMap)));

/// The nodes heard by the module, in the search of the map (point 5).
List<Searchable> meshtasticMapSearchables(){
  final l=MeshtasticLink.instance;
  return l.remembered?meshtasticSearchables(l.others,DateTime.now()):const [];
}

/// Icon of the module in the link pill: 'ok', 'wait', 'bad', 'off',
/// 'battery' (low battery, lot 25); null when no module is remembered.
String? meshtasticPillTone([MeshtasticLink? link]){
  final l=link??MeshtasticLink.instance;
  return l.remembered?meshCorePillToneWithBattery(loraPillTone(l.state),l.deviceId):null;
}

/// Line of the tooltip of the pill: « Module Meshtastic : connecté ».
String? meshtasticPillTooltip([MeshtasticLink? link]){
  final l=link??MeshtasticLink.instance;
  return l.remembered?S.t('meshtastic.pill',{'s':loraStateText(l.state)}):null;
}
