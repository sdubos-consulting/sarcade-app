/// SOS reçu sur ce poste (décision du porteur, 29 Oct 2026): a red banner
/// stays while a distress of another operator is not closed by its « Fin de
/// détresse »; « Couper le son » silences this device only (reminders and
/// notification of the distress messages already received). A new distress
/// rings again.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/message.dart';
import 'sos_map.dart';

bool isDistressMessage(SarcadeMessage m)=>m.priority=='immediate'&&m.body.trimLeft().startsWith('🆘');

bool isDistressEnd(SarcadeMessage m){
  final b=m.body.trim().toLowerCase();
  return b.startsWith('fin de détresse')||b.startsWith('end of distress');
}

/// Distress not closed, by sender (last « 🆘 » message of each sender not
/// followed by its « Fin de détresse »), general messages only, other
/// senders than [deviceId].
Map<String,SarcadeMessage> openDistress(Iterable<SarcadeMessage> messages,String deviceId){
  final out=<String,SarcadeMessage>{};
  final list=messages.where((m)=>m.recipientIds.isEmpty&&m.senderId!=deviceId).toList()
    ..sort((a,b)=>a.createdAt.compareTo(b.createdAt));
  for(final m in list){
    if(isDistressMessage(m)){out[m.senderId]=m;}
    else if(isDistressEnd(m)){out.remove(m.senderId);}
  }
  return out;
}

/// Key of the distress messages silenced: the sound stays off until a new
/// distress message arrives.
String sosMuteKey(Iterable<SarcadeMessage> open)=>(open.map((m)=>m.id).toList()..sort()).join(',');

/// True when every open distress was already silenced on this device.
bool sosMuted(Iterable<SarcadeMessage> open,String? mutedIds){
  if(mutedIds==null||mutedIds.isEmpty)return false;
  final muted=mutedIds.split(',').toSet();
  return open.every((m)=>muted.contains(m.id));
}

/// Red banner of the distress of other operators. A touch centres the map
/// on the operator (lot 17, choice 3); several distresses: « 2 SOS » and one
/// pill per operator, each centring on him.
class SosAlertBanner extends StatelessWidget {
  final List<SosTarget> targets; final DateTime now; final bool muted; final VoidCallback onMute;
  final ValueChanged<SosTarget> onCenter;
  const SosAlertBanner({super.key,required this.targets,required this.now,required this.muted,required this.onMute,required this.onCenter});
  @override
  Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    final text=TextStyle(color:s.onError,fontWeight:FontWeight.w700);
    final single=targets.length==1;
    return Material(color:s.error,child:InkWell(key:const Key('sos-banner'),onTap:single?()=>onCenter(targets.first):null,
      child:Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),
      child:Row(children:[
        Icon(Icons.sos,color:s.onError),const SizedBox(width:10),
        if(single)Expanded(child:Text('${S.t('sos.received',{'who':targets.first.label})} · ${sosAge(targets.first,now)}',style:text))
        else ...[
          Text(S.t('sos.count',{'n':targets.length}),style:text),const SizedBox(width:10),
          Expanded(child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
            for(final t in targets)Padding(padding:const EdgeInsets.only(right:6),child:Material(color:s.onError.withValues(alpha:0.18),shape:const StadiumBorder(),
              child:InkWell(key:ValueKey('sos-target-${t.deviceId}'),customBorder:const StadiumBorder(),onTap:()=>onCenter(t),
                child:Padding(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
                  child:Text('${t.label} · ${sosAge(t,now)}',style:text.copyWith(fontSize:13)))))),
          ]))),
        ],
        if(muted)Padding(padding:const EdgeInsets.only(left:8),child:Icon(Icons.volume_off,color:s.onError,semanticLabel:S.t('sos.muted')))
        else FilledButton.icon(key:const Key('sos-mute'),onPressed:onMute,
          style:FilledButton.styleFrom(backgroundColor:s.onError,foregroundColor:s.error),
          icon:const Icon(Icons.volume_off),label:Text(S.t('sos.mute'))),
      ]))));
  }
}
