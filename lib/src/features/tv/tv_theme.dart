/// « Jour / Nuit / Automatique » of one screen (card « Réglages d'un écran »,
/// validated 1 Nov 2026, 8 h 27): kept by the screen, whatever the view
/// sent from a phone in a dark or light theme.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

const tvThemes=['auto','day','night'];

String tvThemeOf(Map<String,dynamic> d)=>tvThemes.contains(d['theme'])?d['theme'] as String:'auto';

/// The choice, or null when cancelled.
Future<String?> chooseTvTheme(BuildContext context,Map<String,dynamic> d)=>showDialog<String>(context:context,
  builder:(c)=>SimpleDialog(key:const ValueKey('tv-theme'),title:Text(S.t('tv.theme')),children:[
    for(final t in tvThemes)ListTile(key:ValueKey('tv-theme-$t'),
      leading:Icon(tvThemeOf(d)==t?Icons.radio_button_checked:Icons.radio_button_unchecked),
      title:Text(S.t('tv.theme.$t')),subtitle:t=='auto'?Text(S.t('tv.theme.autoHelp')):null,
      onTap:()=>Navigator.pop(c,t)),
  ]));
