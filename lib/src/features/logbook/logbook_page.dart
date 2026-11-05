/// Main courante (card « lisible, filtrable, du plus récent au plus
/// ancien », lot 29.5): newest first with day headers, search and filters,
/// coloured icon per kind, short labels at the minute (the second in the
/// detail), consecutive actions grouped, « + Note » and « Exporter en
/// CSV » in the ⋮ menu; pull down to refresh.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/message.dart';
import '../../platform/platform_services.dart';
import '../../services/sarcade_api.dart';
import '../../ui/link_status.dart';
import 'logbook_view.dart';

class LogbookPage extends StatefulWidget {
 final SarcadeApi api; final String eventId;
 /// Author of the notes; null: no « + Note ».
 final String? actorId;
 const LogbookPage({super.key,required this.api,required this.eventId,this.actorId});
 @override State<LogbookPage> createState()=>_LogbookPageState();
}

class _LogbookPageState extends State<LogbookPage>{
 List<LogbookEntry> entries=[]; bool loading=true;
 LogKind? _filter; String _query='';
 final Set<int> _open={};
 @override void initState(){super.initState();_load();}

 /// Every page of the server (500 entries a page, oldest first).
 Future<void> _load() async {
   try{
     final all=<LogbookEntry>[]; var after=0;
     for(var i=0;i<40;i++){
       final page=await widget.api.logbook(widget.eventId,after:after);
       all.addAll(page);
       if(page.length<500)break;
       after=page.last.seq;
     }
     entries=all;
   }finally{if(mounted)setState(()=>loading=false);}
 }

 /// Colour of the icon of a kind.
 static Color kindColor(LogKind k)=>switch(k){
   LogKind.sos=>const Color(0xFFD93025),LogKind.order=>const Color(0xFFE8710A),LogKind.note=>const Color(0xFF188038),
   LogKind.drawing=>const Color(0xFF8E24AA),LogKind.message=>const Color(0xFF0B57D0),_=>const Color(0xFF5F6368)};
 static IconData kindIcon(LogKind k)=>switch(k){
   LogKind.sos=>Icons.sos,LogKind.order=>Icons.flag_outlined,LogKind.note=>Icons.edit_note,
   LogKind.drawing=>Icons.draw_outlined,LogKind.message=>Icons.chat_bubble_outline,LogKind.access=>Icons.lock_outline,
   LogKind.other=>Icons.receipt_long_outlined};

 Widget _icon(LogKind k)=>CircleAvatar(radius:16,backgroundColor:kindColor(k).withValues(alpha:0.14),child:Icon(kindIcon(k),size:18,color:kindColor(k)));

 void _detail(LogbookEntry e){
   final l=e.time.toLocal();
   showDialog<void>(context:context,builder:(c)=>AlertDialog(
     title:Text(logKindLabel(logKind(e))),
     content:SelectableText('${l.day}/${l.month}/${l.year} ${logHms(e.time)}\n${e.actorId??'-'}\n\n${e.summary}'),
     actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.close')))]));
 }

 Future<void> _addNote() async {
   final ctl=TextEditingController();
   final text=await showDialog<String>(context:context,builder:(c)=>AlertDialog(
     title:Text(S.t('logbook.note')),
     content:TextField(controller:ctl,autofocus:true,minLines:2,maxLines:6,maxLength:2000,textCapitalization:TextCapitalization.sentences,
       decoration:InputDecoration(hintText:S.t('logbook.noteHint'))),
     actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
       FilledButton(onPressed:()=>Navigator.pop(c,ctl.text),child:Text(S.t('logbook.noteSave')))]));
   ctl.dispose();
   if(text==null||text.trim().isEmpty||!mounted)return;
   final messenger=ScaffoldMessenger.of(context);
   try{
     final e=await widget.api.addLogbookNote(widget.eventId,actorId:widget.actorId!,text:text.trim());
     if(mounted)setState(()=>entries=[...entries,e]);
   }catch(_){messenger.showSnackBar(SnackBar(content:Text(S.t('logbook.noteFailed'))));}
 }

 Future<void> _exportCsv() async {
   final shown=logbookShown(entries,filter:_filter,query:_query);
   final messenger=ScaffoldMessenger.of(context);
   final now=DateTime.now();
   String two(int v)=>v.toString().padLeft(2,'0');
   final name='main-courante-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}.csv';
   String? path;
   try{path=await saveFile(name,const Utf8Codec().encode(logbookCsv(shown)),mimeType:'text/csv');}catch(_){path=null;}
   messenger.showSnackBar(SnackBar(content:Text(path==null?S.t('logbook.csvFailed'):S.t('logbook.csvSaved',{'n':shown.length})),
     action:path==null||!canOpenSavedFiles?null:SnackBarAction(label:S.t('map.open'),onPressed:()=>openSavedFile(path!))));
 }

 @override Widget build(BuildContext context){
   final t=Theme.of(context); final s=t.colorScheme;
   final shown=logbookShown(entries,filter:_filter,query:_query);
   final lines=logbookLines(shown);
   final now=DateTime.now();
   Widget chip(LogKind? k)=>Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(key:ValueKey('logbook-filter-${k?.name??'all'}'),
     showCheckmark:false,label:Text(k==null?S.t('logbook.all'):logKindLabel(k)),selected:_filter==k,onSelected:(_)=>setState(()=>_filter=k)));
   Widget line(LogLine ln){
     final e=ln.first; final k=ln.kind;
     if(!ln.grouped){
       return ListTile(dense:true,leading:_icon(k),title:Text(shortSummary(e.summary),maxLines:2,overflow:TextOverflow.ellipsis),
         subtitle:Text('${e.actorId??'-'} · ${logHm(e.time)}'),onTap:()=>_detail(e));
     }
     final open=_open.contains(e.seq);
     return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
       ListTile(dense:true,leading:_icon(k),
         title:Text('${logKindLabel(k)} · ${e.actorId??'-'} · ${groupDetail(ln.entries)}',maxLines:2,overflow:TextOverflow.ellipsis),
         subtitle:Text('${logHm(ln.entries.last.time)} – ${logHm(e.time)}'),
         trailing:Icon(open?Icons.expand_less:Icons.expand_more),
         onTap:()=>setState((){if(!open){_open.add(e.seq);}else{_open.remove(e.seq);}})),
       if(open)for(final x in ln.entries)Padding(padding:const EdgeInsets.only(left:40),child:ListTile(dense:true,
         title:Text(shortSummary(x.summary),maxLines:2,overflow:TextOverflow.ellipsis),subtitle:Text(logHm(x.time)),onTap:()=>_detail(x))),
     ]);
   }
   final children=<Widget>[];
   for(var i=0;i<lines.length;i++){
     final at=lines[i].first.time;
     if(i==0||!sameLogDay(lines[i-1].first.time,at)){
       children.add(Padding(padding:const EdgeInsets.fromLTRB(16,14,16,4),child:Text(logDayLabel(at,now),
         style:t.textTheme.titleSmall?.copyWith(color:s.primary))));
     }
     children.add(line(lines[i]));
   }
   return Scaffold(
     appBar:LinkedAppBar(title:Text(S.t('map.logbook')),actions:[
       PopupMenuButton<String>(key:const ValueKey('logbook-menu'),onSelected:(v){if(v=='csv')_exportCsv();},
         itemBuilder:(_)=>[PopupMenuItem(value:'csv',child:ListTile(leading:const Icon(Icons.table_view_outlined),title:Text(S.t('logbook.csv'))))]),
     ]),
     floatingActionButton:widget.actorId==null?null:FloatingActionButton.extended(key:const ValueKey('logbook-note'),
       onPressed:_addNote,icon:const Icon(Icons.add),label:Text(S.t('logbook.note'))),
     body:Column(children:[
       Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),child:TextField(onChanged:(v)=>setState(()=>_query=v),
         textInputAction:TextInputAction.search,
         decoration:InputDecoration(isDense:true,prefixIcon:const Icon(Icons.search),hintText:S.t('logbook.search'),filled:true,
           fillColor:s.surfaceContainerHigh,border:OutlineInputBorder(borderRadius:BorderRadius.circular(24),borderSide:BorderSide.none)))),
       SizedBox(height:48,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:12),
         children:[chip(null),for(final k in logFilters)chip(k)])),
       Expanded(child:loading?const Center(child:CircularProgressIndicator()):RefreshIndicator(
         onRefresh:()async{await _load();},
         child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.only(bottom:88),children:[
           if(lines.isEmpty)Padding(padding:const EdgeInsets.all(24),child:Center(child:Text(S.t('logbook.none')))),
           ...children,
         ]))),
     ]),
   );
 }
}
