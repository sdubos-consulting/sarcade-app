/// Search in the list of the nodes of Outils › MeshCore (lot 19, card
/// « MeshCore : champ de recherche dans la liste des nœuds », validated on
/// 1 Nov 2026, 21 h 49): a field « Rechercher un nœud » on the name and the
/// start of the public key (accents and capitals ignored), filters Tous /
/// Compagnons / Relais / Salons and « avec position », the nodes heard most
/// recently first, the count following the filter (« Nœuds connus (5 sur
/// 48) ») and a cross to empty the field.
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../search/map_search.dart' show fold;
import 'meshcore_link.dart' show sortedContacts;
import 'meshcore_protocol.dart';
import '../../ui/theme.dart' show searchInputBorder;

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

/// Order of the list (lot 29.5): distance from me, most recent, name.
enum MeshCoreSort { distance, recent, name }

/// Hidden after this age (card « MeshCore : écran compact », lot 29.5).
const meshCoreHideAfter=Duration(days:30);

/// « Entendus aujourd'hui » (the last 24 h), « Plus anciens » (up to 30 days),
/// and how many older ones are hidden.
({List<MeshCoreContact> today,List<MeshCoreContact> older,int hidden}) meshCoreSections(List<MeshCoreContact> nodes,DateTime now){
  final today=<MeshCoreContact>[], older=<MeshCoreContact>[]; var hidden=0;
  for(final n in nodes){
    final at=n.lastAdvert;
    final age=at==null?null:now.toUtc().difference(at.toUtc());
    if(age!=null&&age<=const Duration(hours:24)){today.add(n);}
    else if(age!=null&&age>meshCoreHideAfter){hidden++;}
    else{older.add(n);}
  }
  return (today:today,older:older,hidden:hidden);
}

/// « 10 km N », « 850 m SO » from my position.
String meshCoreRelative(double fromLat,double fromLon,double lat,double lon){
  const d=Distance();
  final a=LatLng(fromLat,fromLon), b=LatLng(lat,lon);
  final m=d.as(LengthUnit.Meter,a,b);
  final dist=m<1000?'${m.round()} m':m<10000?'${(m/1000).toStringAsFixed(1).replaceAll('.',',')} km':'${(m/1000).round()} km';
  const names=['N','NE','E','SE','S','SO','O','NO'];
  final brg=(d.bearing(a,b)+360)%360;
  return '$dist ${names[((brg/45).round())%8]}';
}

/// Nodes in the chosen order; without my position, distance falls back
/// on the most recent.
List<MeshCoreContact> sortMeshCoreNodes(List<MeshCoreContact> nodes,MeshCoreSort sort,{LatLng? me}){
  final out=[...nodes];
  switch(sort){
    case MeshCoreSort.name: out.sort((a,b)=>fold(a.name).compareTo(fold(b.name)));
    case MeshCoreSort.distance when me!=null:
      const d=Distance(); final from=me;
      double km(MeshCoreContact n)=>n.lat==null||n.lon==null?double.infinity:d.as(LengthUnit.Meter,from,LatLng(n.lat!,n.lon!));
      out.sort((a,b)=>km(a).compareTo(km(b)));
    default: break; // already the most recent first
  }
  return out;
}

/// The list of the nodes with its search field and its filters; [tile]
/// draws one node. Lot 29.5: search and order on one line, filters on one
/// scrolling row, « Entendus aujourd'hui » then « Plus anciens » folded,
/// nodes of more than 30 days hidden.
class MeshCoreNodeList extends StatefulWidget {
  final List<MeshCoreContact> nodes;
  final Widget Function(MeshCoreContact) tile;
  /// Text put in the field at the opening (a node chosen elsewhere).
  final String? initialQuery;
  /// My position, for the order by distance.
  final LatLng? me;
  final DateTime? now;
  const MeshCoreNodeList({super.key,required this.nodes,required this.tile,this.initialQuery,this.me,this.now});
  @override State<MeshCoreNodeList> createState()=>_MeshCoreNodeListState();
}

class _MeshCoreNodeListState extends State<MeshCoreNodeList> {
  late final _ctrl=TextEditingController(text:widget.initialQuery??'');
  MeshCoreKindFilter _kind=MeshCoreKindFilter.all;
  bool _withPosition=false, _olderOpen=false, _showHidden=false;
  MeshCoreSort _sort=MeshCoreSort.distance;
  @override void dispose(){_ctrl.dispose();super.dispose();}

  void _clear()=>setState(_ctrl.clear);

  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    final query=_ctrl.text;
    final shown=sortMeshCoreNodes(filterMeshCoreNodes(widget.nodes,query:query,kind:_kind,withPosition:_withPosition),_sort,me:widget.me);
    final filtered=query.trim().isNotEmpty||_kind!=MeshCoreKindFilter.all||_withPosition;
    final sec=meshCoreSections(shown,widget.now??DateTime.now());
    final olderOpen=_olderOpen||(query.trim().isNotEmpty&&sec.older.isNotEmpty);
    String label(MeshCoreKindFilter f)=>S.t('mesh.find.${f.name}');
    Widget head(String text,{bool? open,VoidCallback? onTap})=>InkWell(onTap:onTap,child:Padding(padding:const EdgeInsets.fromLTRB(4,10,4,2),
      child:Row(children:[Expanded(child:Text(text,style:t.textTheme.labelLarge?.copyWith(color:t.colorScheme.onSurfaceVariant))),
        if(open!=null)Icon(open?Icons.expand_less:Icons.expand_more,size:20,color:t.colorScheme.onSurfaceVariant)])));
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.fromLTRB(4,12,4,6),child:Text(meshCoreNodesTitle(shown:shown.length,total:widget.nodes.length,filtered:filtered),
        key:const ValueKey('mesh-nodes-title'),style:t.textTheme.titleSmall)),
      if(widget.nodes.isNotEmpty)...[
        Padding(padding:const EdgeInsets.symmetric(horizontal:4),child:Row(children:[
          Expanded(child:TextField(key:const ValueKey('mesh-find'),controller:_ctrl,
            onChanged:(_)=>setState((){}),textInputAction:TextInputAction.search,
            decoration:InputDecoration(hintText:S.t('mesh.find.hint'),prefixIcon:const Icon(Icons.search),isDense:true,
              border:searchInputBorder,
              suffixIcon:query.isEmpty?null:IconButton(key:const ValueKey('mesh-find-clear'),tooltip:S.t('mesh.find.clear'),
                onPressed:_clear,icon:const Icon(Icons.close))))),
          PopupMenuButton<MeshCoreSort>(key:const ValueKey('mesh-sort'),tooltip:S.t('mesh.sort'),icon:const Icon(Icons.sort),
            onSelected:(v)=>setState(()=>_sort=v),
            itemBuilder:(_)=>[for(final v in MeshCoreSort.values)CheckedPopupMenuItem(value:v,checked:_sort==v,child:Text(S.t('mesh.sort.${v.name}')))]),
        ])),
        SizedBox(height:44,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.fromLTRB(4,6,4,0),children:[
          for(final f in MeshCoreKindFilter.values)Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(key:ValueKey('mesh-find-${f.name}'),
            label:Text(label(f)),selected:_kind==f,onSelected:(_)=>setState(()=>_kind=f),visualDensity:VisualDensity.compact)),
          FilterChip(key:const ValueKey('mesh-find-position'),label:Text(S.t('mesh.find.withPosition')),
            selected:_withPosition,onSelected:(v)=>setState(()=>_withPosition=v),visualDensity:VisualDensity.compact),
        ])),
      ],
      if(widget.nodes.isEmpty)Padding(padding:const EdgeInsets.all(4),child:Text(S.t('mesh.noNodes'),style:t.textTheme.bodySmall))
      else if(shown.isEmpty)Padding(padding:const EdgeInsets.all(4),child:Text(S.t('mesh.find.none'),key:const ValueKey('mesh-find-none'),style:t.textTheme.bodySmall)),
      if(sec.today.isNotEmpty)...[head(S.t('mesh.section.today',{'n':'${sec.today.length}'})),for(final n in sec.today)widget.tile(n)],
      if(sec.older.isNotEmpty)...[head(S.t('mesh.section.older',{'n':'${sec.older.length}'}),open:olderOpen,onTap:()=>setState(()=>_olderOpen=!_olderOpen)),
        if(olderOpen)for(final n in sec.older)widget.tile(n)],
      if(sec.hidden>0)TextButton(key:const ValueKey('mesh-hidden'),onPressed:()=>setState(()=>_showHidden=!_showHidden),
        child:Text(S.t(_showHidden?'mesh.hiddenLess':'mesh.hiddenMore',{'n':'${sec.hidden}'}))),
      if(_showHidden)for(final n in shown.where((n)=>!sec.today.contains(n)&&!sec.older.contains(n)))widget.tile(n),
    ]);
  }
}
