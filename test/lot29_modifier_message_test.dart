import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/message_deletion.dart';
import 'package:sarcade_app/src/features/messages/message_edit.dart';
import 'package:sarcade_app/src/models/message.dart';

SarcadeMessage _m({String sender='TEL-01',String priority='routine',String body='Véhicule repéré',bool deleted=false,DateTime? at})=>
  SarcadeMessage(id:'m1',eventId:'e1',senderId:sender,recipientIds:const [],priority:priority,body:body,
    createdAt:at??DateTime.utc(2026,11,5,20),deleted:deleted);

void main(){
  final now=DateTime.utc(2026,11,5,20,10);
  test('the author within 15 minutes only',(){
    expect(canEditMessage(_m(),'TEL-01',now:now),isTrue);
    expect(canEditMessage(_m(),'TEL-02',now:now),isFalse);
    expect(canEditMessage(_m(),'TEL-01',now:DateTime.utc(2026,11,5,20,16)),isFalse);
    expect(canEditMessage(_m(deleted:true),'TEL-01',now:now),isFalse);
  });
  test('never a distress message nor an order',(){
    expect(canEditMessage(_m(priority:'distress',body:'🆘 Blessé'),'TEL-01',now:now),isFalse);
    expect(canEditMessage(_m(body:'📍 Ordre de déplacement vers P2'),'TEL-01',now:now),isFalse);
  });
  test('nothing sent when the text is empty or unchanged',(){
    expect(editedText(_m(),'  '),isNull);
    expect(editedText(_m(),'Véhicule repéré '),isNull);
    expect(editedText(_m(),'Véhicule blanc repéré'),'Véhicule blanc repéré');
  });
  test('payload of the sync and « modifié » kept in the cache',(){
    final p=editPayload(_m(),'Autre','TEL-01');
    expect(p,{'id':'m1','event_id':'e1','body':'Autre','edited_by':'TEL-01'});
    final cached=_m().toJson();
    final merged=mergeCachedMessage(cached,{'id':'m1','event_id':'e1','body':'Autre','edited':true,'edited_at':'2026-11-05T20:05:00Z'})!;
    final m=SarcadeMessage.fromJson(merged);
    expect(m.body,'Autre');
    expect(m.edited,isTrue);
    expect(m.senderId,'TEL-01');
  });
  test('a change of an unknown or deleted message is ignored',(){
    expect(mergeCachedMessage(null,{'id':'m1','body':'x','edited':true}),isNull);
    expect(mergeCachedMessage({..._m().toJson(),'deleted':true,'body':''},{'id':'m1','body':'x','edited':true}),isNull);
  });
  test('« modifié après accusé » when an acknowledgement came before',(){
    final m=SarcadeMessage.fromJson({..._m().toJson(),'edited':true,'edited_at':'2026-11-05T20:05:00Z'});
    SarcadeAck ack(String who,int min)=>SarcadeAck(id:'a$who',eventId:'e1',messageId:'m1',actorId:who,status:'read',time:DateTime.utc(2026,11,5,20,min));
    expect(editedAfterAck(m,[ack('TEL-02',3)]),isTrue);
    expect(editedAfterAck(m,[ack('TEL-02',8)]),isFalse);
    expect(editedAfterAck(m,[ack('TEL-01',3)]),isFalse);
    expect(editedAfterAck(_m(),[ack('TEL-02',3)]),isFalse);
  });
  test('« Historique »: versions before, then the text now',(){
    final l=versionsOf({'body':'C','edited_at':'2026-11-05T20:09:00Z','versions':[{'body':'A','at':'2026-11-05T20:00:00Z'},{'body':'B','at':'2026-11-05T20:05:00Z'}]});
    expect(l.map((v)=>v.body),['A','B','C']);
    expect(l.last.at,DateTime.utc(2026,11,5,20,9));
  });
}
