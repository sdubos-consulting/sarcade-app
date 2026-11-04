// SPDX-License-Identifier: MPL-2.0
// © SDUBOS Consulting et contributeurs SARCADE

/// Meshtastic phone API over Bluetooth, the few messages SARCADE needs
/// (lot 28, card « Module Meshtastic, sur le modèle de MeshCore »).
///
/// Written by hand, without code generated from the Meshtastic `.proto`
/// files: those are under GPL-3.0, which cannot be mixed into this MPL-2.0
/// application (decision recorded in the first pull request of lot 28).
/// Only the public facts of the interface are used here: the Bluetooth
/// UUIDs, the protobuf wire format (developers.google.com/protocol-buffers)
/// and the numbers of the fields read, as documented for client
/// applications (meshtastic.org/docs/development/device/client-api).
///
/// Unknown fields are skipped, as protobuf requires: a newer firmware adds
/// fields without breaking SARCADE. Pure code, testable without Bluetooth;
/// web-safe (no 64-bit integer operation).
library;

import 'dart:convert';
import 'dart:typed_data';

/// Bluetooth service of the Meshtastic firmware.
const meshtasticService='6ba1b218-15a8-461f-9fa8-5dcae273eafd';
/// The application writes one ToRadio message here.
const meshtasticToRadio='f75c76d2-129e-4dad-a1dd-7866124401e7';
/// The application reads FromRadio messages here, one per read, until an
/// empty value.
const meshtasticFromRadio='2c55e69e-4993-11ed-b878-0242ac120002';
/// Notified when FromRadio has something new to read.
const meshtasticFromNum='ed9da18c-a800-4f66-a670-aa7547e34453';

/// Destination of a message to every node (the channel).
const meshtasticBroadcast=0xFFFFFFFF;

/// Port numbers (Data.portnum) SARCADE reads or writes.
const meshtasticPortText=1, meshtasticPortPosition=3, meshtasticPortNodeInfo=4, meshtasticPortRouting=5, meshtasticPortTelemetry=67;

/// battery_level above 100: the node is on external power.
const meshtasticPowered=101;

// --- Protobuf wire format -------------------------------------------------

/// One field read from a message: its number, its wire type (0 varint,
/// 1 64 bits, 2 length-delimited, 5 32 bits) and its value.
class PbField {
  final int number, wire;
  /// Varint: the value (at most 49 bits kept, enough for every field read
  /// here); 32 bits: the unsigned value.
  final int value;
  /// Length-delimited: the bytes; 32 bits: the 4 bytes (float, sfixed32).
  final Uint8List? bytes;
  const PbField(this.number,this.wire,{this.value=0,this.bytes});

  /// int32 written as a varint (negative numbers take 10 bytes).
  int get int32{final v=value%0x100000000;return v>=0x80000000?v-0x100000000:v;}
  bool get boolean=>value!=0;
  /// fixed32 / sfixed32 / float, from the 4 bytes.
  int get sfixed32=>ByteData.sublistView(bytes!).getInt32(0,Endian.little);
  double get float32=>ByteData.sublistView(bytes!).getFloat32(0,Endian.little);
  String get text=>utf8.decode(bytes!,allowMalformed:true);
}

/// Thrown for a message that cannot be read (truncated).
class PbFormatException implements Exception {
  final String message;
  const PbFormatException(this.message);
  @override String toString()=>'PbFormatException: $message';
}

/// The fields of a message, in order. Throws [PbFormatException] when the
/// bytes are truncated.
List<PbField> pbFields(Uint8List b){
  final out=<PbField>[];
  var i=0;
  int varint(){
    var v=0, mult=1, n=0;
    while(true){
      if(i>=b.length)throw const PbFormatException('truncated varint');
      final x=b[i++];
      // Only the 7 first bytes count (49 bits): exact on the web too.
      if(n<7)v+=(x&0x7F)*mult;
      mult*=128; n++;
      if(x<0x80)break;
      if(n>10)throw const PbFormatException('varint too long');
    }
    return v;
  }
  while(i<b.length){
    final key=varint();
    final number=key~/8, wire=key%8;
    switch(wire){
      case 0:
        out.add(PbField(number,0,value:varint()));
      case 1:
        if(i+8>b.length)throw const PbFormatException('truncated 64 bits');
        out.add(PbField(number,1,bytes:Uint8List.sublistView(b,i,i+8)));
        i+=8;
      case 2:
        final len=varint();
        if(i+len>b.length)throw const PbFormatException('truncated bytes');
        out.add(PbField(number,2,bytes:Uint8List.sublistView(b,i,i+len)));
        i+=len;
      case 5:
        if(i+4>b.length)throw const PbFormatException('truncated 32 bits');
        final bytes=Uint8List.sublistView(b,i,i+4);
        out.add(PbField(number,5,value:ByteData.sublistView(bytes).getUint32(0,Endian.little),bytes:bytes));
        i+=4;
      default:
        throw PbFormatException('wire type $wire');
    }
  }
  return out;
}

/// Writes a protobuf message, field by field.
class PbWriter {
  final _out=BytesBuilder(copy:false);
  void _varint(int v){
    // Negative int32: ten bytes, two's complement on 64 bits.
    if(v<0){
      final low=v%0x100000000;
      for(var k=0;k<4;k++){_out.addByte((low~/_pow(7*k))%128|0x80);}
      _out.addByte(((low~/_pow(28))%16)|0x70|0x80);
      for(var k=0;k<4;k++){_out.addByte(0xFF);}
      _out.addByte(0x01);
      return;
    }
    var x=v;
    while(x>=128){_out.addByte(x%128|0x80);x=x~/128;}
    _out.addByte(x);
  }
  static int _pow(int bits){var r=1;for(var k=0;k<bits;k++){r*=2;}return r;}
  void _key(int number,int wire)=>_varint(number*8+wire);
  void varint(int number,int v){_key(number,0);_varint(v);}
  void boolean(int number,bool v){if(v)varint(number,1);}
  void fixed32(int number,int v){_key(number,5);final d=ByteData(4)..setUint32(0,v%0x100000000,Endian.little);_out.add(d.buffer.asUint8List());}
  void sfixed32(int number,int v){_key(number,5);final d=ByteData(4)..setInt32(0,v,Endian.little);_out.add(d.buffer.asUint8List());}
  void float32(int number,double v){_key(number,5);final d=ByteData(4)..setFloat32(0,v,Endian.little);_out.add(d.buffer.asUint8List());}
  void bytes(int number,List<int> v){_key(number,2);_varint(v.length);_out.add(v);}
  void string(int number,String v)=>bytes(number,utf8.encode(v));
  void message(int number,PbWriter m)=>bytes(number,m.toBytes());
  Uint8List toBytes()=>_out.toBytes();
}

// --- What the module says -------------------------------------------------

/// Node id as Meshtastic shows it: « !a1b2c3d4 ».
String meshtasticId(int number)=>'!${(number%0x100000000).toRadixString(16).padLeft(8,'0')}';

/// The node number of an id « !a1b2c3d4 » (or « a1b2c3d4 »), null otherwise.
int? meshtasticNum(String id){
  final h=id.startsWith('!')?id.substring(1):id;
  if(h.isEmpty||h.length>8)return null;
  return int.tryParse(h,radix:16);
}

/// User of a node (NODEINFO): names, hardware, role.
class MeshtasticUser {
  final String id, longName, shortName;
  final int? hwModel, role;
  final bool licensed;
  const MeshtasticUser({this.id='',this.longName='',this.shortName='',this.hwModel,this.role,this.licensed=false});
}

/// User: id 1, long_name 2, short_name 3, hw_model 5, is_licensed 6, role 7.
MeshtasticUser readMeshtasticUser(Uint8List b){
  var id='', long='', short=''; int? hw, role; var licensed=false;
  for(final f in pbFields(b)){
    switch((f.number,f.wire)){
      case (1,2): id=f.text;
      case (2,2): long=f.text;
      case (3,2): short=f.text;
      case (5,0): hw=f.value;
      case (6,0): licensed=f.boolean;
      case (7,0): role=f.value;
    }
  }
  return MeshtasticUser(id:id,longName:long.trim(),shortName:short.trim(),hwModel:hw,role:role,licensed:licensed);
}

/// Position of a node, null fields when not given.
class MeshtasticPosition {
  final double? lat, lon;
  final int? altitude;
  final DateTime? time;
  const MeshtasticPosition({this.lat,this.lon,this.altitude,this.time});
  bool get placed=>lat!=null&&lon!=null;
}

/// Position: latitude_i 1 and longitude_i 2 (sfixed32, 1e-7 degree),
/// altitude 3 (int32, m), time 4 (fixed32, s). 0, 0 means none.
MeshtasticPosition readMeshtasticPosition(Uint8List b){
  int? lat, lon, alt, time;
  for(final f in pbFields(b)){
    switch((f.number,f.wire)){
      case (1,5): lat=f.sfixed32;
      case (2,5): lon=f.sfixed32;
      case (3,0): alt=f.int32;
      case (4,5): time=f.value;
    }
  }
  final none=lat==null||lon==null||(lat==0&&lon==0);
  return MeshtasticPosition(lat:none?null:lat!/1e7,lon:none?null:lon!/1e7,altitude:alt,
    time:time==null||time==0?null:DateTime.fromMillisecondsSinceEpoch(time*1000,isUtc:true));
}

/// Battery and use of the air of a node (DeviceMetrics).
class MeshtasticMetrics {
  /// 0 to 100, or [meshtasticPowered] on external power.
  final int? battery;
  final double? voltage, channelUtil, airUtilTx;
  final int? uptime;
  const MeshtasticMetrics({this.battery,this.voltage,this.channelUtil,this.airUtilTx,this.uptime});
}

/// DeviceMetrics: battery_level 1, voltage 2 (float), channel_utilization 3,
/// air_util_tx 4, uptime_seconds 5.
MeshtasticMetrics readMeshtasticMetrics(Uint8List b){
  int? battery, uptime; double? volt, ch, air;
  for(final f in pbFields(b)){
    switch((f.number,f.wire)){
      case (1,0): battery=f.value;
      case (2,5): volt=f.float32;
      case (3,5): ch=f.float32;
      case (4,5): air=f.float32;
      case (5,0): uptime=f.value;
    }
  }
  return MeshtasticMetrics(battery:battery,voltage:volt,channelUtil:ch,airUtilTx:air,uptime:uptime);
}

/// Telemetry (port 67): device_metrics 2; the other kinds are ignored.
MeshtasticMetrics? readMeshtasticTelemetry(Uint8List b){
  for(final f in pbFields(b)){
    if(f.number==2&&f.wire==2)return readMeshtasticMetrics(f.bytes!);
  }
  return null;
}

/// A node of the Meshtastic network known by the module (its node list).
class MeshtasticNode {
  final int num;
  String longName, shortName;
  int? hwModel, role;
  double? lat, lon;
  int? altitude;
  DateTime? lastHeard;
  double? snr;
  /// Hops of the last message heard; null when not known.
  int? hops;
  int? battery;
  double? voltage;
  bool viaMqtt;
  MeshtasticNode(this.num,{this.longName='',this.shortName='',this.hwModel,this.role,this.lat,this.lon,this.altitude,
    this.lastHeard,this.snr,this.hops,this.battery,this.voltage,this.viaMqtt=false});

  /// « !a1b2c3d4 ».
  String get id=>meshtasticId(num);
  /// Long name, else short name, else id.
  String get name=>longName.isNotEmpty?longName:shortName.isNotEmpty?shortName:id;
  bool get placed=>lat!=null&&lon!=null;
  /// 'client', 'router', 'tracker', 'sensor' (filters and icons).
  String get kind=>meshtasticRoleKind(role);

  void applyUser(MeshtasticUser u){
    if(u.longName.isNotEmpty)longName=u.longName;
    if(u.shortName.isNotEmpty)shortName=u.shortName;
    hwModel=u.hwModel??hwModel; role=u.role??role;
  }
  void applyPosition(MeshtasticPosition p){
    if(!p.placed)return;
    lat=p.lat; lon=p.lon; altitude=p.altitude??altitude;
  }
  void applyMetrics(MeshtasticMetrics m){
    battery=m.battery??battery; voltage=m.voltage??voltage;
  }
}

/// Role of a node (Config.DeviceConfig.Role) in a few families.
String meshtasticRoleKind(int? role)=>switch(role){
  2||4||11=>'router', 5||10=>'tracker', 6=>'sensor', _=>'client'};

/// NodeInfo: num 1, user 2, position 3, snr 4 (float), last_heard 5
/// (fixed32, s), device_metrics 6, via_mqtt 8, hops_away 9.
MeshtasticNode readMeshtasticNodeInfo(Uint8List b){
  final n=MeshtasticNode(0);
  var number=0;
  for(final f in pbFields(b)){
    switch((f.number,f.wire)){
      case (1,0): number=f.value;
      case (2,2): n.applyUser(readMeshtasticUser(f.bytes!));
      case (3,2): n.applyPosition(readMeshtasticPosition(f.bytes!));
      case (4,5): n.snr=f.float32;
      case (5,5): n.lastHeard=f.value==0?null:DateTime.fromMillisecondsSinceEpoch(f.value*1000,isUtc:true);
      case (6,2): n.applyMetrics(readMeshtasticMetrics(f.bytes!));
      case (8,0): n.viaMqtt=f.boolean;
      case (9,0): n.hops=f.value;
    }
  }
  return MeshtasticNode(number,longName:n.longName,shortName:n.shortName,hwModel:n.hwModel,role:n.role,lat:n.lat,lon:n.lon,
    altitude:n.altitude,lastHeard:n.lastHeard,snr:n.snr,hops:n.hops,battery:n.battery,voltage:n.voltage,viaMqtt:n.viaMqtt);
}

/// A packet of the mesh, decoded by the module (or still encrypted: a
/// channel SARCADE's module does not have).
class MeshtasticPacket {
  final int from, to, channel, id;
  final DateTime? rxTime;
  final double? snr;
  final int? rssi;
  final int hopLimit, hopStart;
  final bool wantAck, viaMqtt, encrypted;
  final int portnum;
  final Uint8List payload;
  final int requestId;
  MeshtasticPacket({this.from=0,this.to=0,this.channel=0,this.id=0,this.rxTime,this.snr,this.rssi,this.hopLimit=0,this.hopStart=0,
    this.wantAck=false,this.viaMqtt=false,this.encrypted=false,this.portnum=0,Uint8List? payload,this.requestId=0}):payload=payload??_empty;
  static final _empty=Uint8List(0);

  bool get broadcast=>to==meshtasticBroadcast;
  /// Hops taken by the packet; null when the firmware does not say.
  int? get hops=>hopStart==0||hopStart<hopLimit?null:hopStart-hopLimit;
  /// Text of a TEXT_MESSAGE packet.
  String? get text=>portnum==meshtasticPortText?utf8.decode(payload,allowMalformed:true):null;
}

/// MeshPacket: from 1 (fixed32), to 2 (fixed32), channel 3, decoded 4
/// (Data), encrypted 5, id 6 (fixed32), rx_time 7, rx_snr 8 (float),
/// hop_limit 9, want_ack 10, rx_rssi 12 (int32), via_mqtt 14, hop_start 15.
/// Data: portnum 1, payload 2, request_id 6 (fixed32).
MeshtasticPacket readMeshtasticPacket(Uint8List b){
  var from=0, to=0, channel=0, id=0, hopLimit=0, hopStart=0, port=0, request=0;
  int? rxTime, rssi; double? snr; var wantAck=false, mqtt=false, encrypted=false;
  Uint8List? payload;
  for(final f in pbFields(b)){
    switch((f.number,f.wire)){
      case (1,5): from=f.value;
      case (2,5): to=f.value;
      case (3,0): channel=f.value;
      case (4,2):
        for(final d in pbFields(f.bytes!)){
          switch((d.number,d.wire)){
            case (1,0): port=d.value;
            case (2,2): payload=d.bytes;
            case (6,5): request=d.value;
          }
        }
      case (5,2): encrypted=true;
      case (6,5): id=f.value;
      case (7,5): rxTime=f.value;
      case (8,5): snr=f.float32;
      case (9,0): hopLimit=f.value;
      case (10,0): wantAck=f.boolean;
      case (12,0): rssi=f.int32;
      case (14,0): mqtt=f.boolean;
      case (15,0): hopStart=f.value;
    }
  }
  return MeshtasticPacket(from:from,to:to,channel:channel,id:id,
    rxTime:rxTime==null||rxTime==0?null:DateTime.fromMillisecondsSinceEpoch(rxTime*1000,isUtc:true),
    snr:snr,rssi:rssi==0?null:rssi,hopLimit:hopLimit,hopStart:hopStart,wantAck:wantAck,viaMqtt:mqtt,encrypted:encrypted,
    portnum:port,payload:payload,requestId:request);
}

/// Routing (port 5): error_reason 3, 0 (none) when absent. An answer to a
/// message of this module ([MeshtasticPacket.requestId]) with 0 is its
/// acknowledgement.
int readMeshtasticRoutingError(Uint8List b){
  for(final f in pbFields(b)){
    if(f.number==3&&f.wire==0)return f.value;
  }
  return 0;
}

/// What the module said about itself, filled as answers arrive.
class MeshtasticInfo {
  int? myNum;
  String? firmware;
  int? hwModel;
  int? region, preset, txPower, hopLimit;
  bool? usePreset;
  /// Primary channel: its name (empty: the name of the preset).
  String? channelName;
  /// Last configuration read in full (config_complete_id).
  DateTime? configAt;
  bool get empty=>myNum==null&&firmware==null;
}

/// QueueStatus: res 1 (0 = taken), free 2, maxlen 3, mesh_packet_id 4.
class MeshtasticQueue {
  final int result, free, max, packetId;
  const MeshtasticQueue({this.result=0,this.free=0,this.max=0,this.packetId=0});
}

/// One FromRadio message: one of the fields is set.
class MeshtasticFrame {
  /// 'packet', 'myInfo', 'node', 'config', 'configComplete', 'rebooted',
  /// 'channel', 'queue', 'metadata', 'log', 'other'.
  final String kind;
  final MeshtasticPacket? packet;
  final MeshtasticNode? node;
  final MeshtasticQueue? queue;
  final int? configId;
  const MeshtasticFrame(this.kind,{this.packet,this.node,this.queue,this.configId});
}

/// Reads one FromRadio message (field numbers: packet 2, my_info 3,
/// node_info 4, config 5, log_record 6, config_complete_id 7, rebooted 8,
/// channel 10, queueStatus 11, metadata 13) and fills [info] with what the
/// module says about itself.
MeshtasticFrame readMeshtasticFrame(Uint8List b,MeshtasticInfo info){
  for(final f in pbFields(b)){
    switch((f.number,f.wire)){
      case (2,2): return MeshtasticFrame('packet',packet:readMeshtasticPacket(f.bytes!));
      case (3,2):
        for(final m in pbFields(f.bytes!)){if(m.number==1&&m.wire==0)info.myNum=m.value;}
        return const MeshtasticFrame('myInfo');
      case (4,2): return MeshtasticFrame('node',node:readMeshtasticNodeInfo(f.bytes!));
      case (5,2): _readConfig(f.bytes!,info); return const MeshtasticFrame('config');
      case (6,2): return const MeshtasticFrame('log');
      case (7,0): info.configAt=DateTime.now(); return MeshtasticFrame('configComplete',configId:f.value);
      case (8,0): return const MeshtasticFrame('rebooted');
      case (10,2): _readChannel(f.bytes!,info); return const MeshtasticFrame('channel');
      case (11,2):
        var res=0, free=0, max=0, id=0;
        for(final q in pbFields(f.bytes!)){
          switch((q.number,q.wire)){
            case (1,0): res=q.int32;
            case (2,0): free=q.value;
            case (3,0): max=q.value;
            case (4,0): id=q.value;
          }
        }
        return MeshtasticFrame('queue',queue:MeshtasticQueue(result:res,free:free,max:max,packetId:id));
      case (13,2):
        for(final m in pbFields(f.bytes!)){
          switch((m.number,m.wire)){
            case (1,2): info.firmware=m.text;
            case (9,0): info.hwModel=m.value;
          }
        }
        return const MeshtasticFrame('metadata');
    }
  }
  return const MeshtasticFrame('other');
}

/// Config: lora 6 (LoRaConfig: use_preset 1, modem_preset 2, region 7,
/// hop_limit 8, tx_power 10); the other parts are not read.
void _readConfig(Uint8List b,MeshtasticInfo info){
  for(final f in pbFields(b)){
    if(f.number!=6||f.wire!=2)continue;
    info.usePreset=false; info.preset=0; info.region=0; info.txPower=0; info.hopLimit=null;
    for(final l in pbFields(f.bytes!)){
      switch((l.number,l.wire)){
        case (1,0): info.usePreset=l.boolean;
        case (2,0): info.preset=l.value;
        case (7,0): info.region=l.value;
        case (8,0): info.hopLimit=l.value;
        case (10,0): info.txPower=l.int32;
      }
    }
  }
}

/// Channel: index 1, settings 2 (ChannelSettings: name 3), role 3
/// (1 = primary). Only the primary channel is kept.
void _readChannel(Uint8List b,MeshtasticInfo info){
  var role=0; String? name;
  for(final f in pbFields(b)){
    switch((f.number,f.wire)){
      case (2,2):
        name='';
        for(final s in pbFields(f.bytes!)){if(s.number==3&&s.wire==2)name=s.text;}
      case (3,0): role=f.value;
    }
  }
  if(role==1)info.channelName=name??'';
}

// --- What the application sends -------------------------------------------

/// ToRadio want_config_id (3): the module sends its node, its settings and
/// every node it knows, then config_complete_id with [nonce].
Uint8List meshtasticWantConfig(int nonce)=>(PbWriter()..varint(3,nonce)).toBytes();

/// ToRadio heartbeat (7): keeps the link alive.
Uint8List meshtasticHeartbeat()=>(PbWriter()..message(7,PbWriter())).toBytes();

/// ToRadio disconnect (4): the module forgets this application.
Uint8List meshtasticDisconnect()=>(PbWriter()..boolean(4,true)).toBytes();

/// Longest text SARCADE lets write, in bytes (the payload of a packet is
/// 233 bytes; the Meshtastic applications stop at 200).
const meshtasticMaxTextBytes=200;

/// True when [text] can go in one Meshtastic message.
bool meshtasticTextFits(String text){
  final t=text.trim();
  return t.isNotEmpty&&utf8.encode(t).length<=meshtasticMaxTextBytes;
}

/// ToRadio packet (1): a text to [to] (a node, or [meshtasticBroadcast]
/// on [channel]), [id] chosen by the application to follow its
/// acknowledgement (Routing packet whose request_id is [id]).
Uint8List meshtasticSendText({required int to,required String text,required int id,int channel=0,bool wantAck=true}){
  final data=PbWriter()..varint(1,meshtasticPortText)..string(2,text.trim());
  final packet=PbWriter()..fixed32(2,to);
  if(channel!=0)packet.varint(3,channel);
  packet..message(4,data)..fixed32(6,id)..boolean(10,wantAck);
  return (PbWriter()..message(1,packet)).toBytes();
}

// --- Names shown ----------------------------------------------------------

/// LoRa region (RegionCode), as written in the Meshtastic applications.
String meshtasticRegionName(int? r)=>switch(r){
  null=>'', 0=>'UNSET', 1=>'US', 2=>'EU_433', 3=>'EU_868', 4=>'CN', 5=>'JP', 6=>'ANZ', 7=>'KR', 8=>'TW', 9=>'RU', 10=>'IN',
  11=>'NZ_865', 12=>'TH', 13=>'LORA_24', 14=>'UA_433', 15=>'UA_868', 16=>'MY_433', 17=>'MY_919', 18=>'SG_923',
  19=>'PH_433', 20=>'PH_868', 21=>'PH_915', 22=>'ANZ_433', 23=>'KZ_433', 24=>'KZ_863', 25=>'NP_865', 26=>'BR_902',
  _=>'#$r'};

/// Modem preset (ModemPreset), as named on the primary channel by default.
String meshtasticPresetName(int? p)=>switch(p){
  null=>'', 0=>'LongFast', 1=>'LongSlow', 2=>'VeryLongSlow', 3=>'MediumSlow', 4=>'MediumFast', 5=>'ShortSlow', 6=>'ShortFast',
  7=>'LongModerate', 8=>'ShortTurbo', 9=>'LongTurbo', _=>'#$p'};

/// Hardware (HardwareModel) of the most common boards; a number otherwise.
String meshtasticHardwareName(int? hw)=>switch(hw){
  null||0=>'', 4=>'T-Beam', 7=>'T-Echo', 9=>'RAK4631', 10=>'Heltec V2.1', 31=>'Station G2', 43=>'Heltec V3', 44=>'Heltec WSL V3',
  48=>'Heltec Wireless Tracker', 50=>'T-Deck', 69=>'Heltec T114', 71=>'Tracker T1000-E', 81=>'Seeed XIAO S3', 110=>'Heltec V4',
  _=>'#$hw'};

/// Battery in words: « 82 % · 3,98 V », « secteur » when powered.
String meshtasticBatteryText(int? level,double? volt,{required String powered}){
  final parts=[
    if(level!=null)level>100?powered:'$level %',
    if(volt!=null&&volt>0)'${volt.toStringAsFixed(2)} V'];
  return parts.join(' · ');
}

/// Lines shown in the Diagnostic, label and value; [me]: the node of the
/// module in its own list.
List<(String,String)> meshtasticLines(MeshtasticInfo i,MeshtasticNode? me,{required String powered}){
  final channel=i.channelName==null?null:i.channelName!.isEmpty?meshtasticPresetName(i.preset):i.channelName!;
  final battery=me==null?'':meshtasticBatteryText(me.battery,me.voltage,powered:powered);
  return [
    if(me!=null&&me.longName.isNotEmpty)('name',me.longName),
    if(me!=null&&me.shortName.isNotEmpty)('shortName',me.shortName),
    if(i.myNum!=null)('id',meshtasticId(i.myNum!)),
    if(meshtasticHardwareName(i.hwModel??me?.hwModel).isNotEmpty)('model',meshtasticHardwareName(i.hwModel??me?.hwModel)),
    if(i.firmware!=null&&i.firmware!.isNotEmpty)('firmware',i.firmware!),
    if(i.region!=null)('radio',[meshtasticRegionName(i.region),if(i.usePreset!=false)meshtasticPresetName(i.preset)].join(' · ')),
    if(i.txPower!=null)('power',i.txPower==0?'max':'${i.txPower} dBm'),
    if(i.hopLimit!=null)('hopLimit','${i.hopLimit}'),
    if(channel!=null)('channel',channel),
    if(battery.isNotEmpty)('battery',battery),
    if(me!=null&&me.placed)('position','${me.lat!.toStringAsFixed(5)}, ${me.lon!.toStringAsFixed(5)}'),
  ];
}

/// Hexadecimal of a message for the journal.
String meshtasticHex(Uint8List f,{int max=48}){
  final hex=[for(final x in f.take(max))x.toRadixString(16).padLeft(2,'0')].join(' ');
  return f.length>max?'$hex … (${f.length} o)':hex;
}
