/// Loading screen of the application (card « Windows : logo SARCADE affiché
/// dès le clic sur l'icône », 1 Nov 2026, point 5): the same logo as the
/// native start window, shown from the first image of Flutter until the
/// local start is done (storage, access), so that no empty screen comes
/// between the start window and the map.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'theme.dart';

/// Shown on Windows only: the other platforms have their own start screen.
bool get showsStartupSplash=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.windows;

class StartupSplash extends StatelessWidget {
  /// Theme of the device when null (same rule as the native window).
  final Brightness? brightness;
  const StartupSplash({super.key,this.brightness});

  static String logoFor(Brightness b)=>b==Brightness.dark?'assets/logo/sarcade-logo-dark.png':'assets/logo/sarcade-logo-light.png';

  @override
  Widget build(BuildContext context){
    final b=brightness??PlatformDispatcher.instance.platformBrightness;
    final dark=b==Brightness.dark;
    return MaterialApp(
      title:'SARCADE',
      debugShowCheckedModeBanner:false,
      home:Scaffold(
        backgroundColor:dark?SarcadeColors.ground:Colors.white,
        body:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
          Image.asset(logoFor(b),width:200,semanticLabel:'SARCADE',
            errorBuilder:(_,_,_)=>const SizedBox(width:200,height:102)),
          const SizedBox(height:20),
          Text(S.t('win.starting'),style:TextStyle(color:dark?SarcadeColors.muted:PlayBlue.inkMuted,fontSize:15)),
          const SizedBox(height:16),
          SizedBox(width:200,child:LinearProgressIndicator(minHeight:4,
            color:dark?SarcadeColors.cyan:PlayBlue.primary,
            backgroundColor:dark?const Color(0xFF16212B):PlayBlue.cardHigh)),
        ])),
      ),
    );
  }
}
