/// « … écrit » (lot 29, group 7): a very light signal by the real time only,
/// never by LoRa nor APRS, never written down, not in energy saving; at most
/// one every 5 s while the text changes, forgotten after 6 s without news.
library;

import 'package:flutter/foundation.dart';

import 'conversations.dart';

const typingEvery=Duration(seconds:5);
const typingForget=Duration(seconds:6);

/// Same name on both sides: a direct chat is the pair of people, in order.
String typingWire(String conv,String me){
  final peer=peerOf(conv);
  if(peer==null)return conv;
  final pair=[me,peer]..sort();
  return 'u:${pair.join('|')}';
}

/// The conversation of this device for a signal received, or null when it
/// is a direct chat between two other people.
String? typingConversation(String wire,String me,String from){
  if(wire.startsWith('u:')&&wire.contains('|')){
    final pair=wire.substring(2).split('|');
    return pair.contains(me)&&pair.contains(from)&&from!=me?directKey(from):null;
  }
  return wire;
}

/// Who writes, per conversation of this device.
class Typing extends ValueNotifier<Map<String,Map<String,DateTime>>>{
  Typing():super({});
  static final instance=Typing();

  void received(Map data,String me,{DateTime? now}){
    final from='${data['actor_id']??''}';
    if(from.isEmpty||from==me)return;
    final conv=typingConversation('${data['conversation']??''}',me,from);
    if(conv==null||conv.isEmpty)return;
    value={...value,conv:{...?value[conv],from:now??DateTime.now()}};
  }

  /// Someone sent his message: no longer writing.
  void sent(String from){
    if(!value.values.any((m)=>m.containsKey(from)))return;
    value={for(final e in value.entries)e.key:{...e.value}..remove(from)};
  }

  List<String> who(String conv,{DateTime? now}){
    final t=now??DateTime.now();
    return [for(final e in (value[conv]??const <String,DateTime>{}).entries)if(t.difference(e.value)<typingForget)e.key]..sort();
  }
}

/// Throttle of the signals sent by this device.
class TypingSender{
  DateTime? _last; String? _conv;
  bool shouldSend(String conv,DateTime now){
    if(_conv==conv&&_last!=null&&now.difference(_last!)<typingEvery)return false;
    _conv=conv; _last=now; return true;
  }
}
