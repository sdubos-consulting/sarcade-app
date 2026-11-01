import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../access/access_manager.dart';
import '../../models/message.dart';
import '../../offline/sync_operation.dart';
import '../../services/notification_actions.dart';
import 'car_context.dart';

/// Background side of the voice messaging in the car (lot 1a): see
/// car_context.dart. Every failure falls back on the former behaviour
/// (answer kept for the application, generic wake-up notification).
const _contextFileName='sarcade_car_context.json';
const _repliesFileName='sarcade_car_replies.jsonl';
const _timeout=Duration(seconds:8);
/// Last messages read to find the one of a wake-up.
const _wokenLookup=30;

Future<File> _contextFile() async =>
  File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}$_contextFileName');

/// Remembers the server, event and terminal of the application.
Future<void> saveCarContext(CarContext c) async {
  if(!c.isComplete)return;
  try{
    final f=await _contextFile();
    await f.parent.create(recursive:true);
    await f.writeAsString(jsonEncode(c.toJson()),flush:true);
  }catch(e){
    debugPrint('SARCADE car context not saved: $e');
  }
}

Future<CarContext?> loadCarContext() async {
  try{
    final f=await _contextFile();
    if(!await f.exists())return null;
    return CarContext.fromJson(jsonDecode(await f.readAsString()));
  }catch(_){
    return null;
  }
}

/// HTTP client with the Cloudflare Access session of the device (read from
/// the secure storage: the background isolate has no application state).
Future<AccessHttpClient> _client() async {
  await AccessManager.instance.load();
  return AccessHttpClient();
}

/// Sends at once an answer given from a notification while SARCADE is in
/// the background or closed. True when the server has it; otherwise it
/// stays in the answers file and the application sends it later.
Future<bool> sendAnswerNow(PendingAnswer a) async {
  final c=await loadCarContext();
  if(c==null||c.eventId!=a.eventId)return false;
  AccessHttpClient? client;
  try{
    client=await _client();
    final op=answerOperation(a,operationId:const Uuid().v4());
    final r=await client.post(Uri.parse('${c.base}/api/v0.1/sync'),headers:const {'content-type':'application/json'},
      body:jsonEncode([op.toJson()])).timeout(_timeout);
    if(r.statusCode!=200)return false;
    final results=jsonDecode(r.body);
    return results is List&&results.isNotEmpty&&operationDelivered(results.first);
  }catch(e){
    debugPrint('SARCADE answer kept for later: $e');
    return false;
  }finally{
    client?.close();
  }
}

/// The message announced by a wake-up, fetched from the server of the
/// application; null when it cannot be read now (no network, no session).
Future<({SarcadeMessage message,String deviceId})?> fetchWokenMessage(Map<String,dynamic> data) async {
  final c=await loadCarContext();
  if(c==null||'${data['event_id']??''}'!=c.eventId)return null;
  AccessHttpClient? client;
  try{
    client=await _client();
    final r=await client.get(Uri.parse('${c.base}/api/v0.1/events/${Uri.encodeComponent(c.eventId)}/messages?limit=$_wokenLookup'))
      .timeout(_timeout);
    if(r.statusCode!=200)return null;
    final list=jsonDecode(r.body);
    if(list is! List)return null;
    final messages=[for(final j in list) if(j is Map) SarcadeMessage.fromJson(Map<String,dynamic>.from(j))];
    final m=wokenMessage(data,messages,deviceId:c.deviceId);
    return m==null?null:(message:m,deviceId:c.deviceId);
  }catch(e){
    debugPrint('SARCADE woken message not read: $e');
    return null;
  }finally{
    client?.close();
  }
}

/// Sends at once the answer dictated in the car (Android Auto « Répondre »,
/// lot 1b). True when the server has it; otherwise it waits in the replies
/// file for the application (see [takePendingReplies]).
Future<bool> sendReplyNow(SarcadeMessage reply) async {
  final c=await loadCarContext();
  if(c==null||c.eventId!=reply.eventId)return false;
  AccessHttpClient? client;
  try{
    client=await _client();
    final op=SyncOperation(operationId:const Uuid().v4(),eventId:reply.eventId,objectId:reply.id,objectType:'message',
      action:'create',clientTime:reply.createdAt,payload:reply.toJson());
    final r=await client.post(Uri.parse('${c.base}/api/v0.1/sync'),headers:const {'content-type':'application/json'},
      body:jsonEncode([op.toJson()])).timeout(_timeout);
    if(r.statusCode!=200)return false;
    final results=jsonDecode(r.body);
    return results is List&&results.isNotEmpty&&operationDelivered(results.first);
  }catch(e){
    debugPrint('SARCADE car reply kept for later: $e');
    return false;
  }finally{
    client?.close();
  }
}

Future<File> _repliesFile() async =>
  File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}$_repliesFileName');

/// Keeps a dictated answer for the application (sent again by its Outbox;
/// the server keeps one message per identifier).
Future<void> appendPendingReply(SarcadeMessage reply) async {
  try{
    final f=await _repliesFile();
    await f.parent.create(recursive:true);
    await f.writeAsString('${jsonEncode(reply.toJson())}\n',mode:FileMode.append,flush:true);
  }catch(e){
    debugPrint('SARCADE car reply not kept: $e');
  }
}

/// Answers dictated since the last call (renamed before reading, as the
/// notification answers).
Future<List<SarcadeMessage>> takePendingReplies() async {
  final out=<SarcadeMessage>[];
  try{
    final f=await _repliesFile();
    final draining=File('${f.path}.draining');
    if(!await draining.exists()){
      if(!await f.exists())return out;
      await f.rename(draining.path);
    }
    for(final line in (await draining.readAsString()).split('\n')){
      if(line.trim().isEmpty)continue;
      try{out.add(SarcadeMessage.fromJson(Map<String,dynamic>.from(jsonDecode(line) as Map)));}catch(_){/* damaged line */}
    }
    await draining.delete();
  }catch(e){
    debugPrint('SARCADE car replies not read: $e');
  }
  return out;
}
