/// Modules of the application (lot C, A1, card « Séparer le Core et les
/// modules », 1 Nov 2026). The Core (map, positions, messages, teams,
/// drawings, SOS, offline, TV, routes, weather, files, MeshCore…) is always
/// there; a module brings the functions of one use, enabled per event
/// (``modules`` of the event settings, see ``operations/event_settings.dart``).
///
/// Rule of 1 Nov 2026: what needs a radio amateur licence (APRS, Packet,
/// Winlink) is ADRASEC; MeshCore and Meshtastic stay in the Core.
library;

class AppModule {
  /// Identifier shared with the server (``sarcade.modules``).
  final String id;
  /// Folder of its code, under ``lib/src/modules``.
  final String folder;
  const AppModule(this.id,this.folder);
  String get labelKey=>'modules.$id';
  String get helpKey=>'modules.${id}Help';
}

const appModules=<AppModule>[
  AppModule('adrasec','adrasec'),
];

/// Core files that still put a module on screen (composition points). The
/// test « module boundaries » refuses any other Core file importing a
/// module; this list may only shrink as the map gets its extension points.
const moduleCompositionPoints=<String>{
  'lib/src/features/map/operational_map_page.dart',
  'lib/src/services/sarcade_api.dart',
  'lib/src/features/settings/settings_page.dart',
  'lib/src/features/settings/event_settings_section.dart',
  'lib/src/features/settings/diagnostics_panel.dart',
};
