/// Search in the list of the nodes of Outils › MeshCore (lot 19, card
/// « MeshCore : champ de recherche dans la liste des nœuds », validated on
/// 1 Nov 2026, 21 h 49): a field « Rechercher un nœud » on the name and the
/// start of the public key (accents and capitals ignored), filters Tous /
/// Compagnons / Relais / Salons and « avec position », the nodes heard most
/// recently first, the count following the filter (« Nœuds connus (5 sur
/// 48) ») and a cross to empty the field.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../search/map_search.dart' show fold;
import 'meshcore_link.dart' show sortedContacts;
import 'meshcore_protocol.dart';

/// Kind filter of the list; [all] keeps the sensors and the other nodes too.
enum MeshCoreKindFilter { all, companion, repeater, room }

/// The node answers [query]: every word in its name, or the query is the
/// start of its public key (spaces ignored).
bool meshCoreNodeMatches(MeshCoreContact c,String query){
  final q=query.trim();
  if(q.isEmpty)return true;
  final key=q.replaceAll(RegExp(r'\s+'),'').toLowerCase();
  if(key.isNotEmpty&&c.key.toLowerCase().startsWith(key))return true;
  final name=fold(c.name);
  final words=fold(q).split(RegExp(r'\s+')).where((w)=>w.isNotEmpty);
  return words.isNotEmpty&&words.every(name.contains);
}

bool meshCoreKindMatches(MeshCoreContact c,MeshCoreKindFilter f)=>f==MeshCoreKindFilter.all||c.kind==f.name;

/// The nodes kept by the search and the filters, heard most recently first.
List<MeshCoreContact> filterMeshCoreNodes(Iterable<MeshCoreContact> all,{String query='',
    MeshCoreKindFilter kind=MeshCoreKindFilter.all,bool withPosition=false})=>sortedContacts([
  for(final c in all)
    if(meshCoreKindMatches(c,kind)&&(!withPosition||(c.lat!=null&&c.lon!=null))&&meshCoreNodeMatches(c,query))c]);

/// Title of the list: « Nœuds connus (48) », or « Nœuds connus (5 sur 48) »
/// when a search or a filter is on.
String meshCoreNodesTitle({required int shown,required int total,required bool filtered})=>
  filtered?S.t('mesh.find.count',{'n':'$shown','total':'$total'}):S.t('mesh.nodes',{'n':'$total'});

/// The list of the nodes with its search field and its filters; [tile]
/// draws one node.
class MeshCoreNodeList extends StatefulWidget {
  final List<MeshCoreContact> nodes;
  final Widget Function(MeshCoreContact) tile;
  /// Text put in the field at the opening (a node chosen elsewhere).
  final String? initialQuery;
  const MeshCoreNodeList({super.key,required this.nodes,required this.tile,this.initialQuery});
  @override State<MeshCoreNodeList> createState()=>_MeshCoreNodeListState();
}

class _MeshCoreNodeListState extends State<MeshCoreNodeList> {
  late final _ctrl=TextEditingController(text:widget.initialQuery??'');
  MeshCoreKindFilter _kind=MeshCoreKindFilter.all;
  bool _withPosition=false;

  @override void dispose(){_ctrl.dispose();super.dispose();}

  void _clear()=>setState(_ctrl.clear);

  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    final query=_ctrl.text;
    final shown=filterMeshCoreNodes(widget.nodes,query:query,kind:_kind,withPosition:_withPosition);
    final filtered=query.trim().isNotEmpty||_kind!=MeshCoreKindFilter.all||_withPosition;
    String label(MeshCoreKindFilter f)=>S.t('mesh.find.${f.name}');
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.fromLTRB(4,16,4,6),child:Text(meshCoreNodesTitle(shown:shown.length,total:widget.nodes.length,filtered:filtered),
        key:const ValueKey('mesh-nodes-title'),style:t.textTheme.titleSmall)),
      if(widget.nodes.isNotEmpty)...[
        Padding(padding:const EdgeInsets.symmetric(horizontal:4),child:TextField(key:const ValueKey('mesh-find'),controller:_ctrl,
          onChanged:(_)=>setState((){}),textInputAction:TextInputAction.search,
          decoration:InputDecoration(hintText:S.t('mesh.find.hint'),prefixIcon:const Icon(Icons.search),isDense:true,
            border:const OutlineInputBorder(),
            suffixIcon:query.isEmpty?null:IconButton(key:const ValueKey('mesh-find-clear'),tooltip:S.t('mesh.find.clear'),
              onPressed:_clear,icon:const Icon(Icons.close))))),
        Padding(padding:const EdgeInsets.fromLTRB(4,8,4,4),child:Wrap(spacing:6,runSpacing:6,children:[
          for(final f in MeshCoreKindFilter.values)ChoiceChip(key:ValueKey('mesh-find-${f.name}'),label:Text(label(f)),
            selected:_kind==f,onSelected:(_)=>setState(()=>_kind=f)),
          FilterChip(key:const ValueKey('mesh-find-position'),label:Text(S.t('mesh.find.withPosition')),
            selected:_withPosition,onSelected:(v)=>setState(()=>_withPosition=v)),
        ])),
      ],
      if(widget.nodes.isEmpty)Padding(padding:const EdgeInsets.all(4),child:Text(S.t('mesh.noNodes'),style:t.textTheme.bodySmall))
      else if(shown.isEmpty)Padding(padding:const EdgeInsets.all(4),child:Text(S.t('mesh.find.none'),key:const ValueKey('mesh-find-none'),style:t.textTheme.bodySmall)),
      for(final n in shown)widget.tile(n),
    ]);
  }
}
