// Card « Messages : coller une image » (validated on 5 Nov 2026, done on
// 9 Nov 2026): a pasted image is made like a photo taken by the device.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sarcade_app/src/features/messages/photo_attachment.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main() {
  test('a large screenshot: 1920 px at most, JPEG', () {
    final png = Uint8List.fromList(img.encodePng(img.Image(width: 2556, height: 1179)));
    final out = preparePastedImage(png)!;
    expect(out.mime, 'image/jpeg');
    final back = img.decodeJpg(out.bytes)!;
    expect(back.width, 1920);
    expect(back.height, closeTo(1179 * 1920 / 2556, 1));
  });

  test('a small image keeps its size; a GIF stays a GIF; not an image: null', () {
    final small = preparePastedImage(Uint8List.fromList(img.encodePng(img.Image(width: 300, height: 200))))!;
    expect(img.decodeJpg(small.bytes)!.width, 300);
    final gif = Uint8List.fromList(img.encodeGif(img.Image(width: 10, height: 10)));
    expect(preparePastedImage(gif)!.mime, 'image/gif');
    expect(preparePastedImage(gif)!.bytes, gif);
    expect(preparePastedImage(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });

  test('texts of the menu', () {
    S.setLanguage('fr');
    expect(S.t('messages.pasteImage'), 'Coller une image');
    expect(S.t('messages.pasteNone'), 'Aucune image à coller');
  });
}
