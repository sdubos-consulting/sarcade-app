/// Choice of the box's companion (lot 21, card « Télécommande : la liste
/// des nœuds ne se ferme pas sans choisir une ligne », validated on 2 Nov
/// 2026, 10 h 45): a window in place of the drop-down list, the same on a
/// phone and a computer: 1) « Annuler » at the top; 2) a search field, as
/// in the list of the nodes of Outils › MeshCore; 3) the node already
/// chosen first, ticked.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../meshcore/meshcore_link.dart' show sortedContacts;
import '../meshcore/meshcore_node_list.dart' show meshCoreNodeMatches;
import '../meshcore/meshcore_page.dart' show meshCoreAge;
import '../meshcore/meshcore_protocol.dart';
import '../../ui/theme.dart' show searchInputBorder;

/// A line of the window: the chosen node first (even if no longer heard),
/// then the others heard most recently first, kept by [query].
List<MeshCoreContact> remoteNodeChoices(List<MeshCoreContact> nodes,{String? selected,String selectedName='',String query=''}){
  final sorted=sortedContacts(nodes);
  MeshCoreContact? chosen;
  if(selected!=null){
    chosen=sorted.where((c)=>meshCorePrefix(c.key)==meshCorePrefix(selected)).firstOrNull
      ??MeshCoreContact(key:selected,type:1,name:selectedName);
  }
  return [
    if(chosen!=null&&meshCoreNodeMatches(chosen,query))chosen,
    for(final c in sorted)if((chosen==null||c.key!=chosen.key)&&meshCoreNodeMatches(c,query))c,
  ];
}

/// Opens the window; the public key of the node chosen, null on « Annuler »
/// (or a touch beside the window).
Future<String?> pickRemoteNode(BuildContext context,{required List<MeshCoreContact> nodes,String? selected,String selectedName=''})=>
  showDialog<String>(context:context,builder:(_)=>RemoteNodePicker(nodes:nodes,selected:selected,selectedName:selectedName));

class RemoteNodePicker extends StatefulWidget {
  final List<MeshCoreContact> nodes;
  final String? selected;
  final String selectedName;
  const RemoteNodePicker({super.key,required this.nodes,this.selected,this.selectedName=''});
  @override State<RemoteNodePicker> createState()=>_RemoteNodePickerState();
}

class _RemoteNodePickerState extends State<RemoteNodePicker> {
  final _ctrl=TextEditingController();

  @override void dispose(){_ctrl.dispose();super.dispose();}

  @override Widget build(BuildContext context){
    final t=Theme.of(context), now=DateTime.now(), query=_ctrl.text;
    final shown=remoteNodeChoices(widget.nodes,selected:widget.selected,selectedName:widget.selectedName,query:query);
    final chosen=widget.selected==null?null:meshCorePrefix(widget.selected!);
    return Dialog(key:const ValueKey('remote-pick'),insetPadding:const EdgeInsets.symmetric(horizontal:16,vertical:24),
      child:ConstrainedBox(constraints:BoxConstraints(maxWidth:480,maxHeight:MediaQuery.sizeOf(context).height*0.8),
        child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Padding(padding:const EdgeInsets.fromLTRB(20,12,8,0),child:Row(children:[
            Expanded(child:Text(S.t('remote.node'),style:t.textTheme.titleMedium)),
            TextButton(key:const ValueKey('remote-pick-cancel'),onPressed:()=>Navigator.pop(context),child:Text(S.t('common.cancel'))),
          ])),
          Padding(padding:const EdgeInsets.fromLTRB(16,8,16,8),child:TextField(key:const ValueKey('remote-pick-find'),controller:_ctrl,
            onChanged:(_)=>setState((){}),textInputAction:TextInputAction.search,
            decoration:InputDecoration(hintText:S.t('mesh.find.hint'),prefixIcon:const Icon(Icons.search),isDense:true,
              border:searchInputBorder,
              suffixIcon:query.isEmpty?null:IconButton(key:const ValueKey('remote-pick-clear'),tooltip:S.t('mesh.find.clear'),
                onPressed:()=>setState(_ctrl.clear),icon:const Icon(Icons.close))))),
          if(shown.isEmpty)Padding(padding:const EdgeInsets.fromLTRB(20,4,20,16),
            child:Text(S.t('mesh.find.none'),key:const ValueKey('remote-pick-none'),style:t.textTheme.bodySmall)),
          Flexible(child:ListView.builder(shrinkWrap:true,padding:const EdgeInsets.only(bottom:8),itemCount:shown.length,itemBuilder:(context,i){
            final c=shown[i], on=chosen!=null&&meshCorePrefix(c.key)==chosen;
            return ListTile(key:ValueKey('remote-pick-${c.shortKey}'),selected:on,
              leading:const Icon(Icons.person_pin_circle_outlined),
              title:Text(c.name.isEmpty?c.shortKey:c.name,overflow:TextOverflow.ellipsis),
              subtitle:Text([c.shortKey,meshCoreAge(c.lastAdvert,now)].join(' · ')),
              trailing:on?Icon(Icons.check,key:const ValueKey('remote-pick-ticked'),color:t.colorScheme.primary):null,
              onTap:()=>Navigator.pop(context,c.key));
          })),
        ])));
  }
}
