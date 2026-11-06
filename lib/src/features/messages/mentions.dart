/// Mentions « @nom » (lot 29, group 7): « @ » proposes the participants of
/// the conversation (and « @PCO » for all the PCO); the mention is coloured
/// in the bubble; the person named gets a notification with sound, even in
/// Routine and in « Sourdine »; « @ » on the line of the conversation while
/// it is unread.
library;

import 'package:flutter/material.dart';

import '../../models/message.dart';

final mentionPattern=RegExp(r'@([A-Za-z0-9_\-]+)');
const mentionPco='PCO';

Set<String> mentionsIn(String body)=>{for(final m in mentionPattern.allMatches(body))m.group(1)!.toLowerCase()};

bool mentionsMe(SarcadeMessage m,String me,{bool pco=false}){
  if(m.deleted||m.senderId==me)return false;
  final names=mentionsIn(m.body);
  return names.contains(me.toLowerCase())||(pco&&names.contains(mentionPco.toLowerCase()));
}

/// The name being typed after « @ » at the cursor, or null.
String? mentionQuery(String text,int cursor){
  if(cursor<0||cursor>text.length)return null;
  final before=text.substring(0,cursor);
  final m=RegExp(r'(?:^|\s)@([A-Za-z0-9_\-]*)$').firstMatch(before);
  return m?.group(1);
}

/// The text with « @name » in place of what was typed, and the cursor after it.
({String text,int cursor}) insertMention(String text,int cursor,String name){
  final q=mentionQuery(text,cursor)??'';
  final start=cursor-q.length-1;
  final after=text.substring(cursor);
  final inserted='@$name ';
  return (text:text.substring(0,start)+inserted+after.replaceFirst(RegExp(r'^ '),''),cursor:start+inserted.length);
}

/// « PCO » first, then the people whose name starts with the query.
List<String> mentionSuggestions(String query,Iterable<String> people,{String? me,int max=8}){
  final q=query.toLowerCase();
  final out=<String>[if(mentionPco.toLowerCase().startsWith(q))mentionPco];
  for(final p in ({...people}.toList()..sort())){
    if(p==me||out.contains(p))continue;
    if(p.toLowerCase().startsWith(q))out.add(p);
  }
  return out.take(max).toList();
}

/// The body with the mentions coloured.
class MentionText extends StatelessWidget{
  final String text; final TextStyle style; final Color color;
  const MentionText(this.text,{super.key,required this.style,required this.color});
  @override
  Widget build(BuildContext context){
    final spans=<TextSpan>[]; var at=0;
    for(final m in mentionPattern.allMatches(text)){
      if(m.start>0&&!RegExp(r'\s').hasMatch(text[m.start-1]))continue;
      if(m.start>at)spans.add(TextSpan(text:text.substring(at,m.start)));
      spans.add(TextSpan(text:m.group(0),style:TextStyle(color:color,fontWeight:FontWeight.w600)));
      at=m.end;
    }
    if(spans.isEmpty)return Text(text,style:style);
    if(at<text.length)spans.add(TextSpan(text:text.substring(at)));
    return Text.rich(TextSpan(style:style,children:spans));
  }
}
