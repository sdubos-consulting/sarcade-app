// Card « Consolidation : contrôle automatique des traductions dans la CI »
// (validated on 6 Nov 2026, default choices): no more manual check of
// strings.dart after a merge.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

final _placeholder = RegExp(r'\{(\w+)(?:#[^{}]*)?\}');

Set<String> _placeholders(String text) => {for (final m in _placeholder.allMatches(text)) m.group(1)!};

void main() {
  final fr = S.all['fr']!, en = S.all['en']!;

  test('no key in a single language', () {
    expect(fr.keys.toSet().difference(en.keys.toSet()), isEmpty, reason: 'French only, English missing');
    expect(en.keys.toSet().difference(fr.keys.toSet()), isEmpty, reason: 'English only, French missing');
  });

  test('no empty text', () {
    for (final lang in S.all.entries) {
      final empty = [for (final e in lang.value.entries) if (e.value.trim().isEmpty) e.key];
      expect(empty, isEmpty, reason: 'empty texts in ${lang.key}');
    }
  });

  test('same placeholders in French and English', () {
    final wrong = <String>[];
    for (final k in fr.keys) {
      final e = en[k];
      if (e == null) continue;
      final a = _placeholders(fr[k]!), b = _placeholders(e);
      if (!a.containsAll(b) || !b.containsAll(a)) {
        wrong.add('$k: ${_placeholders(fr[k]!)} / ${_placeholders(e)}');
      }
    }
    expect(wrong, isEmpty);
  });

  test('no key twice in a language (source read as text)', () {
    // A const map refuses equal keys at compile time; this check also names
    // them, after a merge.
    final src = File('lib/src/l10n/strings.dart').readAsStringSync();
    for (final lang in ['_fr', '_en']) {
      final start = src.indexOf('const Texts $lang={');
      final end = src.indexOf('\n};', start);
      final keys = RegExp(r"'([A-Za-z0-9_.\-]+)':").allMatches(src.substring(start, end)).map((m) => m.group(1)!);
      final seen = <String>{}, twice = <String>{};
      for (final k in keys) {
        if (!seen.add(k)) twice.add(k);
      }
      expect(twice, isEmpty, reason: 'keys twice in $lang');
    }
  });

  test('keys not used (warning only)', () {
    final code = StringBuffer();
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart') && !f.path.endsWith('strings.dart')) code.write(f.readAsStringSync());
    }
    final all = code.toString();
    final unused = [for (final k in fr.keys) if (!all.contains("'$k'") && !all.contains('"$k"')) k];
    // Keys built from parts (car.$k, status.$s…) look unused here: only a warning.
    // ignore: avoid_print
    print('traductions : ${unused.length} clés peut-être inutilisées sur ${fr.length}');
  });
}
