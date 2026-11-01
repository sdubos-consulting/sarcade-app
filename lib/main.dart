import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'src/access/access_manager.dart';
import 'src/app.dart';
import 'src/l10n/strings.dart';
import 'src/offline/local_store.dart';
import 'src/platform/platform_services.dart';
import 'src/platform/startup_report.dart';
import 'src/services/power_state.dart';
import 'src/ui/startup_splash.dart';

Future<void> main() async {
  // Every error, also outside Flutter's own handlers, goes to the startup
  // report (card « Client Windows : écran gris au démarrage », 31 Oct 2026).
  await runZonedGuarded(_start,(e,s)=>StartupReport.error('zone',e,s));
}

Future<void> _start() async {
  WidgetsFlutterBinding.ensureInitialized();
  StartupReport.begin();
  // Release builds hide widget errors (grey area): write them down and
  // show a readable message instead.
  final previous=FlutterError.onError;
  FlutterError.onError=(details){
    StartupReport.error('flutter',details.exception,details.stack);
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError=(e,s){StartupReport.error('platform',e,s);return true;};
  if(kReleaseMode)ErrorWidget.builder=readableErrorWidget;
  if (!await acquireSingleInstance()) {
    // Windows V0.1: refuse a second process before Hive is opened.
    // Native foreground activation will be added in the packaged Windows runner.
    StartupReport.note('deuxième instance refusée');
    quitApp();
    return;
  }
  if(showsStartupSplash){
    // Same logo as the native start window, until the local start is done
    // (card « Windows : logo SARCADE affiché dès le clic sur l'icône »).
    S.setLanguage('system',systemLanguage:PlatformDispatcher.instance.locale.languageCode);
    StartupReport.note('écran de chargement');
    runApp(const StartupSplash());
  }
  final LocalStore store;
  try{
    store=LocalStore();
    StartupReport.note('stockage local');
    await store.init();
    PowerState.instance.init(store);
    StartupReport.note('accès');
    await AccessManager.instance.load();
  }catch(e,s){
    StartupReport.error('démarrage',e,s);
    StartupReport.watchFirstFrame();
    runApp(StartupErrorApp(message:'$e'));
    return;
  }
  StartupReport.note('interface');
  StartupReport.watchFirstFrame();
  runApp(SarcadeApp(store:store));
}
