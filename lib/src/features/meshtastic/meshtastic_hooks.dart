// SPDX-License-Identifier: MPL-2.0
// © SDUBOS Consulting et contributeurs SARCADE

/// What the map (operational_map_page.dart) takes from the Meshtastic
/// module (lot 28): one short line there for each, the logic here.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../lora/lora_battery_view.dart' show meshCorePillToneWithBattery;
import '../lora/lora_link.dart';
import '../tools/tools_page.dart';
import 'meshtastic_link.dart';
import 'meshtastic_page.dart';

export 'meshtastic_link.dart' show MeshtasticLink;
export 'meshtastic_link_card.dart' show MeshtasticReconnectBanner;

/// Outils › Meshtastic, in the Core next to MeshCore (point 1).
ToolItem meshtasticToolItem({required void Function(String id,Widget Function() build) open})=>
  ToolItem(id:'meshtastic',icon:Icons.wifi_tethering,title:S.t('meshtastic.tool'),subtitle:S.t('meshtastic.toolHelp'),
    color:Colors.lightGreen,onTap:()=>open('meshtastic',()=>const MeshtasticPage()));

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
