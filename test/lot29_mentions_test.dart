import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/mentions.dart';
import 'package:sarcade_app/src/models/message.dart';
import 'package:sarcade_app/src/services/notification_actions.dart';

SarcadeMessage _m(String body,{String sender='TEL-01'})=>SarcadeMessage(id:'m1',eventId:'e1',senderId:sender,recipientIds:const [],
  priority:'routine',body:body,createdAt:DateTime.utc(2026,11,6));

void main(){
  test('« @android-demo » names android-demo, « @PCO » every PCO',(){
    expect(mentionsMe(_m('@android-demo rejoins P2'),'android-demo'),isTrue);
    expect(mentionsMe(_m('Rejoins P2 @Android-Demo'),'android-demo'),isTrue);
    expect(mentionsMe(_m('@android-demo2 rejoins'),'android-demo'),isFalse);
    expect(mentionsMe(_m('@PCO besoin d’un relais'),'PC-1',pco:true),isTrue);
    expect(mentionsMe(_m('@PCO besoin d’un relais'),'TEL-02'),isFalse);
    expect(mentionsMe(_m('@TEL-01 note',sender:'TEL-01'),'TEL-01'),isFalse);
  });
  test('the name typed after « @ » and its completion',(){
    expect(mentionQuery('Bonjour @and',12),'and');
    expect(mentionQuery('Bonjour @',9),'');
    expect(mentionQuery('mail@exemple',12),isNull);
    expect(mentionQuery('Bonjour',7),isNull);
    final r=insertMention('Bonjour @and merci',12,'android-demo');
    expect(r.text,'Bonjour @android-demo merci');
    expect(r.cursor,'Bonjour @android-demo '.length);
  });
  test('« PCO » first, then the participants',(){
    expect(mentionSuggestions('',['TEL-02','android-demo','TEL-01'],me:'TEL-01'),['PCO','TEL-02','android-demo']);
    expect(mentionSuggestions('te',['TEL-02','android-demo']),['TEL-02']);
  });
  test('a mention rings even in Routine',(){
    expect(soundFor('routine',{'routine':soundSilent}),soundSilent);
    expect(soundFor('routine',{'routine':soundSilent},mention:true),soundNormal);
    expect(soundFor('routine',{'routine':soundDiscreet},mention:true),soundNormal);
    expect(soundFor('immediate',{},mention:true),soundAlarm);
  });
  testWidgets('the mention coloured in the bubble',(t) async {
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:MentionText('Vu @TEL-02 ?',style:TextStyle(),color:Colors.blue))));
    expect(find.text('Vu @TEL-02 ?',findRichText:true),findsOneWidget);
  });
}
