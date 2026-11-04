// SPDX-License-Identifier: MPL-2.0
// © SDUBOS Consulting et contributeurs SARCADE

/// Thread « Meshtastic · nom » (lot 28, point 3): a direct conversation
/// with a node, or the primary channel; opened by « Écrire » (card of the
/// node, list of Outils › Meshtastic), « Canal principal » or from
/// Messages. Same screen as MeshCore: short messages (200 bytes), each
/// with its state, « Renvoyer » on a failure, the « N non lus » separator.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../ui/link_status.dart';
import '../../ui/overlay_page.dart';
import '../meshcore/meshcore_chat_page.dart' show meshCoreMsgStateIcon, meshCoreMsgStateText;
import '../messages/chat_bottom.dart';
import 'meshtastic_chat.dart';
import 'meshtastic_link.dart';
import 'meshtastic_protocol.dart';

/// Opens a thread (created when new): a node « !a1b2c3d4 », or the
/// primary channel ([meshtasticChannelKey]).
Future<void> openMeshtasticChat(BuildContext context,String key,String name){
  final t=MeshtasticChats.instance.open(key,name);
  return showOverlayPage<void>(context,(_)=>MeshtasticChatPage(threadKey:t.key));
}

/// « Écrire » to a node.
Future<void> openMeshtasticNodeChat(BuildContext context,MeshtasticNode n)=>openMeshtasticChat(context,n.id,n.name);

/// « Canal principal »: the thread of the primary channel.
Future<void> openMeshtasticChannel(BuildContext context)=>
  openMeshtasticChat(context,meshtasticChannelKey,MeshtasticLink.instance.channelName??'');

/// Name of a thread: the node, or « Canal principal · LongFast ».
String meshtasticThreadName(MeshtasticThread t)=>!t.channel?t.name
  :t.name.isEmpty?S.t('meshtastic.channel'):'${S.t('meshtastic.channel')} · ${t.name}';

/// Title of a thread: « Meshtastic · nom ».
String meshtasticThreadTitle(MeshtasticThread t)=>S.t('meshtastic.thread',{'name':meshtasticThreadName(t)});

class MeshtasticChatPage extends StatefulWidget {
  final String threadKey;
  const MeshtasticChatPage({super.key,required this.threadKey});
  @override State<MeshtasticChatPage> createState()=>_MeshtasticChatPageState();
}

class _MeshtasticChatPageState extends State<MeshtasticChatPage> {
  final chats=MeshtasticChats.instance, link=MeshtasticLink.instance;
  final _text=TextEditingController();
  final _scroll=ScrollController();
  final _separator=SeparatorWatch();
  String? _firstUnreadId;
  int _unreadAtOpen=0;
  bool _atBottom=true;

  @override void initState(){
    super.initState();
    final t=chats.thread(widget.threadKey);
    if(t!=null&&t.unread>0){
      final i=firstUnreadReceived([for(final m in t.messages)m.mine],t.unread);
      if(i!=null){_firstUnreadId=t.messages[i].id;_unreadAtOpen=t.messages.skip(i).where((m)=>!m.mine).length;}
    }
    chats.openThread=widget.threadKey;
    chats.addListener(_changed); link.addListener(_changed);
    _scroll.addListener((){
      final atBottom=chatAtBottom(_scroll);
      if(atBottom!=_atBottom&&mounted)setState(()=>_atBottom=atBottom);
      _watchSeparator();
    });
    WidgetsBinding.instance.addPostFrameCallback((_){chats.markRead(widget.threadKey);_toBottom();});
  }

  void _toBottom(){
    chatJumpToBottom(_scroll,alive:()=>mounted);
    _watchSeparator();
  }
  void _watchSeparator()=>_separator.check(alive:()=>mounted,changed:()=>setState((){}));

  Future<void> _toUnread() async {
    final messages=chats.thread(widget.threadKey)?.messages??const <MeshtasticChatMessage>[];
    final i=messages.indexWhere((m)=>m.id==_firstUnreadId);
    setState((){_separator.seen=true;_atBottom=false;});
    if(i<0)return;
    await chatScrollToKey(_scroll,_separator.key,i,messages.length,alive:()=>mounted);
  }

  @override void dispose(){
    if(chats.openThread==widget.threadKey)chats.openThread=null;
    chats.removeListener(_changed); link.removeListener(_changed);
    _text.dispose(); _scroll.dispose();
    super.dispose();
  }

  void _changed(){
    if(!mounted)return;
    chats.markRead(widget.threadKey);
    final follow=_atBottom;
    setState((){});
    if(follow)WidgetsBinding.instance.addPostFrameCallback((_)=>_toBottom());
  }

  Future<void> _send() async {
    final t=chats.thread(widget.threadKey);
    final text=_text.text;
    if(t==null||!link.connected||!meshtasticTextFits(text))return;
    _text.clear();
    await chats.write(t.key,t.name,text);
  }

  static String _hm(DateTime t){final l=t.toLocal();String two(int v)=>v.toString().padLeft(2,'0');return '${two(l.hour)}:${two(l.minute)}';}

  Widget _bubble(MeshtasticChatMessage m){
    final s=Theme.of(context).colorScheme, small=Theme.of(context).textTheme.bodySmall;
    final failed=m.state==MeshtasticMsgState.failed;
    return Align(alignment:m.mine?Alignment.centerRight:Alignment.centerLeft,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),
      child:Container(key:ValueKey('meshtastic-msg-${m.id}'),margin:const EdgeInsets.symmetric(horizontal:10,vertical:3),padding:const EdgeInsets.fromLTRB(10,6,10,4),
        decoration:BoxDecoration(color:m.mine?s.primaryContainer:s.surfaceContainerHighest,borderRadius:BorderRadius.circular(10)),
        child:Column(crossAxisAlignment:CrossAxisAlignment.end,mainAxisSize:MainAxisSize.min,children:[
          if(m.sender!=null)Align(alignment:Alignment.centerLeft,child:Text(m.sender!,style:small?.copyWith(fontWeight:FontWeight.w700))),
          Align(alignment:Alignment.centerLeft,child:SelectableText(m.text)),
          Row(mainAxisSize:MainAxisSize.min,children:[
            Text(_hm(m.at),style:small),
            if(m.mine)...[const SizedBox(width:6),
              Icon(meshCoreMsgStateIcon(m.state),size:14,color:failed?s.error:m.state==MeshtasticMsgState.delivered?Colors.blue:small?.color),
              const SizedBox(width:3),
              Text(meshCoreMsgStateText(m.state),key:ValueKey('meshtastic-msg-state-${m.id}'),style:small?.copyWith(color:failed?s.error:null))],
          ]),
          if(m.mine&&failed&&link.connected)TextButton(key:ValueKey('meshtastic-msg-retry-${m.id}'),
            onPressed:()=>unawaited(chats.retry(widget.threadKey,m)),child:Text(S.t('mesh.retry'))),
        ]))));
  }

  @override Widget build(BuildContext context){
    final t=chats.thread(widget.threadKey);
    final s=Theme.of(context).colorScheme, small=Theme.of(context).textTheme.bodySmall;
    final messages=t?.messages??const <MeshtasticChatMessage>[];
    final bytes=utf8.encode(_text.text.trim()).length;
    final fits=meshtasticTextFits(_text.text);
    return Scaffold(
      appBar:LinkedAppBar(title:Text(t==null?S.t('meshtastic.tool'):meshtasticThreadTitle(t),overflow:TextOverflow.ellipsis)),
      body:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        if(!link.connected)Material(color:s.errorContainer,child:Padding(padding:const EdgeInsets.all(10),
          child:Text(S.t('meshtastic.chat.noModule'),key:const ValueKey('meshtastic-chat-offline'),style:TextStyle(color:s.onErrorContainer)))),
        Expanded(child:messages.isEmpty
          ?Center(child:Padding(padding:const EdgeInsets.all(24),child:Text(S.t(t?.channel==true?'meshtastic.chat.channelHelp':'mesh.chat.help'),textAlign:TextAlign.center,style:small)))
          :Stack(children:[
            StickToBottom(controller:_scroll,stick:()=>_atBottom,child:ListView.builder(controller:_scroll,padding:const EdgeInsets.symmetric(vertical:8),itemCount:messages.length,itemBuilder:(_,i){
              final m=messages[i];
              if(m.id!=_firstUnreadId)return _bubble(m);
              return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                Padding(key:_separator.key,padding:const EdgeInsets.symmetric(vertical:6),child:Center(child:Chip(
                  label:Text(S.t('messages.unreadSeparator',{'n':_unreadAtOpen})),visualDensity:VisualDensity.compact))),
                _bubble(m),
              ]);
            })),
            if(_firstUnreadId!=null&&_unreadAtOpen>0&&!_separator.seen)Positioned(top:10,left:0,right:0,child:Center(
              child:UnreadUpButton(count:_unreadAtOpen,onPressed:()=>unawaited(_toUnread())))),
          ])),
        SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(10,4,6,8),child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
          Expanded(child:TextField(key:const ValueKey('meshtastic-chat-field'),controller:_text,minLines:1,maxLines:4,
            textCapitalization:TextCapitalization.sentences,enabled:link.connected,
            onChanged:(_)=>setState((){}),onSubmitted:(_)=>unawaited(_send()),
            decoration:InputDecoration(hintText:S.t('mesh.chat.hint'),
              counterText:'$bytes / $meshtasticMaxTextBytes',
              counterStyle:bytes>meshtasticMaxTextBytes?TextStyle(color:s.error):null))),
          const SizedBox(width:6),
          Padding(padding:const EdgeInsets.only(bottom:20),child:IconButton.filled(key:const ValueKey('meshtastic-chat-send'),tooltip:S.t('mesh.send'),
            onPressed:link.connected&&fits?()=>unawaited(_send()):null,icon:const Icon(Icons.send))),
        ]))),
      ]));
  }
}

/// The Meshtastic threads in the list of Messages (after the MeshCore
/// ones): « Meshtastic · nom », last message, unread count.
class MeshtasticThreadTiles extends StatelessWidget {
  const MeshtasticThreadTiles({super.key});
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:MeshtasticChats.instance,builder:(context,_){
    final threads=MeshtasticChats.instance.threads.where((t)=>t.messages.isNotEmpty).toList();
    if(threads.isEmpty)return const SizedBox.shrink();
    final s=Theme.of(context).colorScheme;
    return Column(mainAxisSize:MainAxisSize.min,children:[for(final t in threads)ListTile(key:ValueKey('meshtastic-thread-${t.key}'),
      leading:CircleAvatar(radius:22,backgroundColor:const Color(0xFF2E7D32),foregroundColor:Colors.white,child:Icon(t.channel?Icons.groups_outlined:Icons.wifi_tethering)),
      title:Text(meshtasticThreadTitle(t),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w600)),
      subtitle:t.last==null?null:Text(t.last!.sender==null?t.last!.text:'${t.last!.sender} : ${t.last!.text}',maxLines:1,overflow:TextOverflow.ellipsis),
      trailing:t.unread==0?null:Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:2),
        decoration:BoxDecoration(color:s.primary,borderRadius:BorderRadius.circular(12)),
        child:Text('${t.unread}',style:TextStyle(color:s.onPrimary,fontSize:11,fontWeight:FontWeight.w700))),
      onTap:()=>unawaited(openMeshtasticChat(context,t.key,t.name)))]);
  });
}
