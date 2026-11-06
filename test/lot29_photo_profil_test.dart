import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/operator_avatar.dart';
import 'package:sarcade_app/src/features/profile/profile_photo.dart';

void main(){
  test('only the photos new or changed are fetched',(){
    final d=photoDiff({'TEL-01':'2026-11-05T20:00:00Z','TEL-02':'2026-11-05T20:00:00Z','TEL-09':'x'},[
      {'device_id':'TEL-01','updated_at':'2026-11-05T20:00:00Z'},
      {'device_id':'TEL-02','updated_at':'2026-11-05T21:00:00Z'},
      {'device_id':'TEL-03','updated_at':'2026-11-05T21:00:00Z'},
    ]);
    expect(d.fetch,['TEL-02','TEL-03']);
    expect(d.forget,['TEL-09']);
  });
  test('index kept as text, damaged ignored',(){
    expect(parsePhotoIndex('{"TEL-01":"t"}'),{'TEL-01':'t'});
    expect(parsePhotoIndex('[]'),isEmpty);
    expect(parsePhotoIndex('pas du json'),isEmpty);
  });
  test('256 px, under 64 KB',(){
    expect(photoSide,256);
    expect(photoMaxBytes,65536);
  });
  testWidgets('initials without photo',(t) async {
    ProfilePhotos.instance.value={};
    await t.pumpWidget(MaterialApp(home:Scaffold(body:operatorAvatar('TEL-01'))));
    expect(find.byType(Text),findsOneWidget);
  });
  testWidgets('the photo in place of the initials',(t) async {
    // 1 × 1 transparent PNG.
    ProfilePhotos.instance.value={'TEL-01':Uint8List.fromList(const [
      0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
      0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,0x89,0x00,0x00,0x00,0x0A,0x49,0x44,0x41,0x54,0x78,0x9C,0x63,0x00,0x01,0x00,0x00,
      0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,0x42,0x60,0x82])};
    await t.pumpWidget(MaterialApp(home:Scaffold(body:operatorAvatar('TEL-01'))));
    expect(find.byType(Text),findsNothing);
    ProfilePhotos.instance.value={};
  });
}
