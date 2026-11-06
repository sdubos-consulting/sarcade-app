/// « Appuyer pour parler » above the field of a conversation (lot 29):
/// press and hold; who talks is shown; the headset joins or leaves the
/// voice channel of the conversation.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import 'ptt.dart';

/// The headset of the header: joins the voice channel of the conversation.
class PttHeaderButton extends StatelessWidget{
  final String? channel; final String name;
  const PttHeaderButton({super.key,required this.channel,required this.name});
  @override
  Widget build(BuildContext context)=>ListenableBuilder(listenable:Ptt.instance,builder:(c,_){
    final p=Ptt.instance;
    if(!p.available||channel==null||p.channelById(channel)==null)return const SizedBox.shrink();
    final here=p.channel==channel&&p.state!=PttState.off&&p.state!=PttState.error;
    return IconButton(key:const ValueKey('ptt-header'),tooltip:S.t(here?'ptt.leave':'ptt.join'),
      isSelected:here,selectedIcon:Icon(Icons.headset_mic,color:Theme.of(c).colorScheme.primary),
      onPressed:()=>here?p.leave():p.join(channel!,name:name),icon:const Icon(Icons.headset_mic_outlined));
  });
}

/// The bar shown while this conversation's channel is joined.
class PttBar extends StatelessWidget{
  final String? channel;
  const PttBar({super.key,required this.channel});
  @override
  Widget build(BuildContext context)=>ListenableBuilder(listenable:Ptt.instance,builder:(c,_){
    final p=Ptt.instance;
    if(channel==null||p.channel!=channel||p.state==PttState.off)return const SizedBox.shrink();
    final s=Theme.of(c).colorScheme;
    final talking=p.state==PttState.talking;
    final String line=switch(p.state){
      PttState.connecting=>S.t('ptt.connecting'),
      PttState.error=>S.t('ptt.error'),
      PttState.talking=>S.t('ptt.youTalk'),
      _=>p.speakers.isEmpty?S.t(p.canTalk?'ptt.hold':'ptt.listenOnly'):S.t('ptt.talks',{'n':p.speakers.length,'who':p.speakers.join(', ')}),
    };
    final ready=p.canTalk&&(p.state==PttState.listening||talking);
    return Material(key:const ValueKey('ptt-bar'),color:talking?s.errorContainer:s.secondaryContainer,child:Padding(
      padding:const EdgeInsets.fromLTRB(12,6,8,6),child:Row(children:[
        Icon(p.speakers.isNotEmpty?Icons.graphic_eq:Icons.headset_mic,size:20,color:talking?s.onErrorContainer:s.onSecondaryContainer),
        const SizedBox(width:8),
        Expanded(child:Text(line,key:const ValueKey('ptt-line'),maxLines:1,overflow:TextOverflow.ellipsis,
          style:TextStyle(color:talking?s.onErrorContainer:s.onSecondaryContainer))),
        if(p.canTalk)Listener(
          onPointerDown:ready?(_){HapticFeedback.mediumImpact();p.talk(true);}:null,
          onPointerUp:(_){if(talking)p.talk(false);},
          onPointerCancel:(_){if(talking)p.talk(false);},
          child:AnimatedContainer(key:const ValueKey('ptt-talk'),duration:const Duration(milliseconds:120),width:talking?64:56,height:talking?64:56,
            decoration:BoxDecoration(shape:BoxShape.circle,color:ready?(talking?s.error:s.primary):s.outlineVariant),
            child:Icon(Icons.mic,color:talking?s.onError:s.onPrimary,size:28))),
        IconButton(tooltip:S.t('ptt.leave'),onPressed:p.leave,icon:const Icon(Icons.close)),
      ])));
  });
}
