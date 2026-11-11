import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/platform/startup_report.dart';
import 'package:sarcade_app/src/ui/startup_splash.dart';

// Card « Windows : logo SARCADE affiché dès le clic sur l'icône » (1 Nov 2026).
void main() {
  tearDown(() => S.setLanguage('fr'));

  testWidgets('loading screen: logo, text and animated bar', (t) async {
    S.setLanguage('fr');
    await t.pumpWidget(const StartupSplash(brightness: Brightness.dark));
    await t.pump(const Duration(milliseconds: 100));
    final image = t.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, 'assets/logo/sarcade-logo-dark.png');
    expect(find.text('Démarrage…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('loading screen follows the light theme, in English', (t) async {
    S.setLanguage('en');
    await t.pumpWidget(const StartupSplash(brightness: Brightness.light));
    await t.pump(const Duration(milliseconds: 100));
    final image = t.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, 'assets/logo/sarcade-logo-light.png');
    expect(find.text('Starting…'), findsOneWidget);
  });

  test('same logos as the native start window', () {
    expect(StartupSplash.logoFor(Brightness.dark), 'assets/logo/sarcade-logo-dark.png');
    expect(StartupSplash.logoFor(Brightness.light), 'assets/logo/sarcade-logo-light.png');
  });

  test('loading screen only on Windows (tests run as Android)', () {
    expect(showsStartupSplash, isFalse);
  });

  test('start time is measured from the beginning of the Dart code', () {
    StartupReport.begin();
    expect(StartupReport.clock.isRunning, isTrue);
  });
}
