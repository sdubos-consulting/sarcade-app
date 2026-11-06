import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/forward.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/message.dart';

SarcadeMessage _m({String priority='urgent',String body='Balise entendue au nord',bool deleted=false})=>
  SarcadeMessage(id:'m1',eventId:'e1',senderId:'TEL-01',recipientIds:const [],priority:priority,body:body,
    createdAt:DateTime.utc(2026,11,5,21,30),deleted:deleted,
    attachments:const [SarcadeAttachment(fileId:'f1',name:'photo.jpg',mimeType:'image/jpeg',sizeBytes:1000)]);

void main(){
  test('never a distress message, an order or a deleted message',(){
    expect(canForward(_m()),isTrue);
    expect(canForward(_m(priority:'distress',body:'🆘 Blessé')),isFalse);
    expect(canForward(_m(body:'📍 Ordre de déplacement vers P2')),isFalse);
    expect(canForward(_m(deleted:true)),isFalse);
  });
  test('the copy keeps author, time, priority and photos of the original',(){
    final c=forwardedCopy(_m(),id:'m2',me:'TEL-02',recipients:const ['group:pco'],now:DateTime.utc(2026,11,5,22));
    expect(c.senderId,'TEL-02');
    expect(c.recipientIds,['group:pco']);
    expect(c.priority,'urgent');
    expect(c.attachments.single.fileId,'f1');
    expect(c.toJson()['forwarded_from'],{'message_id':'m1','sender_id':'TEL-01','created_at':'2026-11-05T21:30:00.000Z'});
    // Forwarded again: still the first author.
    final again=forwardedCopy(SarcadeMessage.fromJson(c.toJson()),id:'m3',me:'TEL-03',recipients:const [],now:DateTime.utc(2026,11,5,23));
    expect(again.forwardedSender,'TEL-01');
    expect(again.forwardedId,'m1');
  });
  test('« Transféré · TEL-01, 21:30 »',(){
    S.setLanguage('fr');
    final c=forwardedCopy(_m(),id:'m2',me:'TEL-02',recipients:const [],now:DateTime.utc(2026,11,5,22));
    expect(forwardedLabel(c,(t)=>'21:30'),'Transféré · TEL-01, 21:30');
  });
}
