/// Voice messaging in the car, lot 1b: Android Auto (card « CarPlay et
/// Android Auto », note of the same name, choices of 30 Oct 2026, 18 h 09).
///
/// Android Auto reads the notifications in the « conversation » format
/// (MessagingStyle) and offers two actions only: **Répondre** (dictated
/// answer, without opening SARCADE) and **Lu** (marked as read, which is
/// the acknowledgement « Lu »). Accepter and Refuser stay on the phone.
library;

import 'package:uuid/uuid.dart';

import '../../l10n/strings.dart';
import '../../models/message.dart';
import '../../services/notification_actions.dart';
import '../../services/notification_keys.dart';

/// Dictated answer (Android Auto « Répondre »).
const actionReply='reply';
/// Key of the text typed or dictated in the answer.
const replyInputKey='sarcade_reply';

/// An earlier message shown in the same notification (lot 20).
class CarLine {
  final String sender, body;
  final DateTime time;
  const CarLine({required this.sender,required this.body,required this.time});
}

/// Lot 20 (card « Android Auto : ordres de déplacement peu utilisables… »,
/// choice 5): the messages of one sender in one notification of
/// conversation, the latest one shown (Android Auto shows the last message
/// of the conversation): at most this many earlier ones, of the last 2 h.
const carThreadMax=4;
const carThreadWindow=Duration(hours:2);

/// Earlier messages of the sender of [m] in the same conversation (same
/// recipients), oldest first; none for a distress (its own notification).
List<SarcadeMessage> carThread(SarcadeMessage m,Iterable<SarcadeMessage> all,{required String me}){
  bool distress(SarcadeMessage x)=>isDistressNotification(body:x.body,priority:x.priority,recipientIds:x.recipientIds);
  if(m.senderId==me||distress(m))return const [];
  final to=([...m.recipientIds]..sort()).join(',');
  final list=[for(final x in all)
    if(x.id!=m.id&&!x.deleted&&x.eventId==m.eventId&&x.senderId==m.senderId&&!distress(x)
      &&([...x.recipientIds]..sort()).join(',')==to
      &&!x.createdAt.isAfter(m.createdAt)&&m.createdAt.difference(x.createdAt)<=carThreadWindow)x]
    ..sort((a,b)=>a.createdAt.compareTo(b.createdAt));
  return list.length>carThreadMax?list.sublist(list.length-carThreadMax):list;
}

/// What the notification of a message shows as a conversation.
class CarConversation {
  /// Terminal of this phone (the « me » of the conversation).
  final String me;
  /// Sender of the message (callsign or terminal).
  final String sender;
  /// Name of the channel; null for a direct message.
  final String? title;
  final String body;
  final DateTime time;
  /// Earlier messages of the same sender, shown before [body] (lot 20).
  final List<CarLine> history;
  /// Keys of their notifications, replaced by this one (lot 20).
  final List<String> replaces;
  const CarConversation({required this.me,required this.sender,required this.body,required this.time,this.title,
    this.history=const [],this.replaces=const []});
  bool get group=>title!=null;
}

/// Conversation of [m] seen from [me]: a direct message, or a channel (the
/// general broadcast « Tous », or a channel whose name is [channelName]
/// when the caller knows it).
/// [earlier]: messages shown with it in the same notification (see
/// [carThread]), whose own notifications it replaces.
CarConversation carConversation(SarcadeMessage m,{required String me,String? channelName,List<SarcadeMessage> earlier=const []}){
  final r=m.recipientIds;
  final channel=r.isEmpty||r.any((x)=>x.startsWith('group:'));
  return CarConversation(me:me,sender:m.senderId,body:m.body,time:m.createdAt.toLocal(),
    title:!channel?null:(channelName??(r.isEmpty?S.t('car.allChannel'):S.t('car.channel'))),
    history:[for(final x in earlier)CarLine(sender:x.senderId,body:x.body,time:x.createdAt.toLocal())],
    replaces:[for(final x in earlier)messageNotificationKey(x)]);
}

/// The dictated answer, as a message (choice by default of lot 1b): always
/// to the sender, in a direct chat, even when the message came in a channel
/// (a voice answer never goes to everyone by mistake); routine priority;
/// linked to the message it answers.
SarcadeMessage carReply({required String id,required String eventId,required String me,required String sender,
    required String messageId,required String text,required DateTime now})=>SarcadeMessage(
  id:id,eventId:eventId,senderId:me,recipientIds:['user:$sender'],priority:'routine',body:text.trim(),
  createdAt:now.toUtc(),replyTo:messageId);

/// The answer of a « Répondre » action, or null (another action, nothing
/// dictated, or a notification without its sender).
SarcadeMessage? replyOf(NotificationPayload p,String? action,String? input,{DateTime? now,String? id}){
  final text=input?.trim()??'';
  final sender=p.senderId;
  if(action!=actionReply||text.isEmpty||sender==null||sender.isEmpty||p.deviceId.isEmpty)return null;
  return carReply(id:id??const Uuid().v4(),eventId:p.eventId,me:p.deviceId,sender:sender,messageId:p.messageId,
    text:text,now:now??DateTime.now());
}
