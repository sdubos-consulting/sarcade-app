import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Card « Windows : « DÃ©marrageâ€¦ » au lieu de « Démarrage… » » (1 Nov 2026,
// 18 h 57): the native sources of the Windows runner are compiled without
// the UTF-8 flag, so an accented character in them is read as Windows-1252.
// They must stay plain ASCII; accented texts are written with \u escapes.
void main() {
  test('native Windows sources are plain ASCII', () {
    final dir = Directory('tool/windows_runner');
    expect(dir.existsSync(), isTrue);
    final bad = <String>[];
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!RegExp(r'\.(cpp|h|rc)$').hasMatch(f.path)) continue;
      final bytes = f.readAsBytesSync();
      var line = 1;
      for (final b in bytes) {
        if (b == 10) line++;
        if (b > 127) {
          bad.add('${f.path}:$line');
          break;
        }
      }
    }
    expect(bad, isEmpty, reason: 'non-ASCII character in a native source');
  });

  test('the start text is written with escapes', () {
    final src = File('tool/windows_runner/splash_window.cpp').readAsStringSync();
    expect(src, contains(r'L"D\u00E9marrage\u2026"'));
    expect(src, contains(r'L"Starting\u2026"'));
  });
}
