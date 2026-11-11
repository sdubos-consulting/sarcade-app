/// Small Markdown reader of the help (card « Paramètres : menu « Aide » »,
/// validated on 10 Nov 2026, choice 4): titles (#, ##, ###), paragraphs,
/// lists (- or 1.) and **bold**, nothing more. No new dependency: the help
/// texts are written for it.
library;

import 'package:flutter/material.dart';

enum MdKind{heading,paragraph,bullet,numbered}

class MdBlock {
  final MdKind kind;
  /// 1 to 3 for a title; the number of a numbered item.
  final int level;
  final String text;
  const MdBlock(this.kind,this.text,{this.level=0});
}

final _heading=RegExp(r'^(#{1,3})\s+(.*)$');
final _bullet=RegExp(r'^[-*]\s+(.*)$');
final _numbered=RegExp(r'^(\d+)[.)]\s+(.*)$');

/// Blocks of [source]; a line indented under a list item continues it.
List<MdBlock> parseMarkdownLite(String source){
  final out=<MdBlock>[];
  final para=<String>[];
  void flush(){if(para.isNotEmpty){out.add(MdBlock(MdKind.paragraph,para.join(' ')));para.clear();}}
  for(final raw in source.replaceAll('\r\n','\n').split('\n')){
    final line=raw.trimRight();
    final text=line.trim();
    if(text.isEmpty){flush();continue;}
    final h=_heading.firstMatch(text);
    if(h!=null&&!raw.startsWith(' ')){flush();out.add(MdBlock(MdKind.heading,h.group(2)!.trim(),level:h.group(1)!.length));continue;}
    final b=_bullet.firstMatch(text);
    if(b!=null){flush();out.add(MdBlock(MdKind.bullet,b.group(1)!.trim()));continue;}
    final n=_numbered.firstMatch(text);
    if(n!=null){flush();out.add(MdBlock(MdKind.numbered,n.group(2)!.trim(),level:int.parse(n.group(1)!)));continue;}
    // Indented line right after a list item: same item.
    if(para.isEmpty&&raw.startsWith(' ')&&out.isNotEmpty&&(out.last.kind==MdKind.bullet||out.last.kind==MdKind.numbered)){
      final last=out.removeLast();
      out.add(MdBlock(last.kind,'${last.text} $text',level:last.level));
      continue;
    }
    para.add(text);
  }
  flush();
  return out;
}

/// First title of level 1 (the name of the topic), or null.
String? markdownTitle(String source)=>parseMarkdownLite(source).where((b)=>b.kind==MdKind.heading&&b.level==1).firstOrNull?.text;

/// Text without the marks, for the search.
String markdownPlain(String source)=>parseMarkdownLite(source).map((b)=>b.text.replaceAll('**','')).join('\n');

/// « **gras** » as bold spans.
List<InlineSpan> markdownSpans(String text,TextStyle? bold){
  final parts=text.split('**');
  // An odd mark left alone stays as it is.
  if(parts.length.isEven)return [TextSpan(text:text)];
  return [for(var i=0;i<parts.length;i++)if(parts[i].isNotEmpty)TextSpan(text:parts[i],style:i.isOdd?bold:null)];
}

/// The blocks of [source] on screen; [skipTitle] leaves out the first
/// title of level 1 (shown in the bar of the page).
class MarkdownLite extends StatelessWidget {
  final String source;
  final bool skipTitle;
  const MarkdownLite(this.source,{super.key,this.skipTitle=false});

  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    final body=t.textTheme.bodyLarge;
    final bold=const TextStyle(fontWeight:FontWeight.w700);
    var blocks=parseMarkdownLite(source);
    if(skipTitle&&blocks.isNotEmpty&&blocks.first.kind==MdKind.heading&&blocks.first.level==1)blocks=blocks.sublist(1);
    Widget rich(String text,TextStyle? style)=>Text.rich(TextSpan(style:style,children:markdownSpans(text,bold)));
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      for(final b in blocks)switch(b.kind){
        MdKind.heading=>Semantics(header:true,child:Padding(padding:EdgeInsets.only(top:b.level==1?4:18,bottom:6),
          child:rich(b.text,(b.level==1?t.textTheme.headlineSmall:b.level==2?t.textTheme.titleLarge:t.textTheme.titleMedium)?.copyWith(fontWeight:FontWeight.w600)))),
        MdKind.paragraph=>Padding(padding:const EdgeInsets.only(bottom:10),child:rich(b.text,body)),
        MdKind.bullet||MdKind.numbered=>Padding(padding:const EdgeInsets.only(left:4,bottom:6),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          SizedBox(width:24,child:Text(b.kind==MdKind.bullet?'•':'${b.level}.',style:body)),
          Expanded(child:rich(b.text,body)),
        ])),
      },
    ]);
  }
}
