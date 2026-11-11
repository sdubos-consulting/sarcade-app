/// Deletion of messages, like WhatsApp (decision of 29 Oct 2026).
///
/// « Supprimer pour moi »: any message, hidden on this device only.
/// « Supprimer pour tous »: the author during 2 days after sending, the PCO
/// for any message without delay; everyone then sees « Ce message a été
/// supprimé ». The server keeps the original for the PCO only.
library;

import '../../models/message.dart';

const authorDeleteDelay=Duration(days:2);

/// Distress (« 🆘 », priority `distress`), its « Fin de détresse » and move
/// orders (« 📍 Ordre de déplacement ») are never deleted for everyone, not
/// even by the PCO (lot 21, same rule as the server); « Supprimer pour moi »
/// stays possible.
bool keptForEveryone(SarcadeMessage m){
  final b=m.body.trim();
  if(m.priority=='distress'||(m.priority=='immediate'&&b.startsWith('🆘')))return true;
  final l=b.toLowerCase();
  return l.startsWith('fin de détresse')||l.startsWith('end of distress')||b.startsWith('📍 Ordre de déplacement');
}

/// Whether this operator may delete the message for everyone.
bool canDeleteForEveryone(SarcadeMessage m,String actorId,{required bool pco,required DateTime now}){
  if(m.deleted||keptForEveryone(m))return false;
  if(pco)return true;
  return m.senderId==actorId&&now.toUtc().difference(m.createdAt.toUtc())<=authorDeleteDelay;
}

/// The message as cached once deleted for everyone: no text nor photo.
Map<String,dynamic> deletedMessage(Map<String,dynamic> message,{required String by,required bool byPco,required DateTime at})=>{
  ...message,'body':'','attachments':const [],'deleted':true,'deleted_by':by,'deleted_by_pco':byPco,'deleted_at':at.toUtc().toIso8601String()};

/// What the local cache keeps when a message arrives (realtime, feed, this
/// device). A deletion only carries the id: it is merged onto the known
/// message; a deleted message never comes back with its text.
Map<String,dynamic>? mergeCachedMessage(Map<String,dynamic>? existing,Map<String,dynamic> incoming){
  final deleting=incoming['deleted']==true;
  // A change (« message.updated »): only the text and its marks.
  if(incoming['sender_id']==null&&incoming['edited']==true)return existing==null||existing['deleted']==true?null:{...existing,...incoming};
  if(existing==null)return incoming['sender_id']==null?null:(deleting?{...incoming,'body':'','attachments':const []}:incoming);
  if(deleting)return {...existing,...incoming,'body':'','attachments':const []};
  if(existing['deleted']==true){
    return {...incoming,'body':'','attachments':const [],for(final k in const ['deleted','deleted_by','deleted_by_pco','deleted_at'])k:existing[k]};
  }
  return incoming;
}

/// Messages hidden on this device (« Supprimer pour moi »), kept as one
/// preference per event.
String hiddenMessagesKey(String eventId)=>'msg_hidden:$eventId';
Set<String> parseHidden(String? v)=>(v??'').split('|').where((s)=>s.isNotEmpty).toSet();
String? formatHidden(Set<String> ids)=>ids.isEmpty?null:ids.join('|');
