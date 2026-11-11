/// Messages read aloud on the phone (card « Messages : lecture à voix haute
/// sur le téléphone », validated on 5 Nov 2026, default choices; done on
/// 9 Nov 2026): never, in the car, always; Urgent and above by default.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../l10n/strings.dart';
import '../../models/message.dart';
import '../../offline/local_store.dart';

/// Choices of Paramètres › Notifications › « Lire les messages à voix haute ».
const readAloudModes=['never','car','always'];
const readAloudDefault='car';
const readAloudModeKey='read_aloud';
const readAloudRoutineKey='read_aloud_routine';
/// « En voiture » also when the phone moves faster than this (choice 2).
const readAloudCarSpeedKmh=20.0;
/// A speed older than this no longer counts.
const readAloudSpeedValidity=Duration(minutes:2);

String readAloudMode(LocalStore? store){
  final v=store?.preference(readAloudModeKey);
  return v is String&&readAloudModes.contains(v)?v:readAloudDefault;
}

bool readAloudRoutine(LocalStore? store)=>store?.preference(readAloudRoutineKey)=='1';

/// Whether a message of [priority] is read now (choices 1, 2 and 4).
bool shouldReadAloud({required String mode,required bool routineToo,required String priority,required bool inCar}){
  if(mode=='never')return false;
  if(mode=='car'&&!inCar)return false;
  return priorityRaised(priority)||routineToo;
}

/// Same sentence as Android Auto (choice 3): « Urgent. android-demo : … ».
String readAloudText(SarcadeMessage m){
  final text=m.body.trim().isEmpty?S.t('car.photo'):m.body.trim().replaceAll(RegExp(r'\s+'),' ');
  return S.t('car.speak',{
    'prio':priorityRaised(m.priority)?'${S.t(priorityKey(m.priority))}. ':'',
    'who':m.senderId,
    'text':text.replaceFirst(RegExp(r'[.!?…]+$'),''),
  });
}

/// The voice of the system (choice 5), in the language of the application.
class ReadAloud {
  ReadAloud._();
  static final instance=ReadAloud._();

  FlutterTts? _tts;
  double? _speedKmh; DateTime? _speedAt;
  /// CarPlay or Android Auto shows SARCADE (car_screen_channel.dart).
  bool carSession=false;

  /// Speed of the phone (positions of the map or of the beacon).
  void noteSpeed(double metresPerSecond,{DateTime? at}){
    if(metresPerSecond.isNaN||metresPerSecond<0)return;
    _speedKmh=metresPerSecond*3.6; _speedAt=at??DateTime.now();
  }

  /// In a car: a car screen shows SARCADE, or the phone moves faster than
  /// 20 km/h. The Bluetooth of the car is not read yet (native code).
  bool inCar({DateTime? now}){
    if(carSession)return true;
    final at=_speedAt, v=_speedKmh;
    if(at==null||v==null)return false;
    return (now??DateTime.now()).difference(at)<readAloudSpeedValidity&&v>readAloudCarSpeedKmh;
  }

  Future<void> speak(String text) async {
    if(text.trim().isEmpty)return;
    try{
      final tts=_tts??=await _init();
      await tts.setLanguage(S.lang=='en'?'en-GB':'fr-FR');
      await tts.speak(text);
    }catch(e){
      debugPrint('SARCADE read aloud failed: $e');
    }
  }

  Future<FlutterTts> _init() async {
    final tts=FlutterTts();
    if(!kIsWeb&&defaultTargetPlatform==TargetPlatform.iOS){
      // Other sounds (music, navigation) lowered while SARCADE speaks.
      await tts.setSharedInstance(true);
      await tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback,
        [IosTextToSpeechAudioCategoryOptions.duckOthers,IosTextToSpeechAudioCategoryOptions.interruptSpokenAudioAndMixWithOthers],
        IosTextToSpeechAudioMode.voicePrompt);
    }
    await tts.awaitSpeakCompletion(false);
    return tts;
  }
}
