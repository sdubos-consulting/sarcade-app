/// Profile photo in place of the initials (lot 29, group 7).
///
/// Reduced to 256 px on the device before sending (under 50 KB), kept by
/// the server for the participants of the event only. « Retirer la photo »
/// by the operator; a PCO or an administrator can remove someone else's,
/// the operator is then told. APRS, MeshCore and Meshtastic stations keep
/// their symbols: they never have a photo.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../offline/local_store.dart';
import '../../services/sarcade_api.dart';

const photoSide=256.0;
const photoQuality=80;
const photoMaxBytes=64*1024;

String photosIndexKey(String eventId)=>'photos:$eventId';
String photoKey(String eventId,String deviceId)=>'photo:$eventId:$deviceId';

/// device → updated_at, as kept on this device.
Map<String,String> parsePhotoIndex(String? v){
  if(v==null||v.isEmpty)return {};
  try{final j=jsonDecode(v);return j is Map?{for(final e in j.entries)'${e.key}':'${e.value}'}:{};}catch(_){return {};}
}

/// The photos to fetch (new or changed) and the ones to forget, from the
/// list of the server.
({List<String> fetch,List<String> forget}) photoDiff(Map<String,String> kept,List<Map> server){
  final now={for(final r in server)if(r['device_id'] is String)r['device_id'] as String:'${r['updated_at']??''}'};
  return (fetch:[for(final e in now.entries)if(kept[e.key]!=e.value)e.key]..sort(),
    forget:[for(final k in kept.keys)if(!now.containsKey(k))k]..sort());
}

class ProfilePhotos extends ValueNotifier<Map<String,Uint8List>>{
  ProfilePhotos():super({});
  static final instance=ProfilePhotos();
  String? _event; Map<String,String> _index={};

  Uint8List? of(String deviceId)=>value[deviceId];

  void load(LocalStore store,String eventId){
    if(_event==eventId)return;
    _event=eventId; _index=parsePhotoIndex(store.preference(photosIndexKey(eventId)));
    final out=<String,Uint8List>{};
    for(final id in _index.keys){
      final b=store.preference(photoKey(eventId,id));
      if(b==null)continue;
      try{out[id]=base64Decode(b);}catch(_){/* damaged: fetched again */}
    }
    value=out;
  }

  Future<void> _keep(LocalStore store,String eventId,String deviceId,Uint8List? bytes,String? at) async {
    final next={...value};
    if(bytes==null){next.remove(deviceId);_index.remove(deviceId);}else{next[deviceId]=bytes;_index[deviceId]=at??'';}
    value=next;
    await store.setPreference(photoKey(eventId,deviceId),bytes==null?null:base64Encode(bytes));
    await store.setPreference(photosIndexKey(eventId),_index.isEmpty?null:jsonEncode(_index));
  }

  /// Back online or on opening: only the photos new or changed.
  Future<void> refresh(SarcadeApi api,LocalStore store,String eventId) async {
    load(store,eventId);
    final rows=await api.photos(eventId);
    final d=photoDiff(_index,rows);
    final list={for(final r in rows)'${r['device_id']}':'${r['updated_at']}'};
    for(final id in d.forget){await _keep(store,eventId,id,null,null);}
    for(final id in d.fetch){
      final b=await api.photo(eventId,id);
      await _keep(store,eventId,id,b,list[id]);
    }
  }

  /// « photo.updated » from the real time.
  Future<void> changed(SarcadeApi api,LocalStore store,String eventId,Map data) async {
    load(store,eventId);
    final id='${data['device_id']??''}'; if(id.isEmpty)return;
    final at=data['updated_at'];
    if(at==null){await _keep(store,eventId,id,null,null);return;}
    if(_index[id]=='$at')return;
    final b=await api.photo(eventId,id);
    await _keep(store,eventId,id,b,'$at');
  }

  /// This device: sent first, kept once the server took it.
  Future<void> setMine(SarcadeApi api,LocalStore store,String eventId,String deviceId,Uint8List bytes) async {
    load(store,eventId);
    final at=await api.putPhoto(eventId,deviceId,bytes);
    await _keep(store,eventId,deviceId,bytes,at);
  }

  Future<void> remove(SarcadeApi api,LocalStore store,String eventId,String deviceId) async {
    load(store,eventId);
    await api.deletePhoto(eventId,deviceId);
    await _keep(store,eventId,deviceId,null,null);
  }
}
