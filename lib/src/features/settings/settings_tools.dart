/// Tools that left Paramètres (card « Paramètres : supprimer l'onglet
/// Affichage », moves validated on 1 Nov 2026, 22 h 18): « Main courante »
/// (was in Diagnostic) and the default frequencies of the bearing tool (was
/// in Événement, administrator and ADRASEC module only), both in Outils,
/// group « Au PC ».
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/comm_group.dart' show myRoles;
import '../../modules/adrasec/bearings/signal_defaults_page.dart';
import '../../offline/local_store.dart';
import '../../services/sarcade_api.dart';
import '../logbook/logbook_page.dart';
import '../tools/tools_page.dart';

/// [open] shows a page next to the map (computer) or as a screen (phone).
List<ToolItem> settingsToolItems({required SarcadeApi api,required String eventId,LocalStore? store,required bool adrasec,
    Set<String>? roles,required void Function(String id,Widget Function() build) open}){
  final admin=(roles??myRoles).contains('admin');
  return [
    ToolItem(id:'logbook',icon:Icons.menu_book_outlined,title:S.t('map.logbook'),subtitle:S.t('settings.logbookHelp'),
      color:Colors.brown,group:ToolGroup.pc,onTap:()=>open('logbook',()=>LogbookPage(api:api,eventId:eventId))),
    if(adrasec&&admin)ToolItem(id:'signals',icon:Icons.graphic_eq,title:S.t('signals.title'),subtitle:S.t('signals.rowHelp'),
      color:Colors.red,group:ToolGroup.pc,onTap:()=>open('signals',()=>SignalDefaultsPage(api:api,store:store))),
  ];
}
