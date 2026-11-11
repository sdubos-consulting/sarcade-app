import 'package:flutter/material.dart';

/// Width and height of the pill around the icon of the chosen tab.
const phoneTabPillWidth=64.0, phoneTabPillHeight=32.0;

/// Colours of the chosen tab, taken from the night blue of the logo (card
/// « Menu du bas : couleur de l'onglet choisi tirée du logo », validated on
/// 9 Nov 2026, choice 1): pale night blue pill and night blue icon by day;
/// night blue pill and white icon by night.
const logoNightBlue=Color(0xFF0A2A55);
({Color pill,Color icon}) phoneTabSelectedColors(Brightness b)=>b==Brightness.light
  ?(pill:const Color(0xFFDCE3EE),icon:logoNightBlue)
  :(pill:const Color(0xFF1C3A66),icon:Colors.white);

/// One button of the phone tab bar (Carte, Messages, Équipes, Outils,
/// Paramètres).
///
/// Card « Menu du bas : surligner seulement l'icône, pas le texte » (validated
/// on 5 Nov 2026), as in Google Maps: the light pill (64 × 32) holds the icon
/// only, the label is below it without background. Chosen tab: icon in the
/// primary blue (porteur, 8 Nov 2026, build 2104), label in the normal text
/// colour (white in dark mode, never blue) and bold; the others grey. Count
/// badges stay on the corner of the icon.
class PhoneTabItem extends StatelessWidget {
  final Widget icon; final String label; final bool selected; final VoidCallback onTap;
  /// Test identifier (`nav.<id>`).
  final String id;
  /// Tooltip and screen reader label, [label] when absent.
  final String? tooltip;
  const PhoneTabItem({super.key,required this.icon,required this.label,required this.selected,required this.onTap,required this.id,this.tooltip});
  @override Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    final color=selected?scheme.onSurface:scheme.onSurfaceVariant;
    final chosen=phoneTabSelectedColors(scheme.brightness);
    final iconColor=selected?chosen.icon:scheme.onSurfaceVariant;
    return Tooltip(message:tooltip??label,excludeFromSemantics:true,child:InkWell(
      onTap:onTap,borderRadius:BorderRadius.circular(28),
      child:Semantics(identifier:'nav.$id',button:true,selected:selected,label:tooltip??label,excludeSemantics:true,child:SizedBox(height:60,
        child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
          // 64 wide, narrower on a small phone (five tabs share the width).
          Container(key:const ValueKey('tab-pill'),width:double.infinity,height:phoneTabPillHeight,
            constraints:const BoxConstraints(maxWidth:phoneTabPillWidth),alignment:Alignment.center,
            decoration:BoxDecoration(color:selected?chosen.pill:null,borderRadius:BorderRadius.circular(phoneTabPillHeight/2)),
            child:IconTheme(data:IconThemeData(color:iconColor),child:icon)),
          const SizedBox(height:4),
          Text(label,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:13,fontWeight:selected?FontWeight.w700:FontWeight.w500,color:color)),
        ])))));
  }
}
