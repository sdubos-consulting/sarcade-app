/// Event chosen automatically when the server has only one (lot 19, card
/// « Événement choisi automatiquement quand le serveur n'en a qu'un »,
/// 1 Nov 2026, after the Windows computer stayed on a wrong event):
/// 1) at the connection to a server and at every start, the list of the
///    open events (draft or active; closed ones do not count) is read;
/// 2) one open event: it is followed at once, « Événement suivi : … »;
/// 3) several: the list opens, the active ones first; none: « Aucun
///    événement ouvert », with « Créer » for the PCO;
/// 4) the followed event unknown to the server (404): one open → followed
///    at once, several → the list;
/// 5) a choice made by hand is never replaced while the server knows it.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/comm_group.dart' show isPco;
import '../../operations/event_settings.dart' show eventKinds;
import '../../services/sarcade_api.dart';

/// States of an open event (the server also hides the closed ones).
const openEventStates={'draft','active'};

/// Open events, the active ones first, then the drafts, each in the order
/// of the server (newest first).
List<Map<String,dynamic>> openEvents(Iterable<Map<String,dynamic>> all){
  final open=[for(final e in all)if(openEventStates.contains(e['status'])&&e['ended_at']==null)e];
  return [...open.where((e)=>e['status']=='active'),...open.where((e)=>e['status']!='active')];
}

/// What to do with the followed event.
enum EventPick { keep, auto, choose, none }

/// [current] followed event; [known] the server knows it (open or closed);
/// [manual] it was chosen by hand.
EventPick pickEvent({required List<Map<String,dynamic>> open,required String current,required bool known,required bool manual}){
  if(open.any((e)=>'${e['id']}'==current))return EventPick.keep;
  if(known&&manual)return EventPick.keep;
  if(open.length==1)return EventPick.auto;
  return open.isEmpty?EventPick.none:EventPick.choose;
}

/// Settings, list of a server just read: its only open event when the
/// event field is empty or not on this server (else null).
Map<String,dynamic>? singleOpenEvent(List<Map<String,dynamic>> all,String current){
  if(current.isNotEmpty&&all.any((e)=>'${e['id']}'==current))return null;
  final open=openEvents(all);
  return open.length==1?open.single:null;
}

/// Preference holding the event chosen by hand (its identifier, unique
/// whatever the address of the server, which may go to HTTPS).
const manualEventPref='event_manual';

/// Name of an event for the messages (its identifier when unnamed).
String eventName(Map<String,dynamic> e){final n='${e['name']??''}'.trim();return n.isEmpty?'${e['id']}':n;}

/// « Test NAS 1 · actif · 01/11 ».
String eventChoiceLabel(Map<String,dynamic> e){
  final t=DateTime.tryParse('${e['created_at']??''}')?.toLocal();
  String two(int v)=>v.toString().padLeft(2,'0');
  return [eventName(e),S.t('eventState.${e['status']}'),if(t!=null)'${two(t.day)}/${two(t.month)}'].join(' · ');
}

/// Follows [event]: saved in the configuration (the map restarts on it).
typedef FollowEvent=Future<void> Function(Map<String,dynamic> event,{required bool manual});

/// Reads the open events of the server and applies the rules above.
/// [unknown]: the server answered 404 for the followed event. Without
/// network, nothing changes. Returns what was done.
Future<EventPick?> checkFollowedEvent({required SarcadeApi api,required String current,required String deviceId,
    required bool manual,bool unknown=false,required BuildContext? Function() context,required FollowEvent follow}) async {
  var open=const <Map<String,dynamic>>[];
  var known=!unknown;
  try{
    open=openEvents(await api.events());
    if(!unknown&&!open.any((e)=>'${e['id']}'==current)){
      known=(await api.events(includeClosed:true)).any((e)=>'${e['id']}'==current);
    }
  }catch(_){
    return null;
  }
  final pick=pickEvent(open:open,current:current,known:known,manual:manual);
  switch(pick){
    case EventPick.keep:
      break;
    case EventPick.auto:
      await follow(open.single,manual:false);
      _snack(context,S.t('events.followed',{'name':eventName(open.single)}));
    case EventPick.choose:
    case EventPick.none:
      final ctx=context();
      if(ctx==null||!ctx.mounted)return pick;
      final e=pick==EventPick.choose?await showEventChoice(ctx,open,unknown:!known):await showNoOpenEvent(ctx,api:api,pco:isPco(deviceId));
      if(e!=null){await follow(e,manual:true);_snack(context,S.t('events.followed',{'name':eventName(e)}));}
  }
  return pick;
}

void _snack(BuildContext? Function() context,String text){
  // After the restart of the map on the new event.
  WidgetsBinding.instance.addPostFrameCallback((_){
    final ctx=context();
    if(ctx!=null&&ctx.mounted)ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content:Text(text)));
  });
}

/// The list of the open events, the active ones first.
Future<Map<String,dynamic>?> showEventChoice(BuildContext context,List<Map<String,dynamic>> open,{bool unknown=false})=>
  showDialog<Map<String,dynamic>>(context:context,builder:(c)=>SimpleDialog(
    key:const ValueKey('event-choice'),
    title:Text(S.t('events.choose')),
    children:[
      if(unknown)Padding(padding:const EdgeInsets.fromLTRB(24,0,24,8),child:Text(S.t('events.unknown'),style:Theme.of(c).textTheme.bodySmall)),
      for(final e in open)ListTile(key:ValueKey('event-choice-${e['id']}'),
        leading:Icon(e['status']=='active'?Icons.play_circle_outline:Icons.edit_note),
        title:Text(eventChoiceLabel(e),overflow:TextOverflow.ellipsis),
        onTap:()=>Navigator.pop(c,e)),
    ]));

/// « Aucun événement ouvert », with « Créer » for the PCO: the created
/// event is returned.
Future<Map<String,dynamic>?> showNoOpenEvent(BuildContext context,{required SarcadeApi api,required bool pco}) async {
  final create=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
    key:const ValueKey('event-none'),
    title:Text(S.t('events.noneOpen')),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.close'))),
      if(pco)FilledButton(key:const ValueKey('event-none-create'),onPressed:()=>Navigator.pop(c,true),child:Text(S.t('events.create'))),
    ]));
  if(create!=true||!context.mounted)return null;
  return createEventDialog(context,api);
}

/// Name and model, then `POST /events`; null when cancelled or refused
/// (said in a message).
Future<Map<String,dynamic>?> createEventDialog(BuildContext context,SarcadeApi api) async {
  final name=TextEditingController(); var kind=eventKinds.first;
  final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(title:Text(S.t('events.new')),
    content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      TextField(key:const ValueKey('event-new-name'),controller:name,autofocus:true,decoration:InputDecoration(labelText:S.t('events.name'))),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(initialValue:kind,isExpanded:true,decoration:InputDecoration(labelText:S.t('events.model')),
        items:[for(final k in eventKinds)DropdownMenuItem(value:k,child:Text(S.t('events.kind.$k')))],onChanged:(v)=>set(()=>kind=v??kind)),
    ]),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
      FilledButton(key:const ValueKey('event-new-create'),onPressed:()=>Navigator.pop(c,true),child:Text(S.t('events.create'))),
    ])));
  final n=name.text.trim(); name.dispose();
  if(ok!=true||n.isEmpty||!context.mounted)return null;
  final m=ScaffoldMessenger.maybeOf(context);
  try{
    return await api.createEvent(n,kind);
  }on SarcadeHttpException catch(e){
    m?.showSnackBar(SnackBar(content:Text(S.t(e.statusCode==403?'events.pcoOnly':'events.createFailed',{'e':'HTTP ${e.statusCode}'}))));
  }catch(_){
    m?.showSnackBar(SnackBar(content:Text(S.t('events.createFailed',{'e':S.t('settings.eventsOffline')}))));
  }
  return null;
}
