/// Menu « Outils » (card « Outils : liste plus compacte, rangée par
/// familles et par module », lot 29.5): compact rows (about 56 px, round
/// icon of 34 px, title, one line of help, chevron, thin line between),
/// grouped by nature: Carte et terrain, Radio et liaisons, one section per
/// module, Suivi de l'opération, Affichage. « Sur le terrain » and « Au PC »
/// are gone; the PCO tools stay hidden for the others (by their caller).
library;

import 'package:flutter/material.dart';

import '../../ui/test_ids.dart';

import '../../l10n/strings.dart';
import '../../ui/link_status.dart';

/// Family of a tool, in the order of the page.
enum ToolGroup { terrain, radio, module, operation, display }

String toolGroupTitle(ToolGroup g)=>S.t(switch(g){
  ToolGroup.terrain=>'tools.group.terrain',ToolGroup.radio=>'tools.group.radio',ToolGroup.module=>'tools.group.adrasec',
  ToolGroup.operation=>'tools.group.operation',ToolGroup.display=>'tools.group.display'});

class ToolItem {
  final IconData icon; final String title, subtitle; final Color color; final VoidCallback onTap; final ToolGroup group;
  /// Test identifier: `tool.<id>` (card B of the cinématique review).
  final String id;
  const ToolItem({required this.icon,required this.title,required this.subtitle,required this.color,required this.onTap,this.group=ToolGroup.terrain,this.id=''});
}

/// Height of a tool row at text scale 1.
const double toolTileHeight=56;

class ToolsPage extends StatelessWidget {
  final List<ToolItem> items;
  /// Left bar (computer, tablet): tools pinned there, and the pin of each
  /// row (card « Barre de gauche personnalisable », 1 Nov 2026).
  final Set<String> pinned; final void Function(String id)? onTogglePin;
  const ToolsPage({super.key,required this.items,this.pinned=const {},this.onTogglePin});

  @override
  Widget build(BuildContext context){
    final t=Theme.of(context);
    Widget row(ToolItem i)=>withId('tool.${i.id}',InkWell(
      // On a phone the page is a screen of its own: it closes first, so
      // that a tool working on the map shows the map.
      onTap:(){final nav=Navigator.of(context);if(nav.canPop())nav.pop();i.onTap();},
      child:ConstrainedBox(constraints:const BoxConstraints(minHeight:toolTileHeight),child:Padding(padding:const EdgeInsets.fromLTRB(16,6,8,6),child:Row(children:[
        Container(width:34,height:34,decoration:BoxDecoration(color:i.color.withValues(alpha:0.14),shape:BoxShape.circle),
          child:Icon(i.icon,size:20,color:i.color)),
        const SizedBox(width:14),
        Expanded(child:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(i.title,maxLines:1,overflow:TextOverflow.ellipsis,style:t.textTheme.bodyLarge?.copyWith(fontWeight:FontWeight.w600)),
          if(i.subtitle.isNotEmpty)Text(i.subtitle,maxLines:1,overflow:TextOverflow.ellipsis,style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant)),
        ])),
        if(onTogglePin!=null&&i.id.isNotEmpty)IconButton(key:ValueKey('pin-${i.id}'),
          tooltip:S.t(pinned.contains(i.id)?'rail.unpin':'rail.pin'),onPressed:()=>onTogglePin!(i.id),
          icon:Icon(pinned.contains(i.id)?Icons.push_pin:Icons.push_pin_outlined,color:pinned.contains(i.id)?t.colorScheme.primary:t.colorScheme.onSurfaceVariant)),
        Icon(Icons.chevron_right,color:t.colorScheme.onSurfaceVariant),
      ])))));
    return Scaffold(
      appBar:LinkedAppBar(title:Text(S.t('tools.title'))),
      body:ListView(padding:const EdgeInsets.only(bottom:16),children:[
        for(final g in ToolGroup.values)
          if(items.any((i)=>i.group==g))...[
            Padding(padding:const EdgeInsets.fromLTRB(16,16,16,4),child:Row(children:[
              if(g==ToolGroup.module)...[Icon(Icons.shield_outlined,size:16,color:t.colorScheme.primary),const SizedBox(width:6)],
              Text(toolGroupTitle(g),style:t.textTheme.titleSmall?.copyWith(color:t.colorScheme.primary,fontWeight:FontWeight.w600)),
            ])),
            for(final (n,i) in [for(final i in items)if(i.group==g)i].indexed)...[
              if(n>0)const Divider(height:1,indent:64),
              row(i),
            ],
          ],
      ]),
    );
  }
}
