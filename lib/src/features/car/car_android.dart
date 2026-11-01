/// Android Auto side of the car messaging (lot 1b, 1 Nov 2026): the
/// « conversation » style and the Répondre / Lu actions with their semantic
/// actions. Installed applications only (see car_messaging.dart).
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../l10n/strings.dart';
import '../../services/notification_actions.dart';
import 'car_messaging.dart';

/// The « conversation » style read by Android Auto.
MessagingStyleInformation carStyle(CarConversation c)=>MessagingStyleInformation(
  Person(name:c.me,key:c.me),
  conversationTitle:c.title,groupConversation:c.group,
  messages:[Message(c.body,c.time,Person(name:c.sender,key:c.sender))]);

/// Buttons of a message notification on Android: Répondre and Lu, with the
/// semantic actions Android Auto looks for; Accepter / Refuser (urgent)
/// and Ouvrir stay for the phone.
List<AndroidNotificationAction> carActions(String priority)=>[
  AndroidNotificationAction(actionReply,S.t('notif.action.reply'),showsUserInterface:false,
    semanticAction:SemanticAction.reply,
    inputs:[AndroidNotificationActionInput(label:S.t('car.replyHint'))]),
  if(isUrgentPriority(priority))...[
    AndroidNotificationAction(actionAccept,S.t('notif.action.$actionAccept'),showsUserInterface:false),
    AndroidNotificationAction(actionRefuse,S.t('notif.action.$actionRefuse'),showsUserInterface:false),
  ],
  AndroidNotificationAction(actionRead,S.t('notif.action.$actionRead'),showsUserInterface:false,
    semanticAction:SemanticAction.markAsRead),
  AndroidNotificationAction(actionOpen,S.t('notif.action.$actionOpen'),showsUserInterface:true),
];
