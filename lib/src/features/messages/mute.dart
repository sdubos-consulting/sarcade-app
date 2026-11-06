/// « Sourdine » of a conversation (lot 29, group 7): 8 h, 1 week or always,
/// set on this device only. Always rings: a distress message, the priority
/// IMMÉDIAT, an order, a mention « @ » of me.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/message.dart';
import '../../offline/local_store.dart';
import '../../services/notification_actions.dart' show isSosBody;

const muteAlways='always';
const muteChoices={'8h':Duration(hours:8),'week':Duration(days:7),muteAlways:null};

String muteKey(String eventId)=>'muted:$eventId';

Map<String,String> parseMutes(String? v){
  if(v==null||v.isEmpty)return {};
  try{final j=jsonDecode(v);return j is Map?{for(final e in j.entries)'${e.key}':'${e.value}'}:{};}catch(_){return {};}
}

bool isMutedIn(Map<String,String> all,String conv,DateTime now){
  final v=all[conv];
  if(v==null)return false;
  if(v==muteAlways)return true;
  final until=DateTime.tryParse(v);
  return until!=null&&now.toUtc().isBefore(until.toUtc());
}

/// [choice] one of [muteChoices], or null to ring again.
Map<String,String> withMute(Map<String,String> all,String conv,String? choice,DateTime now){
  final out={...all};
  if(choice==null){out.remove(conv);return out;}
  final d=muteChoices[choice];
  out[conv]=d==null?muteAlways:now.toUtc().add(d).toIso8601String();
  return out;
}

/// Messages that ring even in a conversation in « Sourdine ».
bool ringsThroughMute(SarcadeMessage m,{bool mentionsMe=false})=>
  mentionsMe||m.priority=='distress'||m.priority=='immediate'||isSosBody(m.body)||m.body.trimLeft().startsWith('📍 Ordre de déplacement');

class Mutes extends ValueNotifier<Map<String,String>>{
  Mutes():super({});
  static final instance=Mutes();
  String? _event;
  void load(LocalStore store,String eventId){
    if(_event==eventId)return;
    _event=eventId; value=parseMutes(store.preference(muteKey(eventId)));
  }
  bool muted(String conv,{DateTime? now})=>isMutedIn(value,conv,now??DateTime.now());
  Future<void> set(LocalStore store,String eventId,String conv,String? choice) async {
    load(store,eventId);
    final now=DateTime.now();
    // Expired ones are forgotten at the same time.
    value=Map.fromEntries(withMute(value,conv,choice,now).entries.where((e)=>isMutedIn({e.key:e.value},e.key,now)));
    await store.setPreference(muteKey(eventId),value.isEmpty?null:jsonEncode(value));
  }
}
