/// « Messages importants » (lot 29, group 7): a star on the bubble, the
/// list in the « … » menu of Messages, all conversations together; kept by
/// the server for the person, found again on every device.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../offline/local_store.dart';
import '../../services/sarcade_api.dart';

const importantKey='important_messages';
const importantMax=500;

String importantId(String eventId,String messageId)=>'$eventId/$messageId';

List<String> parseImportant(Object? v){
  final raw=v is String?(){try{return jsonDecode(v);}catch(_){return null;}}():v;
  if(raw is! List)return const [];
  final out=<String>[];
  for(final x in raw){final s='$x';if(s.contains('/')&&!out.contains(s))out.add(s);}
  return out;
}

/// Most recent first, at most [importantMax].
List<String> toggleImportant(List<String> list,String id){
  if(list.contains(id))return [...list]..remove(id);
  return [id,...list].take(importantMax).toList();
}

class Important extends ValueNotifier<List<String>>{
  Important():super(const []);
  static final instance=Important();
  bool _loaded=false;

  void load(LocalStore store){
    if(_loaded)return;
    _loaded=true; value=parseImportant(store.preference(importantKey));
  }

  bool has(String eventId,String messageId)=>value.contains(importantId(eventId,messageId));

  /// From the personal settings of the server (every device of the person).
  Future<void> fromServer(LocalStore store,Object? remote) async {
    if(remote is! List)return;
    _loaded=true; value=parseImportant(remote);
    await store.setPreference(importantKey,value.isEmpty?null:jsonEncode(value));
  }

  Future<void> toggle(LocalStore store,SarcadeApi api,String eventId,String messageId) async {
    load(store);
    value=toggleImportant(value,importantId(eventId,messageId));
    await store.setPreference(importantKey,value.isEmpty?null:jsonEncode(value));
    try{await api.patchMyPreferences({importantKey:value.isEmpty?null:value});}catch(_){/* kept here, sent next time */}
  }
}
