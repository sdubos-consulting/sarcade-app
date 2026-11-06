/// Reactions on a message (lot 29, group 7): 👍 ❤️ 😂 😮 😢 🙏, one per
/// person and message, changed or removed by its author; never on a
/// distress message, an order or a deleted message. Not an acknowledgement:
/// « Reçu », « Lu »… stay apart.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../offline/local_store.dart';
import 'message_deletion.dart';

const reactionEmojis=['👍','❤️','😂','😮','😢','🙏'];

bool canReact(SarcadeMessage m)=>!m.deleted&&!keptForEveryone(m);

String reactionsKey(String eventId)=>'reactions:$eventId';

/// message id → person → emoji.
typedef ReactionMap=Map<String,Map<String,String>>;

ReactionMap parseReactions(String? v){
  if(v==null||v.isEmpty)return {};
  try{
    final j=jsonDecode(v);
    if(j is! Map)return {};
    return {for(final e in j.entries)if(e.value is Map)'${e.key}':{for(final r in (e.value as Map).entries)'${r.key}':'${r.value}'}};
  }catch(_){return {};}
}

/// One change, from the server (« reaction.updated », the synchronisation)
/// or from this device; `emoji` null removes it.
ReactionMap applyReaction(ReactionMap all,Map data){
  final mid='${data['message_id']??''}'; final actor='${data['actor_id']??''}';
  if(mid.isEmpty||actor.isEmpty)return all;
  final out={for(final e in all.entries)e.key:{...e.value}};
  final emoji=data['emoji'];
  final of=out.putIfAbsent(mid,()=>{});
  if(emoji is String&&reactionEmojis.contains(emoji)){of[actor]=emoji;}else{of.remove(actor);}
  if(of.isEmpty)out.remove(mid);
  return out;
}

/// Counts in the order of [reactionEmojis], for the chips under a bubble.
List<({String emoji,int count,bool mine})> reactionCounts(Map<String,String>? of,String me){
  if(of==null||of.isEmpty)return const [];
  return [for(final e in reactionEmojis)
    if(of.values.contains(e))(emoji:e,count:of.values.where((x)=>x==e).length,mine:of[me]==e)];
}

/// Touching the emoji already chosen removes it.
String? nextReaction(String? mine,String picked)=>mine==picked?null:picked;

/// Reactions of the event kept on this device, so they show offline.
class Reactions extends ValueNotifier<ReactionMap>{
  Reactions._():super({});
  static final instance=Reactions._();
  String? _event;

  void load(LocalStore store,String eventId){
    if(_event==eventId)return;
    _event=eventId; value=parseReactions(store.preference(reactionsKey(eventId)));
  }

  Future<void> apply(LocalStore store,String eventId,Map data) async {
    load(store,eventId);
    value=applyReaction(value,data);
    await store.setPreference(reactionsKey(eventId),value.isEmpty?null:jsonEncode(value));
  }

  /// The whole list from the server (device back online).
  Future<void> replace(LocalStore store,String eventId,List<Map> rows) async {
    ReactionMap all={};
    for(final r in rows){all=applyReaction(all,r);}
    _event=eventId; value=all;
    await store.setPreference(reactionsKey(eventId),all.isEmpty?null:jsonEncode(all));
  }
}

/// Chips under a bubble: « 👍 2 », mine outlined.
class ReactionChips extends StatelessWidget{
  final Map<String,String>? of; final String me; final VoidCallback? onTap;
  const ReactionChips({super.key,required this.of,required this.me,this.onTap});
  @override
  Widget build(BuildContext context){
    final counts=reactionCounts(of,me);
    if(counts.isEmpty)return const SizedBox.shrink();
    final s=Theme.of(context).colorScheme;
    return Padding(padding:const EdgeInsets.only(top:2),child:Wrap(spacing:4,runSpacing:2,children:[
      for(final c in counts)InkWell(borderRadius:BorderRadius.circular(12),onTap:onTap,
        child:Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:1),
          decoration:BoxDecoration(color:s.surface,borderRadius:BorderRadius.circular(12),
            border:Border.all(color:c.mine?s.primary:s.outlineVariant)),
          child:Text(c.count>1?'${c.emoji} ${c.count}':c.emoji,style:const TextStyle(fontSize:13)))),
    ]));
  }
}

/// Row of the six emojis on top of the menu of a message.
class ReactionPicker extends StatelessWidget{
  final String? mine; final ValueChanged<String> onPick;
  const ReactionPicker({super.key,required this.mine,required this.onPick});
  @override
  Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    return Padding(padding:const EdgeInsets.fromLTRB(12,0,12,4),child:Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
      for(final e in reactionEmojis)InkWell(key:ValueKey('react-$e'),customBorder:const CircleBorder(),onTap:()=>onPick(e),
        child:Container(padding:const EdgeInsets.all(8),
          decoration:BoxDecoration(shape:BoxShape.circle,color:mine==e?s.primaryContainer:null),
          child:Text(e,style:const TextStyle(fontSize:24)))),
    ]));
  }
}
