/// Thread « MeshCore · nom du nœud » (lot 17): a private conversation with
/// a MeshCore companion, opened by « Écrire » (card of the node on the map,
/// list of Outils › MeshCore) or from Messages. Short messages (character
/// counter), each with its state: envoi…, envoyé, reçu par le nœud
/// (MeshCore acknowledgement), échec (« Renvoyer »).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../ui/link_status.dart';
import '../../ui/overlay_page.dart';
import 'meshcore_chat.dart';
import 'meshcore_link.dart';
import 'meshcore_protocol.dart';

/// Opens the thread of a node (created when new).
Future<void> openMeshCoreChat(BuildContext context,String key,String name){
  final t=MeshCoreChats.instance.open(key,name);
  return showOverlayPage<void>(context,(_)=>MeshCoreChatPage(prefix:t.prefix));
}

/// Title of a thread: « MeshCore · nom ».
String meshCoreThreadTitle(MeshCoreThread t)=>S.t('mesh.thread',{'name':t.name});

/// State of a message in words (« reçu par le nœud »…).
String meshCoreMsgStateText(MeshCoreMsgState s)=>S.t('mesh.msg.${s.name}');

IconData meshCoreMsgStateIcon(MeshCoreMsgState s)=>switch(s){
  MeshCoreMsgState.sending=>Icons.schedule,MeshCoreMsgState.sent=>Icons.done,MeshCoreMsgState.delivered=>Icons.done_all,
  MeshCoreMsgState.failed=>Icons.error_outline,MeshCoreMsgState.received=>Icons.call_received};

class MeshCoreChatPage extends StatefulWidget {
  final String prefix;
  const MeshCoreChatPage({super.key,required this.prefix});
  @override State<MeshCoreChatPage> createState()=>_MeshCoreChatPageState();
}

class _MeshCoreChatPageState extends State<MeshCoreChatPage> {
  final chats=MeshCoreChats.instance, link=MeshCoreLink.instance;
  final _text=TextEditingController();
  final _scroll=ScrollController();

  @override void initState(){
    super.initState();
    chats.openThread=widget.prefix;
    chats.addListener(_changed); link.addListener(_changed);
    // After the first frame: the list of Messages rebuilds its unread count.
    WidgetsBinding.instance.addPostFrameCallback((_)=>chats.markRead(widget.prefix));
  }
  @override void dispose(){
    if(chats.openThread==widget.prefix)chats.openThread=null;
    chats.removeListener(_changed); link.removeListener(_changed);
    _text.dispose(); _scroll.dispose();
    super.dispose();
  }
  void _changed(){
    if(!mounted)return;
    chats.markRead(widget.prefix);
    setState((){});
    WidgetsBinding.instance.addPostFrameCallback((_){if(_scroll.hasClients)_scroll.jumpTo(_scroll.position.maxScrollExtent);});
  }

  bool get _connected=>link.state==MeshCoreState.connected;

  Future<void> _send() async {
    final t=chats.thread(widget.prefix);
    final text=_text.text;
    if(t==null||!_connected||!meshCoreTextFits(text))return;
    _text.clear();
    await chats.write(t.prefix,t.name,text);
  }

  static String _hm(DateTime t){final l=t.toLocal();String two(int v)=>v.toString().padLeft(2,'0');return '${two(l.hour)}:${two(l.minute)}';}

  Widget _bubble(MeshCoreChatMessage m){
    final s=Theme.of(context).colorScheme, small=Theme.of(context).textTheme.bodySmall;
    final failed=m.state==MeshCoreMsgState.failed;
    return Align(alignment:m.mine?Alignment.centerRight:Alignment.centerLeft,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),
      child:Container(key:ValueKey('mesh-msg-${m.id}'),margin:const EdgeInsets.symmetric(horizontal:10,vertical:3),padding:const EdgeInsets.fromLTRB(10,6,10,4),
        decoration:BoxDecoration(color:m.mine?s.primaryContainer:s.surfaceContainerHighest,borderRadius:BorderRadius.circular(10)),
        child:Column(crossAxisAlignment:CrossAxisAlignment.end,mainAxisSize:MainAxisSize.min,children:[
          Align(alignment:Alignment.centerLeft,child:SelectableText(m.text)),
          Row(mainAxisSize:MainAxisSize.min,children:[
            Text(_hm(m.at),style:small),
            if(m.mine)...[const SizedBox(width:6),
              Icon(meshCoreMsgStateIcon(m.state),size:14,color:failed?s.error:m.state==MeshCoreMsgState.delivered?Colors.blue:small?.color),
              const SizedBox(width:3),
              Text(meshCoreMsgStateText(m.state),key:ValueKey('mesh-msg-state-${m.id}'),style:small?.copyWith(color:failed?s.error:null))],
          ]),
          if(m.mine&&failed&&_connected)TextButton(key:ValueKey('mesh-msg-retry-${m.id}'),
            onPressed:()=>unawaited(chats.retry(widget.prefix,m)),child:Text(S.t('mesh.retry'))),
        ]))));
  }

  @override Widget build(BuildContext context){
    final t=chats.thread(widget.prefix);
    final s=Theme.of(context).colorScheme, small=Theme.of(context).textTheme.bodySmall;
    final messages=t?.messages??const <MeshCoreChatMessage>[];
    final fits=meshCoreTextFits(_text.text);
    return Scaffold(
      appBar:LinkedAppBar(title:Text(t==null?S.t('mesh.tool'):meshCoreThreadTitle(t),overflow:TextOverflow.ellipsis)),
      body:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        if(!_connected)Material(color:s.errorContainer,child:Padding(padding:const EdgeInsets.all(10),
          child:Text(S.t('mesh.chat.noModule'),key:const ValueKey('mesh-chat-offline'),style:TextStyle(color:s.onErrorContainer)))),
        Expanded(child:messages.isEmpty
          ?Center(child:Padding(padding:const EdgeInsets.all(24),child:Text(S.t('mesh.chat.help'),textAlign:TextAlign.center,style:small)))
          :ListView.builder(controller:_scroll,padding:const EdgeInsets.symmetric(vertical:8),itemCount:messages.length,itemBuilder:(_,i)=>_bubble(messages[i]))),
        SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(10,4,6,8),child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
          Expanded(child:TextField(key:const ValueKey('mesh-chat-field'),controller:_text,minLines:1,maxLines:4,
            maxLength:meshCoreMaxText,maxLengthEnforcement:MaxLengthEnforcement.enforced,
            textCapitalization:TextCapitalization.sentences,enabled:_connected,
            onChanged:(_)=>setState((){}),onSubmitted:(_)=>unawaited(_send()),
            decoration:InputDecoration(hintText:S.t('mesh.chat.hint')))),
          const SizedBox(width:6),
          Padding(padding:const EdgeInsets.only(bottom:20),child:IconButton.filled(key:const ValueKey('mesh-chat-send'),tooltip:S.t('mesh.send'),
            onPressed:_connected&&fits?()=>unawaited(_send()):null,icon:const Icon(Icons.send))),
        ]))),
      ]));
  }
}

/// The MeshCore threads in the list of Messages (after the conversations of
/// the event): « MeshCore · nom », last message, unread count.
class MeshCoreThreadTiles extends StatelessWidget {
  const MeshCoreThreadTiles({super.key});
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:MeshCoreChats.instance,builder:(context,_){
    final threads=MeshCoreChats.instance.threads.where((t)=>t.messages.isNotEmpty).toList();
    if(threads.isEmpty)return const SizedBox.shrink();
    final s=Theme.of(context).colorScheme;
    return Column(mainAxisSize:MainAxisSize.min,children:[for(final t in threads)ListTile(key:ValueKey('mesh-thread-${t.prefix}'),
      leading:const CircleAvatar(radius:22,backgroundColor:Color(0xFF00838F),foregroundColor:Colors.white,child:Icon(Icons.hub_outlined)),
      title:Text(meshCoreThreadTitle(t),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w600)),
      subtitle:t.last==null?null:Text(t.last!.text,maxLines:1,overflow:TextOverflow.ellipsis),
      trailing:t.unread==0?null:Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:2),
        decoration:BoxDecoration(color:s.primary,borderRadius:BorderRadius.circular(12)),
        child:Text('${t.unread}',style:TextStyle(color:s.onPrimary,fontSize:11,fontWeight:FontWeight.w700))),
      onTap:()=>unawaited(openMeshCoreChat(context,t.prefix,t.name)))]);
  });
}
