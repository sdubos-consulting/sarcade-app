import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/swipe_reply.dart';

void main(){
  test('the bubble follows the finger, slowed past the threshold, never left',(){
    expect(swipeOffset(-20),0);
    expect(swipeOffset(30),30);
    expect(swipeOffset(swipeReplyAt),swipeReplyAt);
    expect(swipeOffset(200),swipeReplyMax);
  });
  testWidgets('sliding to the right prepares the reply without the menu',(t) async {
    var replied=0;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Center(child:SwipeReply(onReply:()=>replied++,
      child:const SizedBox(width:200,height:40,child:Text('Bulle')))))));
    await t.drag(find.text('Bulle'),const Offset(90,0));
    await t.pumpAndSettle();
    expect(replied,1);
    await t.drag(find.text('Bulle'),const Offset(20,0));
    await t.pumpAndSettle();
    expect(replied,1);
  });
}
