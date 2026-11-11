/// « Main courante » was a tool of Outils, group « Au PC » (1 Nov 2026,
/// point 6); since 9 Nov 2026 (porteur) it is opened from Paramètres ›
/// Diagnostic only, and [logbookToolItem] is no longer listed. The bearing
/// frequencies (point 7) are a tool of the ADRASEC module:
/// [signalDefaultsToolItem].
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/sarcade_api.dart';
import '../logbook/logbook_page.dart';
import '../tools/tools_page.dart';

/// [open] shows a page next to the map (computer) or as a screen (phone).
ToolItem logbookToolItem({required SarcadeApi api,required String eventId,
    required void Function(String id,Widget Function() build) open})=>
  ToolItem(id:'logbook',icon:Icons.menu_book_outlined,title:S.t('map.logbook'),subtitle:S.t('settings.logbookHelp'),
    color:Colors.brown,group:ToolGroup.operation,onTap:()=>open('logbook',()=>LogbookPage(api:api,eventId:eventId)));
