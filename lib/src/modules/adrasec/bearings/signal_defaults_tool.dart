/// Default frequencies of the bearing tool in Outils, group « Au PC »
/// (administrator, ADRASEC module), no longer in Paramètres › Événement
/// (lot 19, moves validated on 1 Nov 2026, 22 h 18, point 7).
library;

import 'package:flutter/material.dart';

import '../../../features/tools/tools_page.dart';
import '../../../l10n/strings.dart';
import '../../../models/comm_group.dart' show myRoles;
import '../../../offline/local_store.dart';
import '../../../services/sarcade_api.dart';
import 'signal_defaults_page.dart';

/// The tile, or null when this person is not an administrator.
ToolItem? signalDefaultsToolItem({required SarcadeApi api,LocalStore? store,Set<String>? roles,
    required void Function(String id,Widget Function() build) open})=>
  (roles??myRoles).contains('admin')
    ?ToolItem(id:'signals',icon:Icons.graphic_eq,title:S.t('signals.title'),subtitle:S.t('signals.rowHelp'),
      color:Colors.red,group:ToolGroup.pc,onTap:()=>open('signals',()=>SignalDefaultsPage(api:api,store:store)))
    :null;
