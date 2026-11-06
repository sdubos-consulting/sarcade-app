/// « Recherche dans une conversation » (lot 29, group 7): loupe in the
/// header, results highlighted, previous / next, their number; also the
/// captions of the photos (the text of the message); offline on the
/// messages already received.
library;

import 'package:flutter/material.dart';

import '../../models/message.dart';

String _fold(String s){
  const from='àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝŸŒÆ';
  const to  ='aaaaaaceeeeiiiinooooouuuuyyoaAAAAAACEEEEIIIINOOOOOUUUUYYOA';
  final b=StringBuffer();
  for(final r in s.runes){final c=String.fromCharCode(r);final i=from.indexOf(c);b.write(i<0?c:to[i]);}
  return b.toString().toLowerCase();
}

/// Ids of the messages holding [query] (accents and case ignored), in the
/// order of the conversation; deleted messages never match.
List<String> searchHits(List<SarcadeMessage> messages,String query){
  final q=_fold(query.trim());
  if(q.isEmpty)return const [];
  return [for(final m in messages)if(!m.deleted&&_fold(m.body).contains(q))m.id];
}

/// Spans of [query] in [text] (accents and case ignored); the folding keeps
/// one character for one, so positions match.
List<(int,int)> searchRanges(String text,String query){
  final q=_fold(query.trim()); if(q.isEmpty)return const [];
  final t=_fold(text); final out=<(int,int)>[]; var i=t.indexOf(q);
  while(i>=0){out.add((i,i+q.length));i=t.indexOf(q,i+q.length);}
  return out;
}

class HighlightText extends StatelessWidget{
  final String text,query; final TextStyle style; final Color background;
  const HighlightText(this.text,{super.key,required this.query,required this.style,required this.background});
  @override
  Widget build(BuildContext context){
    final ranges=searchRanges(text,query);
    if(ranges.isEmpty)return Text(text,style:style);
    final spans=<TextSpan>[]; var at=0;
    for(final (a,b) in ranges){
      if(a>at)spans.add(TextSpan(text:text.substring(at,a)));
      spans.add(TextSpan(text:text.substring(a,b),style:TextStyle(backgroundColor:background,fontWeight:FontWeight.w700)));
      at=b;
    }
    if(at<text.length)spans.add(TextSpan(text:text.substring(at)));
    return Text.rich(TextSpan(style:style,children:spans));
  }
}
