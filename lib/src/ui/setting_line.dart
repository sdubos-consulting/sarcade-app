/// Compact lines of the Paramètres tabs (cards « Paramètres › Général,
/// Événement, Profil, Notifications : onglet compact », validated on
/// 5 Nov 2026; rule « lignes avec chevron » of lot 29.4).
///
/// - [SettingsSectionTitle]: small coloured title of a section
///   (« Connexion », « Cet appareil », « Batterie »).
/// - [SettingLine]: one setting on one line, entirely touchable: title, a
///   help line in small under it (in place of the ⓘ), the value on the
///   right (never cut: it wraps), then a chevron « › », or a control on
///   the line (switch) with [trailing].
/// - [SettingPill]: small coloured label for a state (« Brouillon »),
///   used as a value or in a list.
library;

import 'package:flutter/material.dart';

class SettingsSectionTitle extends StatelessWidget {
  final String title;
  const SettingsSectionTitle(this.title,{super.key});
  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    return Semantics(header:true,child:Padding(padding:const EdgeInsets.fromLTRB(4,14,0,2),
      child:Text(title,style:t.textTheme.labelLarge?.copyWith(color:t.colorScheme.primary,fontWeight:FontWeight.w600))));
  }
}

class SettingLine extends StatelessWidget {
  final String title;
  /// Small grey line under the title. With [onHelpTap] it is a link of its
  /// own (« Connecté : … › Profil » under « Serveur »).
  final String? help;
  final VoidCallback? onHelpTap;
  final Key? helpKey;
  /// Value on the right: a text ([value]) or a widget ([valueWidget]).
  final String? value;
  final Widget? valueWidget;
  /// Control on the line (switch); no chevron then.
  final Widget? trailing;
  final VoidCallback? onTap;
  const SettingLine({super.key,required this.title,this.help,this.onHelpTap,this.helpKey,this.value,this.valueWidget,this.trailing,this.onTap});

  @override Widget build(BuildContext context){
    final t=Theme.of(context); final s=t.colorScheme;
    final helpStyle=t.textTheme.bodySmall?.copyWith(color:onHelpTap!=null?s.primary:s.onSurfaceVariant);
    Widget? helpLine;
    if(help!=null&&help!.isNotEmpty){
      helpLine=Text(help!,style:helpStyle);
      if(onHelpTap!=null){
        helpLine=InkWell(key:helpKey,onTap:onHelpTap,borderRadius:BorderRadius.circular(4),
          child:Padding(padding:const EdgeInsets.symmetric(vertical:4),child:helpLine));
      }else if(helpKey!=null){
        helpLine=KeyedSubtree(key:helpKey,child:helpLine);
      }
    }
    final shown=valueWidget??(value==null||value!.isEmpty?null
      :Text(value!,textAlign:TextAlign.end,softWrap:true,style:t.textTheme.bodyMedium?.copyWith(color:s.onSurfaceVariant)));
    final line=ConstrainedBox(constraints:const BoxConstraints(minHeight:48),child:Padding(
      padding:const EdgeInsets.fromLTRB(4,6,0,6),child:LayoutBuilder(builder:(context,box)=>Row(children:[
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
          Text(title,style:t.textTheme.bodyLarge),
          ?helpLine,
        ])),
        if(shown!=null)...[const SizedBox(width:12),
          // Never cut (« aucun texte tronqué »): at most half of the line,
          // on several lines if needed; a short value takes only its width,
          // so the title keeps the rest (9 Nov 2026, « Stations anciennes
          // après » on three lines beside « 2 h »).
          ConstrainedBox(constraints:BoxConstraints(maxWidth:box.maxWidth/2),child:shown)],
        if(trailing!=null)...[const SizedBox(width:8),trailing!]
        else if(onTap!=null)Icon(Icons.chevron_right,color:s.onSurfaceVariant),
      ]))));
    return onTap==null?line:InkWell(onTap:onTap,child:line);
  }
}

class SettingPill extends StatelessWidget {
  final String text; final Color? color;
  const SettingPill(this.text,{super.key,this.color});
  @override Widget build(BuildContext context){
    final t=Theme.of(context); final c=color??t.colorScheme.secondary;
    return Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),
      decoration:BoxDecoration(color:c.withValues(alpha:0.14),borderRadius:BorderRadius.circular(10)),
      child:Text(text,style:t.textTheme.labelSmall?.copyWith(color:c,fontWeight:FontWeight.w600)));
  }
}
