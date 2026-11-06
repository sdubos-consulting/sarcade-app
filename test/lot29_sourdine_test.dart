import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/conversation_row.dart';
import 'package:sarcade_app/src/features/messages/mute.dart';
import 'package:sarcade_app/src/models/message.dart';

SarcadeMessage _m(String priority,String body)=>SarcadeMessage(id:'m1',eventId:'e1',senderId:'TEL-02',recipientIds:const [],
  priority:priority,body:body,createdAt:DateTime.utc(2026,11,6));

void main(){
  final now=DateTime.utc(2026,11,6,0,30);
  test('8 h, 1 week, always, then sound back on',(){
    var all=withMute({},'all','8h',now);
    expect(isMutedIn(all,'all',now.add(const Duration(hours:7))),isTrue);
    expect(isMutedIn(all,'all',now.add(const Duration(hours:9))),isFalse);
    all=withMute(all,'g:pco','week',now);
    expect(isMutedIn(all,'g:pco',now.add(const Duration(days:6))),isTrue);
    all=withMute(all,'u:TEL-02',muteAlways,now);
    expect(isMutedIn(all,'u:TEL-02',now.add(const Duration(days:400))),isTrue);
    all=withMute(all,'u:TEL-02',null,now);
    expect(isMutedIn(all,'u:TEL-02',now),isFalse);
  });
  test('distress, IMMÉDIAT, orders and mentions ring through',(){
    expect(ringsThroughMute(_m('routine','Pause café')),isFalse);
    expect(ringsThroughMute(_m('urgent','Route coupée')),isFalse);
    expect(ringsThroughMute(_m('immediate','Rejoignez P2')),isTrue);
    expect(ringsThroughMute(_m('distress','🆘 Blessé')),isTrue);
    expect(ringsThroughMute(_m('routine','🆘 DÉTRESSE — TEL-02')),isTrue);
    expect(ringsThroughMute(_m('urgent','📍 Ordre de déplacement vers P2')),isTrue);
    expect(ringsThroughMute(_m('routine','Pause café'),mentionsMe:true),isTrue);
  });
  test('kept on the device as text',(){
    expect(parseMutes('{"all":"always"}'),{'all':'always'});
    expect(parseMutes('pas du json'),isEmpty);
  });
  testWidgets('crossed speaker on the line',(t) async {
    final e=(favKey:'all',title:'Tous',preview:'',at:null,unread:0,fav:false,avatar:const SizedBox(),onTap:(){},key:const ValueKey('c'),selected:false);
    await t.pumpWidget(MaterialApp(home:Scaffold(body:ConversationRow(entry:e,muted:true))));
    expect(find.byKey(const ValueKey('conv-muted')),findsOneWidget);
  });
}
