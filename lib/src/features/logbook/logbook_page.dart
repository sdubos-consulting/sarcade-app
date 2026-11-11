/// Main courante (card « lisible, filtrable, du plus récent au plus
/// ancien », lot 29.5): newest first with day headers, search and filters,
/// coloured icon per kind, short labels at the minute (the second in the
/// detail), consecutive actions grouped, « + Note » and « Exporter en
/// CSV » in the ⋮ menu; pull down to refresh.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import '../../ui/menu_entry.dart';

import '../../l10n/strings.dart';
import '../../models/message.dart';
import '../../offline/sync_service.dart';
import '../../platform/platform_services.dart';
import '../../services/sarcade_api.dart';
import '../../ui/link_status.dart';
import 'logbook_view.dart';
import '../../ui/theme.dart' show searchInputBorder;

class LogbookPage extends StatefulWidget {
 final SarcadeApi api; final String eventId;
 /// Author of the notes; by default the terminal of the device.
 final String? actorId;
 const LogbookPage({super.key,required this.api,required this.eventId,this.actorId});
 @override State<LogbookPage> createState()=>_LogbookPageState();
}

class _LogbookPageState extends State<LogbookPage>{
 List<LogbookEntry> entries=[]; bool loading=true;
 /// Author of the notes: given, else the terminal kept on the device.
 String? get _actor=>widget.actorId??OfflineSyncService.active?.store.storedConfig()?['device_id'] as String?;
 LogKind? _filter; String _query='';
 final Set<int> _open={};
 /// Sections opened or closed by hand (key: logSectionKey); by default only
 /// today's is open (card « Main courante : page trop longue », 8 Nov 2026).
 final Map<String,bool> _sections={};
 /// Days shown, 7 more each time « Afficher les semaines précédentes ».
 int _days=logPeriodDays;
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
   LogKind.drawing=>const Color(0xFF8E24AA),LogKind.message=>const Color(0xFF0B57D0),LogKind.link=>const Color(0xFF00838F),_=>const Color(0xFF5F6368)};
 static IconData kindIcon(LogKind k)=>switch(k){
   LogKind.sos=>Icons.sos,LogKind.order=>Icons.flag_outlined,LogKind.note=>Icons.edit_note,
   LogKind.drawing=>Icons.draw_outlined,LogKind.message=>Icons.chat_bubble_outline,LogKind.access=>Icons.lock_outline,LogKind.link=>Icons.wifi_tethering,
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
     final e=await widget.api.addLogbookNote(widget.eventId,actorId:_actor!,text:text.trim());
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
   try{path=await saveFile(name,const Utf8Codec().encode(logbookCsv(shown,eventId:widget.eventId)),mimeType:'text/csv');}catch(_){path=null;}
   messenger.showSnackBar(SnackBar(content:Text(path==null?S.t('logbook.csvFailed'):S.t('logbook.csvSaved',{'n':shown.length})),
     action:path==null||!canOpenSavedFiles?null:SnackBarAction(label:S.t('map.open'),onPressed:()=>openSavedFile(path!))));
 }

 @override Widget build(BuildContext context){
   final t=Theme.of(context); final s=t.colorScheme;
   final shown=logbookShown(entries,filter:_filter,query:_query);
   final now=DateTime.now();
   // The search covers the whole Main courante; otherwise the last [_days] days.
   final searching=_query.trim().isNotEmpty;
   final recent=searching?shown:[for(final e in shown)if(inLogPeriod(e.time,now,_days))e];
   final hasOlder=!searching&&recent.length<shown.length;
   final lines=logbookLines(recent);
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
   // Sections by day (by week beyond 7 days), today's open; all open while searching.
   final sections=<String,List<LogLine>>{};
   for(final ln in lines){(sections[logSectionKey(ln.first.time,now)]??=[]).add(ln);}
   final todayKey=logSectionKey(now,now);
   final children=<Widget>[];
   for(final e in sections.entries){
     final open=searching||(_sections[e.key]??e.key==todayKey);
     final count=e.value.fold<int>(0,(n,l)=>n+l.entries.length);
     children.add(InkWell(key:ValueKey('logbook-section-${e.key}'),
       onTap:searching?null:()=>setState(()=>_sections[e.key]=!open),
       child:Padding(padding:const EdgeInsets.fromLTRB(16,14,12,6),child:Row(children:[
         Expanded(child:Text(logSectionLabel(e.key,now),style:t.textTheme.titleSmall?.copyWith(color:s.primary))),
         Text(S.t('logbook.entries',{'n':count}),style:t.textTheme.bodySmall?.copyWith(color:s.onSurfaceVariant)),
         if(!searching)Icon(open?Icons.expand_less:Icons.expand_more,color:s.onSurfaceVariant),
       ]))));
     if(open)children.addAll(e.value.map(line));
   }
   if(hasOlder){
     children.add(Padding(padding:const EdgeInsets.fromLTRB(16,12,16,0),child:OutlinedButton.icon(key:const ValueKey('logbook-older'),
       onPressed:()=>setState(()=>_days+=7),icon:const Icon(Icons.history),label:Text(S.t('logbook.older')))));
   }
   return Scaffold(
     appBar:LinkedAppBar(title:Text(S.t('map.logbook')),actions:[
       PopupMenuButton<String>(key:const ValueKey('logbook-menu'),onSelected:(v){if(v=='csv')_exportCsv();},
         itemBuilder:(_)=>[PopupMenuItem(value:'csv',child:menuEntry(context,icon:Icons.table_view_outlined,title:S.t('logbook.csv')))]),
     ]),
     floatingActionButton:_actor==null?null:FloatingActionButton.extended(key:const ValueKey('logbook-note'),
       onPressed:_addNote,icon:const Icon(Icons.add),label:Text(S.t('logbook.note'))),
     body:Column(children:[
       Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),child:TextField(onChanged:(v)=>setState(()=>_query=v),
         textInputAction:TextInputAction.search,
         decoration:InputDecoration(isDense:true,prefixIcon:const Icon(Icons.search),hintText:S.t('logbook.search'),
           border:searchInputBorder))),
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
