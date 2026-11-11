/// PTT natif, talkie-walkie (card « PTT natif », lot 29, decisions of
/// 6 Nov 2026): WebRTC through the LiveKit server of the NAS. The SARCADE
/// server gives a short access per channel; the voice goes between the
/// devices and LiveKit, is never recorded. Channels: « Général » and one per
/// group of the event. Press and hold to talk; everyone else in the channel
/// hears, the name of who talks is shown.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../messages/conversations.dart';
import '../../services/sarcade_api.dart';

const pttGeneral='general';

typedef PttChannel=({String id,String name,bool canTalk});

/// The voice channel of a conversation: « Tous » is « Général », a group
/// its own; a direct chat has none.
String? pttChannelOf(String conv){
  if(conv==allKey)return pttGeneral;
  return groupOf(conv);
}

List<PttChannel> parsePttChannels(Map j)=>[
  for(final c in (j['channels'] as List?)??const [])
    if(c is Map)(id:'${c['id']}',name:'${c['name']??''}',canTalk:c['can_talk']==true)];

enum PttState{off,connecting,listening,talking,error}

class Ptt extends ChangeNotifier{
  Ptt._();
  static final instance=Ptt._();

  SarcadeApi? _api; String? _event, _device;
  bool available=false; List<PttChannel> channels=const [];
  PttState state=PttState.off; String? channel; String? error;
  bool canTalk=false;
  /// Who talks now (identities of the devices).
  List<String> speakers=const [];
  Room? _room; EventsListener<RoomEvent>? _events;

  /// Channels of this device for the event; « available » false while the
  /// server has no LiveKit.
  Future<void> load(SarcadeApi api,String eventId,String deviceId) async {
    _api=api; _event=eventId; _device=deviceId;
    try{
      final j=await api.pttChannels(eventId,deviceId);
      available=j['available']==true; channels=parsePttChannels(j);
    }catch(_){available=false;channels=const [];}
    notifyListeners();
  }

  PttChannel? channelById(String? id)=>id==null?null:channels.where((c)=>c.id==id).firstOrNull;

  Future<void> join(String channelId,{String? name}) async {
    final api=_api, ev=_event, dev=_device;
    if(api==null||ev==null||dev==null)return;
    if(channel==channelId&&state!=PttState.off&&state!=PttState.error)return;
    await leave();
    channel=channelId; state=PttState.connecting; error=null; notifyListeners();
    try{
      final a=await api.pttToken(ev,dev,channelId,name:name);
      canTalk=a['can_talk']==true;
      final room=Room(roomOptions:const RoomOptions(adaptiveStream:false,dynacast:false,
        defaultAudioPublishOptions:AudioPublishOptions(dtx:true)));
      _room=room;
      _events=room.createListener()
        ..on<ActiveSpeakersChangedEvent>((e){speakers=[for(final p in e.speakers)if(p.identity!=dev)p.identity];notifyListeners();})
        ..on<RoomDisconnectedEvent>((_){if(_room==room){state=PttState.off;speakers=const [];notifyListeners();}});
      await room.connect('${a['url']}','${a['token']}');
      state=PttState.listening;
    }catch(e){
      state=PttState.error; error='$e';
      await _close();
    }
    notifyListeners();
  }

  /// Pressed: the microphone opens; released: it closes.
  Future<void> talk(bool down) async {
    final room=_room;
    if(room==null||!canTalk||(state!=PttState.listening&&state!=PttState.talking))return;
    state=down?PttState.talking:PttState.listening; notifyListeners();
    try{await room.localParticipant?.setMicrophoneEnabled(down);}catch(e){error='$e';state=PttState.listening;notifyListeners();}
  }

  Future<void> leave() async {
    await _close();
    if(state!=PttState.off||channel!=null){state=PttState.off;channel=null;speakers=const [];notifyListeners();}
  }

  Future<void> _close() async {
    final room=_room; _room=null;
    final events=_events; _events=null;
    events?.dispose();
    if(room!=null){
      try{await room.disconnect();}catch(_){/* already gone */}
      room.dispose();
    }
  }
}
