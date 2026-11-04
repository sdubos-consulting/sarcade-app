// SPDX-License-Identifier: MPL-2.0
// © SDUBOS Consulting et contributeurs SARCADE

// Lot 28, card « Module Meshtastic, sur le modèle de MeshCore »: decoder
// written by hand (no code generated from the GPL .proto files), checked
// against sample messages encoded by Google's protobuf library
// (fixtures/meshtastic_frames.dart, tool/meshtastic_samples.py).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/meshtastic/meshtastic_protocol.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

import 'fixtures/meshtastic_frames.dart';

String hex(Uint8List b)=>[for(final x in b)x.toRadixString(16).padLeft(2,'0')].join();

void main(){
  setUp(()=>S.setLanguage('fr'));

  group('wire format',(){
    test('varint, negative int32 on ten bytes, fixed32, float, bytes',(){
      final w=PbWriter()..varint(1,300)..varint(2,-2)..fixed32(3,0xFFFFFFFF)..sfixed32(4,-5)..float32(5,1.5)..string(6,'é');
      final f=pbFields(w.toBytes());
      expect(f.map((x)=>x.number),[1,2,3,4,5,6]);
      expect(f[0].value,300);
      expect(f[1].int32,-2);
      expect(f[2].value,0xFFFFFFFF);
      expect(f[3].sfixed32,-5);
      expect(f[4].float32,1.5);
      expect(f[5].text,'é');
      expect(hex((PbWriter()..varint(10,-2)).toBytes()),'50feffffffffffffffff01');
    });

    test('truncated message: a clear error, no crash',(){
      expect(()=>pbFields(Uint8List.fromList([0x12,0x05,0x01])),throwsA(isA<PbFormatException>()));
      expect(()=>pbFields(Uint8List.fromList([0x08,0x80])),throwsA(isA<PbFormatException>()));
    });

    test('unknown fields are skipped',(){
      final b=(PbWriter()..varint(99,7)..string(1,'!abc')..fixed32(98,1)).toBytes();
      expect(readMeshtasticUser(b).id,'!abc');
    });

    test('ids « !a1b2c3d4 »',(){
      expect(meshtasticId(0xa1b2c3d4),'!a1b2c3d4');
      expect(meshtasticId(0x0badcafe),'!0badcafe');
      expect(meshtasticNum('!0badcafe'),0x0badcafe);
      expect(meshtasticNum('xyz'),isNull);
    });
  });

  group('FromRadio samples',(){
    test('my node, metadata, LoRa settings, primary channel',(){
      final i=MeshtasticInfo();
      expect(readMeshtasticFrame(meshtasticSample('myInfo'),i).kind,'myInfo');
      expect(i.myNum,0xa1b2c3d4);
      expect(readMeshtasticFrame(meshtasticSample('metadata'),i).kind,'metadata');
      expect(i.firmware,'2.6.11.60ec05e');
      expect(i.hwModel,43);
      expect(readMeshtasticFrame(meshtasticSample('loraConfig'),i).kind,'config');
      expect(i.region,3); expect(i.preset,0); expect(i.usePreset,isTrue); expect(i.hopLimit,3); expect(i.txPower,-2);
      expect(readMeshtasticFrame(meshtasticSample('channelSecondary'),i).kind,'channel');
      expect(i.channelName,isNull,reason:'a secondary channel is not the primary one');
      readMeshtasticFrame(meshtasticSample('channelPrimary'),i);
      expect(i.channelName,'',reason:'no name: the name of the preset');
      final f=readMeshtasticFrame(meshtasticSample('configComplete'),i);
      expect(f.kind,'configComplete'); expect(f.configId,42); expect(i.configAt,isNotNull);
    });

    test('node of the module: names, hardware, position, battery',(){
      final n=readMeshtasticFrame(meshtasticSample('nodeMe'),MeshtasticInfo()).node!;
      expect(n.num,0xa1b2c3d4); expect(n.id,'!a1b2c3d4');
      expect(n.longName,'F4ABC Mobile'); expect(n.shortName,'F4AB'); expect(n.hwModel,43);
      expect(n.lat,closeTo(48.7654321,1e-7)); expect(n.lon,closeTo(1.9876543,1e-7)); expect(n.altitude,152);
      expect(n.battery,18); expect(n.voltage,closeTo(3.62,1e-5));
      expect(n.lastHeard,DateTime.fromMillisecondsSinceEpoch(1793800000*1000,isUtc:true));
      expect(n.kind,'client');
    });

    test('a router on external power, 2 hops; a node without position',(){
      final r=readMeshtasticFrame(meshtasticSample('nodeRouter'),MeshtasticInfo()).node!;
      expect(r.name,'Relais Maurepas'); expect(r.kind,'router'); expect(r.hwModel,9);
      expect(r.snr,6.25); expect(r.hops,2); expect(r.battery,meshtasticPowered);
      final o=readMeshtasticFrame(meshtasticSample('nodeNoPos'),MeshtasticInfo()).node!;
      expect(o.name,'Sans position'); expect(o.placed,isFalse); expect(o.snr,-7.5); expect(o.hops,isNull);
    });

    test('direct text: sender, text, SNR, RSSI, hops',(){
      final p=readMeshtasticFrame(meshtasticSample('textDirect'),MeshtasticInfo()).packet!;
      expect(p.from,0x0badcafe); expect(p.to,0xa1b2c3d4); expect(p.broadcast,isFalse);
      expect(p.portnum,meshtasticPortText); expect(p.text,'Bonjour Gérard');
      expect(p.id,0x01020304); expect(p.snr,-3.5); expect(p.rssi,-97); expect(p.hops,2);
    });

    test('channel text, position, telemetry, encrypted packet',(){
      final c=readMeshtasticFrame(meshtasticSample('textChannel'),MeshtasticInfo()).packet!;
      expect(c.broadcast,isTrue); expect(c.channel,0); expect(c.text,'Point radio 12 OK'); expect(c.hops,0);
      final p=readMeshtasticFrame(meshtasticSample('positionPacket'),MeshtasticInfo()).packet!;
      final pos=readMeshtasticPosition(p.payload);
      expect(pos.lat,closeTo(48.7,1e-7)); expect(pos.lon,closeTo(2.1,1e-7)); expect(p.hops,1);
      final t=readMeshtasticFrame(meshtasticSample('telemetryMe'),MeshtasticInfo()).packet!;
      final m=readMeshtasticTelemetry(t.payload)!;
      expect(m.battery,9); expect(m.voltage,closeTo(3.4,1e-5));
      final e=readMeshtasticFrame(meshtasticSample('encrypted'),MeshtasticInfo()).packet!;
      expect(e.encrypted,isTrue); expect(e.channel,1); expect(e.text,isNull);
    });

    test('acknowledgement, failure, queue',(){
      final a=readMeshtasticFrame(meshtasticSample('ackDelivered'),MeshtasticInfo()).packet!;
      expect(a.portnum,meshtasticPortRouting); expect(a.requestId,0x11223344);
      expect(readMeshtasticRoutingError(a.payload),0);
      final n=readMeshtasticFrame(meshtasticSample('nakMaxRetransmit'),MeshtasticInfo()).packet!;
      expect(readMeshtasticRoutingError(n.payload),5);
      final q=readMeshtasticFrame(meshtasticSample('queue'),MeshtasticInfo()).queue!;
      expect(q.result,0); expect(q.free,15); expect(q.max,16); expect(q.packetId,0x11223344);
      expect(readMeshtasticFrame(meshtasticSample('queueNeg'),MeshtasticInfo()).queue!.result,-1);
      expect(readMeshtasticFrame(meshtasticSample('rebooted'),MeshtasticInfo()).kind,'rebooted');
    });
  });

  group('ToRadio, byte for byte as Google protobuf',(){
    test('want_config, heartbeat, disconnect',(){
      expect(hex(meshtasticWantConfig(12345)),meshtasticSamples['wantConfig12345']);
      expect(hex(meshtasticHeartbeat()),meshtasticSamples['heartbeat']);
      expect(hex(meshtasticDisconnect()),meshtasticSamples['disconnect']);
    });

    test('direct text and channel text',(){
      expect(hex(meshtasticSendText(to:0x0badcafe,text:'Reçu, 5 sur 5 ',id:0x11223344)),meshtasticSamples['sendDirect']);
      expect(hex(meshtasticSendText(to:meshtasticBroadcast,text:'A tous',id:0x7fffffff)),meshtasticSamples['sendChannel']);
    });

    test('text length: 200 bytes at most',(){
      expect(meshtasticTextFits('a'*200),isTrue);
      expect(meshtasticTextFits('a'*201),isFalse);
      expect(meshtasticTextFits('é'*101),isFalse,reason:'two bytes each');
      expect(meshtasticTextFits('   '),isFalse);
      expect(utf8.encode('é'*100).length,200);
    });
  });

  group('diagnostic lines',(){
    test('region, preset, channel, battery, hardware',(){
      final i=MeshtasticInfo();
      for(final s in ['myInfo','metadata','loraConfig','channelPrimary']){readMeshtasticFrame(meshtasticSample(s),i);}
      final me=readMeshtasticFrame(meshtasticSample('nodeMe'),i).node!;
      final lines={for(final (k,v) in meshtasticLines(i,me,powered:'secteur'))k:v};
      expect(lines['name'],'F4ABC Mobile');
      expect(lines['id'],'!a1b2c3d4');
      expect(lines['model'],'Heltec V3');
      expect(lines['firmware'],'2.6.11.60ec05e');
      expect(lines['radio'],'EU_868 · LongFast');
      expect(lines['power'],'-2 dBm');
      expect(lines['channel'],'LongFast');
      expect(lines['battery'],'18 % · 3.62 V');
      expect(lines['position'],'48.76543, 1.98765');
      expect(meshtasticBatteryText(101,4.1,powered:'secteur'),'secteur · 4.10 V');
    });
  });
}
