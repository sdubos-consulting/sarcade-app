// Voice messaging in the car, lot 1b: Android Auto (1 Nov 2026).
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/car/car_android.dart';
import 'package:sarcade_app/src/features/car/car_messaging.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/message.dart';
import 'package:sarcade_app/src/services/notification_actions.dart';

SarcadeMessage msg(List<String> to,{String priority='routine'})=>SarcadeMessage(id:'m1',eventId:'e',senderId:'F4JPO',
  recipientIds:to,priority:priority,body:'Rendez-vous au point haut',createdAt:DateTime.utc(2026,11,1,3));

void main(){
  setUp(()=>S.setLanguage('fr'));

  test('direct message, channel, general broadcast',(){
    final d=carConversation(msg(['user:TEL-1']),me:'TEL-1');
    expect(d.group,isFalse); expect(d.title,isNull); expect(d.sender,'F4JPO');
    expect(carConversation(msg(['group:g1']),me:'TEL-1',channelName:'Équipe 2').title,'Équipe 2');
    expect(carConversation(msg(['group:g1']),me:'TEL-1').title,'Canal');
    expect(carConversation(msg(const []),me:'TEL-1').title,'Tous');
  });

  test('conversation style read by Android Auto',(){
    final st=carStyle(carConversation(msg(['group:g1']),me:'TEL-1',channelName:'Diffusion PCO'));
    expect(st.person.name,'TEL-1');
    expect(st.groupConversation,isTrue); expect(st.conversationTitle,'Diffusion PCO');
    expect(st.messages!.single.text,'Rendez-vous au point haut');
    expect(st.messages!.single.person!.name,'F4JPO');
  });

  test('Répondre and Lu carry their semantic actions, without opening SARCADE',(){
    final routine=carActions('routine');
    expect(routine.map((a)=>a.id),[actionReply,actionRead,actionOpen]);
    final reply=routine.first;
    expect(reply.semanticAction,SemanticAction.reply); expect(reply.showsUserInterface,isFalse);
    expect(reply.inputs.single.allowFreeFormInput,isTrue);
    expect(routine[1].semanticAction,SemanticAction.markAsRead); expect(routine[1].showsUserInterface,isFalse);
    expect(carActions('urgent').map((a)=>a.id),[actionReply,actionAccept,actionRefuse,actionRead,actionOpen]);
  });

  test('the dictated answer goes to the sender, as a direct message',(){
    final p=NotificationPayload(eventId:'e',messageId:'m1',deviceId:'TEL-1',priority:'urgent',senderId:'F4JPO');
    final again=NotificationPayload.decode(p.encode());
    expect(again!.senderId,'F4JPO');
    final r=replyOf(again,actionReply,'  Bien reçu, j’arrive ',now:DateTime.utc(2026,11,1,3,5),id:'r1')!;
    expect(r.recipientIds,['user:F4JPO']); expect(r.senderId,'TEL-1'); expect(r.body,'Bien reçu, j’arrive');
    expect(r.priority,'routine'); expect(r.replyTo,'m1'); expect(r.eventId,'e');
    expect(replyOf(again,actionRead,'x'),isNull);
    expect(replyOf(again,actionReply,'   '),isNull,reason:'nothing dictated');
    final old=NotificationPayload(eventId:'e',messageId:'m1',deviceId:'TEL-1',priority:'routine');
    expect(replyOf(old,actionReply,'ok'),isNull,reason:'no sender known');
    expect(NotificationPayload.decode(old.encode())!.senderId,isNull);
  });
}
