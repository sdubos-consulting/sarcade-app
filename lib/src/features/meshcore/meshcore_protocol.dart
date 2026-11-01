/// MeshCore companion radio protocol, the few frames of the Bluetooth trial
/// (card « Essai : SARCADE parle en Bluetooth à un module MeshCore »,
/// 1 Nov 2026). Source: docs.meshcore.io/companion_protocol. Contacts and
/// adverts are read (lot D); since lot 17 (card « MeshCore : nœuds sur la
/// carte et discussion directe avec un nœud ») a private text message can
/// be sent to a companion and its acknowledgement followed. Pure code,
/// testable without Bluetooth.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Nordic UART service of the companion firmware (BLE variant).
const meshCoreService='6e400001-b5a3-f393-e0a9-e50e24dcca9e';
/// The application writes its commands here.
const meshCoreRx='6e400002-b5a3-f393-e0a9-e50e24dcca9e';
/// The module answers by notifications here.
const meshCoreTx='6e400003-b5a3-f393-e0a9-e50e24dcca9e';

/// Protocol version SARCADE understands (sent with the device query).
const meshCoreAppProtocol=3;

/// CMD_DEVICE_QUERY (0x16): firmware, model, version. Answer: 0x0D.
Uint8List deviceQuery()=>Uint8List.fromList([0x16,meshCoreAppProtocol]);

/// CMD_APP_START (0x01): who the application is. Answer: SELF_INFO 0x05.
Uint8List appStart([String app='SARCADE'])=>Uint8List.fromList([0x01,0,0,0,0,0,0,0,...utf8.encode(app)]);

/// Battery and storage (0x14). Answer: 0x0C.
Uint8List batteryQuery()=>Uint8List.fromList([0x14]);

/// CMD_GET_CONTACTS (0x04): the nodes the module knows. Answers:
/// CONTACTS_START (0x02), one CONTACT (0x03) each, END_OF_CONTACTS (0x04).
Uint8List contactsQuery()=>Uint8List.fromList([0x04]);

/// A node of the MeshCore network known by the module (its contact list):
/// companion, repeater, room server or sensor.
class MeshCoreContact {
  final String key; final int type; final int flags;
  /// Hops of the known route; null when the route is not known yet (flood).
  final int? hops;
  final String name;
  final DateTime? lastAdvert;
  final double? lat, lon;
  const MeshCoreContact({required this.key,required this.type,this.flags=0,this.hops,required this.name,this.lastAdvert,this.lat,this.lon});
  /// 'companion', 'repeater', 'room', 'sensor' or 'other'.
  String get kind=>switch(type){1=>'companion',2=>'repeater',3=>'room',4=>'sensor',_=>'other'};
  String get shortKey=>key.length>8?key.substring(0,8):key;
}

/// CONTACT frame (0x03, 148 bytes): public key (32), type, flags, path
/// length (signed, -1 = unknown), path (64), name (32), last advert (u32,
/// seconds), latitude and longitude (i32, millionths), last change (u32).
MeshCoreContact? readMeshCoreContact(Uint8List f){
  if(f.length<144||f[0]!=0x03)return null;
  final key=[for(final b in f.sublist(1,33))b.toRadixString(16).padLeft(2,'0')].join();
  final pathLen=_i8(f[35]);
  final advert=_u32(f,132);
  final lat=_i32(f,136)/1e6, lon=_i32(f,140)/1e6;
  final none=lat==0&&lon==0;
  return MeshCoreContact(key:key,type:f[33],flags:f[34],hops:pathLen<0?null:pathLen,name:_text(f,100,132),
    lastAdvert:advert==0?null:DateTime.fromMillisecondsSinceEpoch(advert*1000,isUtc:true),lat:none?null:lat,lon:none?null:lon);
}

/// What the module said about itself, filled as answers arrive.
class MeshCoreInfo {
  int? firmwareVersion, maxContacts, maxChannels;
  String? build, model, version;
  String? name, publicKeyStart;
  int? txPowerDbm, maxTxPowerDbm, spreadingFactor, codingRate;
  double? frequencyMhz, bandwidthKhz, lat, lon;
  int? batteryMv, storageUsedKb, storageTotalKb;
  bool get empty=>firmwareVersion==null&&name==null&&batteryMv==null;
}

int _u16(Uint8List b,int o)=>b[o]|(b[o+1]<<8);
int _u32(Uint8List b,int o)=>b[o]|(b[o+1]<<8)|(b[o+2]<<16)|(b[o+3]<<24);
int _i32(Uint8List b,int o){final v=_u32(b,o);return v>=0x80000000?v-0x100000000:v;}
int _i8(int v)=>v>=128?v-256:v;
String _text(Uint8List b,int from,[int? to]){
  final end=to==null||to>b.length?b.length:to;
  if(from>=end)return '';
  var bytes=b.sublist(from,end);
  final z=bytes.indexOf(0); if(z>=0)bytes=bytes.sublist(0,z);
  return utf8.decode(bytes,allowMalformed:true).trim();
}

/// Reads one frame from the module into [info]; returns the kind of frame
/// ('device', 'self', 'battery', 'error', 'ok' or 'other').
String readMeshCoreFrame(Uint8List f,MeshCoreInfo info){
  if(f.isEmpty)return 'other';
  switch(f[0]){
    case 0x0D: // DEVICE_INFO
      if(f.length>1)info.firmwareVersion=f[1];
      if(f.length>=8&&(info.firmwareVersion??0)>=3){
        info.maxContacts=f[2]*2; info.maxChannels=f[3];
        // Bytes 4-7: Bluetooth PIN of the module, never shown nor logged.
        info.build=_text(f,8,20); info.model=_text(f,20,60); info.version=_text(f,60,80);
      }
      return 'device';
    case 0x05: // SELF_INFO
      if(f.length<58)return 'other';
      info.txPowerDbm=_i8(f[2]); info.maxTxPowerDbm=_i8(f[3]);
      info.publicKeyStart=[for(final b in f.sublist(4,8))b.toRadixString(16).padLeft(2,'0')].join();
      final lat=_i32(f,36)/1e6, lon=_i32(f,40)/1e6;
      info.lat=lat==0&&lon==0?null:lat; info.lon=lat==0&&lon==0?null:lon;
      info.frequencyMhz=_u32(f,48)/1000.0; info.bandwidthKhz=_u32(f,52)/1000.0;
      info.spreadingFactor=f[56]; info.codingRate=f[57];
      info.name=_text(f,58);
      return 'self';
    case 0x0C: // BATTERY
      if(f.length>=3)info.batteryMv=_u16(f,1);
      if(f.length>=11){info.storageUsedKb=_u32(f,3);info.storageTotalKb=_u32(f,7);}
      return 'battery';
    case 0x00: return 'ok';
    case 0x01: return 'error';
    case 0x02: return 'contactsStart';
    case 0x03: return 'contact';
    case 0x04: return 'contactsEnd';
    // Private messages (lot 17): sent, acknowledged, received.
    case 0x06: return 'sent';
    case 0x07: case 0x10: return 'contactMsg';
    case 0x08: case 0x11: return 'channelMsg';
    case 0x0A: return 'noMore';
    case 0x82: return 'confirmed';
    case 0x83: return 'waiting';
    // ADVERT (0x80) and NEW_ADVERT (0x8A): a node was heard.
    case 0x80: case 0x8A: return 'advert';
    default: return 'other';
  }
}

/// Hexadecimal of a frame for the journal; the PIN of DEVICE_INFO is masked.
String meshCoreHex(Uint8List f){
  final b=Uint8List.fromList(f);
  if(b.length>=8&&b[0]==0x0D){for(var i=4;i<8;i++){b[i]=0;}}
  return [for(final x in b)x.toRadixString(16).padLeft(2,'0')].join(' ');
}

/// Lines shown in the Diagnostic, label and value.
List<(String,String)> meshCoreLines(MeshCoreInfo i)=>[
  if(i.name!=null&&i.name!.isNotEmpty)('name',i.name!),
  if(i.model!=null&&i.model!.isNotEmpty)('model',i.model!),
  if(i.version!=null||i.firmwareVersion!=null)('firmware',[if(i.version!=null&&i.version!.isNotEmpty)i.version!,if(i.build!=null&&i.build!.isNotEmpty)i.build!,if(i.firmwareVersion!=null)'proto ${i.firmwareVersion}'].join(' · ')),
  if(i.frequencyMhz!=null)('radio','${i.frequencyMhz!.toStringAsFixed(3)} MHz · BW ${i.bandwidthKhz!.toStringAsFixed(1)} kHz · SF${i.spreadingFactor} · CR${i.codingRate}'),
  if(i.txPowerDbm!=null)('power','${i.txPowerDbm} dBm (max ${i.maxTxPowerDbm} dBm)'),
  if(i.batteryMv!=null)('battery','${(i.batteryMv!/1000).toStringAsFixed(2)} V'),
  if(i.lat!=null)('position','${i.lat!.toStringAsFixed(5)}, ${i.lon!.toStringAsFixed(5)}'),
  if(i.publicKeyStart!=null)('key','${i.publicKeyStart}…'),
];

/// Longest private message SARCADE lets write: 133 characters (MeshCore
/// specification), and never more than the 160 bytes of the frame.
const meshCoreMaxText=133, meshCoreMaxTextBytes=160;

/// True when [text] can go in one MeshCore message.
bool meshCoreTextFits(String text){
  final t=text.trim();
  return t.isNotEmpty&&t.runes.length<=meshCoreMaxText&&utf8.encode(t).length<=meshCoreMaxTextBytes;
}

/// The 6 first bytes of a public key (12 hexadecimal characters): how a
/// private message names its recipient or its sender.
String meshCorePrefix(String key)=>(key.length>12?key.substring(0,12):key).toLowerCase();

/// CMD_SEND_TXT_MSG (0x02): plain text to the contact whose public key
/// starts with [prefix]; [attempt] 0 to 3. Answers: RESP_CODE_SENT (0x06)
/// with the expected acknowledgement, or an error (0x01); then
/// PUSH_CODE_SEND_CONFIRMED (0x82) when the node acknowledged it.
Uint8List sendTextMessage(String prefix,String text,{required DateTime at,int attempt=0}){
  final key=[for(var i=0;i+1<prefix.length&&i<12;i+=2)int.parse(prefix.substring(i,i+2),radix:16)];
  final ts=at.millisecondsSinceEpoch~/1000;
  return Uint8List.fromList([0x02,0,attempt.clamp(0,3),ts&0xFF,(ts>>8)&0xFF,(ts>>16)&0xFF,(ts>>24)&0xFF,
    ...key,...List<int>.filled(6-key.length,0),...utf8.encode(text.trim())]);
}

/// CMD_SYNC_NEXT_MESSAGE (0x0A): the next message waiting in the module
/// (they wait there even while SARCADE is away). Answers: a contact message
/// (0x07 or 0x10), a channel message (0x08 or 0x11), or NO_MORE (0x0A).
Uint8List syncNextMessage()=>Uint8List.fromList([0x0A]);

/// RESP_CODE_SENT (0x06): flood or direct, the acknowledgement code to
/// expect and the round trip the module suggests to wait.
({bool flood,int ack,Duration timeout})? readMeshCoreSent(Uint8List f){
  if(f.length<10||f[0]!=0x06)return null;
  return (flood:f[1]==1,ack:_u32(f,2),timeout:Duration(milliseconds:_u32(f,6)));
}

/// PUSH_CODE_SEND_CONFIRMED (0x82): the acknowledgement code received.
int? readMeshCoreConfirmed(Uint8List f)=>f.length<5||f[0]!=0x82?null:_u32(f,1);

/// A private message received from a node.
class MeshCoreIncoming {
  /// 12 hexadecimal characters of the sender's public key.
  final String prefix;
  final String text;
  final DateTime? sentAt;
  /// Signal to noise ratio in dB (version 3 frames only).
  final double? snr;
  /// Hops of the way it came; null when sent direct.
  final int? hops;
  const MeshCoreIncoming({required this.prefix,required this.text,this.sentAt,this.snr,this.hops});
}

/// CONTACT_MSG_RECV (0x07) and its version 3 (0x10, with the SNR first):
/// sender prefix (6), path length (0xFF: direct), text type, timestamp,
/// 4 more bytes when the text is signed (type 2), then the text.
MeshCoreIncoming? readMeshCoreMessage(Uint8List f){
  if(f.isEmpty)return null;
  final v3=f[0]==0x10;
  if(!v3&&f[0]!=0x07)return null;
  final o=v3?4:1;
  if(f.length<o+12)return null;
  final prefix=[for(final b in f.sublist(o,o+6))b.toRadixString(16).padLeft(2,'0')].join();
  final path=f[o+6], type=f[o+7], ts=_u32(f,o+8);
  final textAt=o+12+(type==2?4:0);
  return MeshCoreIncoming(prefix:prefix,text:_text(f,textAt),
    sentAt:ts==0?null:DateTime.fromMillisecondsSinceEpoch(ts*1000,isUtc:true),
    snr:v3?_i8(f[1])/4:null,hops:path==0xFF?null:path);
}
