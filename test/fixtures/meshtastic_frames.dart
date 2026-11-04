// SPDX-License-Identifier: MPL-2.0
// © SDUBOS Consulting et contributeurs SARCADE

// Sample Meshtastic messages (lot 28), hexadecimal, encoded by Google's
// protobuf library (Python) from a minimal schema written for these tests
// (field numbers of the public client API, no Meshtastic .proto file):
// an independent check of the decoder written by hand.
import 'dart:typed_data';

const meshtasticSamples=<String,String>{
  'myInfo':'1a0608d487cb8d0a',
  'metadata':'6a120a0e322e362e31312e36306563303565482b',
  'loraConfig':'2a153213080138034003480150feffffffffffffffff01',
  'channelPrimary':'520712031201011801',
  'channelSecondary':'520f080112091a07414452415345431802',
  'nodeMe':'224608d487cb8d0a12210a09216131623263336434120c4634414243204d6f62696c651a0446344142282b1a0d0db103111d15bf4a2f011898012d4037eb6a320708121514ae6740',
  'nodeRouter':'224908fe95b75d12260a09213062616463616665120f52656c616973204d617572657061731a04524d4155280938021a0a0dc03c131d15e08b2901250000c8402d5833eb6a320208654802',
  'nodeNoPos':'222108f8acd19101120f120d53616e7320706f736974696f6e250000f0c02d3010eb6a',
  'configComplete':'382a',
  'textDirect':'123d0dfecaad0b15d4c3b2a122130801120f426f6e6a6f75722047c3a97261726435040302013da437eb6a45000060c04801609fffffffffffffffff017803',
  'textChannel':'122f0d7856341215ffffffff221508011211506f696e7420726164696f203132204f4b350d0c0b0a3d0838eb6a48037803',
  'ackDelivered':'121c0dfecaad0b15d4c3b2a1220b08051202180035443322113588776655',
  'nakMaxRetransmit':'12170dd4c3b2a115d4c3b2a1220b0805120218053544332211',
  'positionPacket':'12280d7856341215ffffffff22130803120f0dc007071d15406f4001256c38eb6a3d6c38eb6a48027803',
  'telemetryMe':'121e0dd4c3b2a115ffffffff22120843120e0dd038eb6a12070809159a995940',
  'encrypted':'12160dfecaad0b15ffffffff18012a039988773507000000',
  'queue':'5a0a100f181020c4e6888901',
  'rebooted':'4001',
  'wantConfig12345':'18b960',
  'heartbeat':'3a00',
  'disconnect':'2001',
  'sendDirect':'0a2015fecaad0b22120801120e5265c3a7752c203520737572203535443322115001',
  'sendChannel':'0a1815ffffffff220a080112064120746f757335ffffff7f5001',
  'queueNeg':'5a0b08ffffffffffffffffff01',
};

Uint8List meshtasticSample(String name){
  final h=meshtasticSamples[name]!;
  return Uint8List.fromList([for(var i=0;i<h.length;i+=2)int.parse(h.substring(i,i+2),radix:16)]);
}
