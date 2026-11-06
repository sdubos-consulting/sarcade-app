import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/reactions.dart';
import 'package:sarcade_app/src/models/message.dart';

SarcadeMessage _m({String priority='routine',String body='Arrivé au point 2',bool deleted=false})=>
  SarcadeMessage(id:'m1',eventId:'e1',senderId:'TEL-01',recipientIds:const [],priority:priority,body:body,
    createdAt:DateTime.utc(2026,11,5,20),deleted:deleted);

void main(){
  test('never on a distress message, an order or a deleted message',(){
    expect(canReact(_m()),isTrue);
    expect(canReact(_m(priority:'distress',body:'🆘 Blessé')),isFalse);
    expect(canReact(_m(body:'📍 Ordre de déplacement vers P2')),isFalse);
    expect(canReact(_m(deleted:true)),isFalse);
  });
  test('one reaction per person, changed then removed',(){
    var all=applyReaction({},{'message_id':'m1','actor_id':'TEL-02','emoji':'👍'});
    all=applyReaction(all,{'message_id':'m1','actor_id':'TEL-03','emoji':'👍'});
    all=applyReaction(all,{'message_id':'m1','actor_id':'TEL-02','emoji':'❤️'});
    expect(all['m1'],{'TEL-02':'❤️','TEL-03':'👍'});
    all=applyReaction(all,{'message_id':'m1','actor_id':'TEL-02','emoji':null});
    all=applyReaction(all,{'message_id':'m1','actor_id':'TEL-03','emoji':null});
    expect(all,isEmpty);
  });
  test('an unknown emoji removes, never stored',(){
    final all=applyReaction({},{'message_id':'m1','actor_id':'TEL-02','emoji':'🍕'});
    expect(all,isEmpty);
  });
  test('counts in the usual order, mine marked',(){
    final c=reactionCounts({'TEL-02':'🙏','TEL-03':'👍','TEL-04':'👍'},'TEL-02');
    expect(c.map((x)=>x.emoji),['👍','🙏']);
    expect(c.first.count,2);
    expect(c.last.mine,isTrue);
  });
  test('the same emoji again removes it',(){
    expect(nextReaction('👍','👍'),isNull);
    expect(nextReaction('👍','😂'),'😂');
    expect(nextReaction(null,'😂'),'😂');
  });
  test('kept on the device as text',(){
    expect(parseReactions('{"m1":{"TEL-02":"👍"}}'),{'m1':{'TEL-02':'👍'}});
    expect(parseReactions('pas du json'),isEmpty);
    expect(parseReactions(null),isEmpty);
  });
  testWidgets('chips under the bubble',(t) async {
    await t.pumpWidget(MaterialApp(home:Scaffold(body:ReactionChips(of:const {'TEL-02':'👍','TEL-03':'👍'},me:'TEL-01'))));
    expect(find.text('👍 2'),findsOneWidget);
  });
}
