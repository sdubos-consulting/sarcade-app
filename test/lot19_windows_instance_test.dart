import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/offline/compaction_guard.dart';

// Card « Windows : pastille de liaison grise alors que le Diagnostic dit
// « Tout fonctionne » » (lot 19, points 1, 2, 3 and 6).
void main() {
  group('native runner', () {
    const names = ['single_instance.h', 'single_instance.cpp', 'runner_channel.h', 'runner_channel.cpp', 'splash_window.h', 'splash_window.cpp'];

    test('new native sources exist and are plain ASCII', () {
      for (final name in names) {
        final f = File('tool/windows_runner/$name');
        expect(f.existsSync(), isTrue, reason: name);
        final bytes = f.readAsBytesSync();
        expect(bytes.where((b) => b > 127), isEmpty, reason: '$name: non-ASCII character');
      }
    });

    test('second instance refused with a named lock, first window to the front', () {
      final src = File('tool/windows_runner/single_instance.cpp').readAsStringSync();
      expect(src, contains('CreateMutexW'));
      expect(src, contains('ERROR_ALREADY_EXISTS'));
      expect(src, contains('FLUTTER_RUNNER_WIN32_WINDOW'));
      expect(src, contains('SARCADE_SPLASH'));
      expect(src, contains('SetForegroundWindow'));
      for (final name in names) {
        final text = File('tool/windows_runner/$name').readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');
        expect(RegExp(r'\b(exit|ExitProcess|TerminateProcess)\(').hasMatch(text), isFalse, reason: '$name: abrupt end');
      }
    });

    test('patch: refusal before the start window, clean return from wWinMain', () {
      final py = File('tool/patch_windows.py').readAsStringSync();
      expect(py, contains('patch_single_instance'));
      final guard = py.indexOf('if (!single_instance::Acquire())');
      expect(guard, greaterThan(0));
      expect(py.substring(guard), contains('single_instance::ShowExisting();'));
      expect(py.substring(guard), contains('return EXIT_SUCCESS;'));
      expect(py, contains(r'splash_window::Start\(instance\)'));
      expect(py, contains('return runner_channel::ExitCode();'));
      expect(py, contains('runner_channel::Register(flutter_controller_->engine()->messenger(), GetHandle());'));
    });

    test('the Dart code quits through the runner, not exit()', () {
      final io = File('lib/src/platform/platform_services_io.dart').readAsStringSync();
      expect(io, contains("MethodChannel('sarcade/runner')"));
      expect(io, contains("invokeMethod<void>('quit',code)"));
      expect(io, contains('void quitApp()=>exitProcess(0);'));
      final channel = File('tool/windows_runner/runner_channel.cpp').readAsStringSync();
      expect(channel, contains('"sarcade/runner"'));
      expect(channel.indexOf('splash_window::Stop();'), lessThan(channel.indexOf('PostMessageW(g_window, WM_CLOSE')));
    });

    test('start test launches twice and looks for Application Error', () {
      final ps = File('tool/windows_smoke.ps1').readAsStringSync();
      expect(ps, contains(r'$p2 = Start-Process -FilePath $Exe -PassThru'));
      expect(ps, contains("ProviderName = 'Application Error'"));
      expect(ps, contains('::error title=Windows second instance'));
    });
  });

  group('local storage compaction', () {
    test('Hive never compacts inside a write, the box is marked', () {
      final guard = CompactionGuard(compact: (_) async {}, delay: const Duration(hours: 1));
      addTearDown(guard.dispose);
      final strategy = guard.strategyFor('meta');
      expect(strategy(100, 10), isFalse);
      expect(guard.pending, isEmpty);
      expect(strategy(100, 80), isFalse);
      expect(guard.pending, {'meta'});
    });

    test('same rule as the default strategy of Hive', () {
      expect(CompactionGuard.needed(1000, 60), isFalse);
      expect(CompactionGuard.needed(1000, 100), isFalse);
      expect(CompactionGuard.needed(300, 61), isTrue);
      expect(CompactionGuard.needed(0, 0), isFalse);
    });

    test('a refused rename is logged and tried again later, never thrown', () async {
      var calls = 0;
      final lines = <String>[];
      final guard = CompactionGuard(
        compact: (box) async {
          calls++;
          if (calls == 1) throw const PathAccessException('meta.hivec', OSError('Accès refusé', 5), 'Cannot rename file');
        },
        log: lines.add,
        delay: const Duration(hours: 1),
        retryAfter: const Duration(hours: 1),
      );
      addTearDown(guard.dispose);
      guard.mark('meta');
      await guard.run();
      expect(calls, 1);
      expect(guard.pending, {'meta'});
      expect(lines.single, contains('compactage de « meta » reporté'));
      expect(lines.single, contains('nouvel essai dans 60 min'));
      await guard.run();
      expect(calls, 2);
      expect(guard.pending, isEmpty);
      expect(lines, hasLength(1));
    });

    test('marked boxes are compacted after the delay', () async {
      final done = <String>[];
      final guard = CompactionGuard(compact: (box) async => done.add(box), delay: const Duration(milliseconds: 10));
      addTearDown(guard.dispose);
      guard.strategyFor('positions')(200, 100);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(done, ['positions']);
    });
  });
}
