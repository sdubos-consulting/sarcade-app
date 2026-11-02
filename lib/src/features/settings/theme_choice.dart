/// Thème Jour / Nuit / Automatique, at the top of the « Affichage » tab of
/// « Fond et affichage » on the map (card « Paramètres : supprimer l'onglet
/// Affichage », decision of 1 Nov 2026, 22 h 17). Applied at once; the
/// application keeps the choice on the device ([themeMode] listener).
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../ui/choice_pills.dart';
import '../../ui/theme.dart' show themeMode;

class ThemeChoice extends StatelessWidget {
  const ThemeChoice({super.key});

  @override
  Widget build(BuildContext context)=>ValueListenableBuilder<ThemeMode>(valueListenable:themeMode,
    builder:(context,mode,_)=>Padding(key:const ValueKey('display-theme'),padding:const EdgeInsets.fromLTRB(16,12,16,0),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(S.t('settings.theme'),style:Theme.of(context).textTheme.titleMedium),
        const SizedBox(height:8),
        ChoicePills<ThemeMode>(
          choices:[
            (value:ThemeMode.light,icon:Icons.light_mode_outlined,label:S.t('settings.themeDay')),
            (value:ThemeMode.dark,icon:Icons.dark_mode_outlined,label:S.t('settings.themeNight')),
            (value:ThemeMode.system,icon:Icons.brightness_auto_outlined,label:S.t('settings.themeAuto')),
          ],
          selected:mode,
          onSelected:(v)=>themeMode.value=v,
        ),
        const Divider(height:24),
      ])));
}
