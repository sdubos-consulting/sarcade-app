/// Direct buttons of a screen (card « Afficher sur une TV : boutons directs
/// au lieu du menu ⋮ », choices 1 to 6 validated on 1 Nov 2026, 22 h 15):
/// 1) computer and tablet: filled « Envoyer ma vue », then the pills
///    « Identifier », mode of the screen (Jour → Nuit → Auto, one tap goes
///    to the next) and « Messages » (shown / hidden, seen on the icon);
/// 2) « Retirer le bandeau SOS » in red, only during an SOS;
/// 3) Renommer, Revenir à la vue par défaut, Révoquer stay in ⋮;
/// 4) phone: only « Envoyer ma vue » leaves the menu;
/// 5) the same in Outils › Afficher sur une TV and in « Écrans » of the map.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import 'tv_theme.dart';

/// From this width (tablet, computer) every button is on the line.
const double tvButtonsWideWidth=600;

bool tvButtonsWide(BuildContext context)=>MediaQuery.sizeOf(context).width>=tvButtonsWideWidth;

/// Next mode of a screen: Jour → Nuit → Auto → Jour.
String nextTvTheme(String current)=>switch(current){'day'=>'night','night'=>'auto',_=>'day'};

/// Messages column shown on the screen (shown unless switched off).
bool tvMessagesShown(Map<String,dynamic> d)=>d['messages']!=false;

/// « Retirer le bandeau SOS » on the line: during an SOS, when allowed.
bool tvShowsSosButton(Map<String,dynamic> d)=>d['alert']==true&&d['can_clear_alert']!=false;

/// Actions of the buttons, the same names as the entries of the menus.
abstract final class TvAction {
  static const view='view', identify='identify', theme='theme', messages='messages', sos='sos';
}

/// Actions on the line of a screen; on a phone [wide] is false and only
/// « Envoyer ma vue » is shown.
class TvScreenButtons extends StatelessWidget {
  final Map<String,dynamic> screen;
  final bool wide;
  final ValueChanged<String> onAction;
  const TvScreenButtons({super.key,required this.screen,required this.wide,required this.onAction});

  @override
  Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    final id='${screen['id']}'; final theme=tvThemeOf(screen); final shown=tvMessagesShown(screen);
    return Wrap(spacing:8,runSpacing:6,crossAxisAlignment:WrapCrossAlignment.center,children:[
      FilledButton.icon(key:ValueKey('tvb-view-$id'),onPressed:()=>onAction(TvAction.view),
        icon:const Icon(Icons.cast,size:18),label:Text(S.t('tv.sendView'))),
      if(wide)...[
        ActionChip(key:ValueKey('tvb-identify-$id'),avatar:const Icon(Icons.highlight_alt,size:18),
          label:Text(S.t('tv.identify')),onPressed:()=>onAction(TvAction.identify)),
        ActionChip(key:ValueKey('tvb-theme-$id'),tooltip:S.t('tvb.modeHelp'),
          avatar:Icon(switch(theme){'day'=>Icons.light_mode_outlined,'night'=>Icons.dark_mode_outlined,_=>Icons.brightness_auto_outlined},size:18),
          label:Text(S.t('tvb.mode.$theme')),onPressed:()=>onAction(TvAction.theme)),
        ActionChip(key:ValueKey('tvb-messages-$id'),tooltip:S.t(shown?'tv.messagesHide':'tv.messagesShow'),
          avatar:Icon(shown?Icons.chat_outlined:Icons.speaker_notes_off_outlined,size:18),
          label:Text(S.t('tvb.messages')),onPressed:()=>onAction(TvAction.messages)),
        if(tvShowsSosButton(screen))FilledButton.icon(key:ValueKey('tvb-sos-$id'),
          style:FilledButton.styleFrom(backgroundColor:scheme.error,foregroundColor:scheme.onError),
          onPressed:()=>onAction(TvAction.sos),icon:const Icon(Icons.sos,size:18),label:Text(S.t('tv.clearSos'))),
      ],
    ]);
  }
}
