/// MeshCore companion radio protocol, the few frames of the Bluetooth trial
/// (card « Essai : SARCADE parle en Bluetooth à un module MeshCore »,
/// 1 Nov 2026). Source: docs.meshcore.io/companion_protocol. Read only:
/// nothing here sends anything on the LoRa network. Pure code, testable
/// without Bluetooth.
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
