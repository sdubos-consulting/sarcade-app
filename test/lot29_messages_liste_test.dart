import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/conversation_row.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

ConvEntry _e(String title,{int unread=0,bool fav=false,DateTime? at})=>(favKey:title,title:title,preview:'Texte',at:at,unread:unread,fav:fav,
  avatar:const CircleAvatar(),onTap:(){},key:ValueKey(title),selected:false);

void main(){
  setUp(()=>S.setLanguage('fr'));
  final now=DateTime(2026,11,5,20);
  test('favourites, then unread, then the others; the last message first',(){
    final l=sortConversations([
      _e('ancien',at:now.subtract(const Duration(days:2))),
      _e('non lu',unread:2,at:now.subtract(const Duration(hours:3))),
      _e('favori',fav:true,at:now.subtract(const Duration(days:5))),
      _e('récent',at:now.subtract(const Duration(minutes:5))),
      _e('favori récent',fav:true,unread:1,at:now.subtract(const Duration(minutes:1))),
    ]);
    expect(l.map((e)=>e.title),['favori récent','favori','non lu','récent','ancien']);
  });
  test('time: today, hier, day name, then the date',(){
    expect(conversationTime(DateTime(2026,11,5,14,5),now),'14:05');
    expect(conversationTime(DateTime(2026,11,4,9),now),'Hier');
    expect(conversationTime(DateTime(2026,11,3,9),now),'mardi');
    expect(conversationTime(DateTime(2026,10,28,9),now),'28/10');
  });
  testWidgets('something new: date and count in blue, preview on two lines',(t) async {
    await t.pumpWidget(MaterialApp(home:Scaffold(body:ConversationRow(entry:_e('PCO',unread:3,at:DateTime(2026,11,5,19,58)),now:now))));
    expect(find.text('3'),findsOneWidget);
    expect(t.widget<Text>(find.text('Texte')).maxLines,2);
    final time=t.widget<Text>(find.text('19:58'));
    expect(time.style?.color,Theme.of(t.element(find.text('19:58'))).colorScheme.primary);
  });
}
