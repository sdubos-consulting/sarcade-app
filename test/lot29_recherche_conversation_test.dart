import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/conversation_search.dart';
import 'package:sarcade_app/src/models/message.dart';

SarcadeMessage _m(String id,String body,{bool deleted=false})=>SarcadeMessage(id:id,eventId:'e1',senderId:'TEL-01',recipientIds:const [],
  priority:'routine',body:body,createdAt:DateTime.utc(2026,11,6),deleted:deleted);

void main(){
  final list=[_m('m1','Balise entendue au nord'),_m('m2','Rien'),_m('m3','BALISE localisée, photo jointe'),_m('m4','balise',deleted:true)];
  test('every message holding the word, in order, deleted ones excluded',(){
    expect(searchHits(list,'balise'),['m1','m3']);
    expect(searchHits(list,'  '),isEmpty);
    expect(searchHits(list,'localisee'),['m3']);
  });
  test('each occurrence found, accents and case ignored',(){
    expect(searchRanges('Balise, balise',"balise"),[(0,6),(8,14)]);
    expect(searchRanges('Été dégagé','ete'),[(0,3)]);
  });
  testWidgets('occurrences highlighted',(t) async {
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:HighlightText('Balise entendue',query:'balise',style:TextStyle(),background:Colors.yellow))));
    expect(find.text('Balise entendue',findRichText:true),findsOneWidget);
  });
}
