// MeshCore companion protocol, frames of the Bluetooth trial
// (1 Nov 2026; layouts from docs.meshcore.io/companion_protocol).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_protocol.dart';

Uint8List _le32(int v)=>Uint8List(4)..buffer.asByteData().setInt32(0,v,Endian.little);

void main() {
  test('commands', () {
    expect(deviceQuery(), [0x16, 0x03]);
    expect(appStart('mccli'), [0x01, 0, 0, 0, 0, 0, 0, 0, 0x6d, 0x63, 0x63, 0x6c, 0x69]);
    expect(batteryQuery(), [0x14]);
  });

  test('DEVICE_INFO: firmware, model, version; PIN never kept nor logged', () {
    final f = Uint8List(80)..[0] = 0x0D..[1] = 8..[2] = 50..[3] = 40;
    f.setRange(4, 8, [0x40, 0xE2, 0x01, 0x00]); // PIN 123456
    f.setRange(8, 8 + 11, ascii.encode('21 Oct 2026'));
    f.setRange(20, 20 + 9, ascii.encode('Heltec V4'));
    f.setRange(60, 60 + 6, ascii.encode('v1.12.0'.substring(0, 6)));
    final i = MeshCoreInfo();
    expect(readMeshCoreFrame(f, i), 'device');
    expect(i.firmwareVersion, 8);
    expect(i.maxContacts, 100);
    expect(i.maxChannels, 40);
    expect(i.model, 'Heltec V4');
    expect(i.build, '21 Oct 2026');
    expect(meshCoreHex(f).substring(0, 24), '0d 08 32 28 00 00 00 00 ');
  });

  test('SELF_INFO: radio, power, position, name', () {
    final f = Uint8List(58);
    f[0] = 0x05; f[1] = 1; f[2] = 22; f[3] = 22;
    f.setRange(4, 8, [0xab, 0xcd, 0x01, 0x02]);
    f.setRange(36, 40, _le32(48804900));
    f.setRange(40, 44, _le32(2120400));
    f.setRange(48, 52, _le32(869525));
    f.setRange(52, 56, _le32(250000));
    f[56] = 11; f[57] = 5;
    final frame = Uint8List.fromList([...f, ...utf8.encode('F4XYZ Mobile')]);
    final i = MeshCoreInfo();
    expect(readMeshCoreFrame(frame, i), 'self');
    expect(i.name, 'F4XYZ Mobile');
    expect(i.frequencyMhz, closeTo(869.525, 1e-9));
    expect(i.bandwidthKhz, closeTo(250.0, 1e-9));
    expect(i.spreadingFactor, 11);
    expect(i.txPowerDbm, 22);
    expect(i.lat, closeTo(48.8049, 1e-6));
    expect(i.publicKeyStart, 'abcd0102');
    final lines = meshCoreLines(i).map((l) => l.$1).toList();
    expect(lines, containsAll(['name', 'radio', 'power', 'position', 'key']));
  });

  test('BATTERY and short or unknown frames', () {
    final i = MeshCoreInfo();
    expect(readMeshCoreFrame(Uint8List.fromList([0x0C, 0x6A, 0x0F, 1, 0, 0, 0, 0, 1, 0, 0]), i), 'battery');
    expect(i.batteryMv, 3946);
    expect(i.storageTotalKb, 256);
    expect(readMeshCoreFrame(Uint8List.fromList([0x05, 1, 2]), i), 'other');
    expect(readMeshCoreFrame(Uint8List(0), i), 'other');
    expect(readMeshCoreFrame(Uint8List.fromList([0x01]), i), 'error');
  });
}
