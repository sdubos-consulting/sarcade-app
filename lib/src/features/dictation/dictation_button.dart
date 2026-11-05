import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../l10n/strings.dart';
import 'dictation.dart';

/// A dictation is running somewhere (the message bar keeps the microphone,
/// it does not turn into « Envoyer » after the first words; lot 29).
final ValueNotifier<bool> dictationActive=ValueNotifier(false);

/// Longest dictation, and silence tolerated before the system closes it
/// (card « Dictée : le micro s'arrête au bout de 2 ou 3 secondes », lot 29).
const dictationMaxLength=Duration(seconds:60);
const dictationPause=Duration(seconds:5);

/// « 0:12 » under the microphone while listening.
String dictationElapsed(Duration d)=>'${d.inMinutes}:${(d.inSeconds%60).toString().padLeft(2,'0')}';

/// Microphone next to a text field: tap to dictate, tap again to stop.
/// Windows and Linux: a tap explains the system dictation (Windows + H).
class DictationButton extends StatefulWidget {
  final TextEditingController controller;
  /// Called after each recognised piece (the search runs again).
  final VoidCallback? onChanged;
  /// Round coloured button (the send position of the message bar).
  final bool filled;
  const DictationButton({super.key,required this.controller,this.onChanged,this.filled=false});
  @override State<DictationButton> createState()=>_DictationButtonState();
}

class _DictationButtonState extends State<DictationButton> {
  static final SpeechToText _speech=SpeechToText();
  static bool? _available;
  /// The user wants to dictate: the listening starts again when the system
  /// closes it on a pause, until the stop button or 60 s (lot 29).
  bool _wanted=false;
  bool get _listening=>_wanted;
  String _before='';
  DateTime? _since;
  Timer? _tick;
  static _DictationButtonState? _owner;

  bool get _offered=>dictationOffered(isWeb:kIsWeb,targetPlatform:defaultTargetPlatform.name);

  void _snack(String t){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t)));}

  void _onStatus(String s){
    final o=_owner; if(o==null||!o.mounted)return;
    if(s=='done'||s=='notListening')o._closedBySystem();
  }
  void _onError(Object _){
    final o=_owner; if(o==null||!o.mounted)return;
    o._finish();
  }

  /// The system closed the listening (pause, end of a sentence): it starts
  /// again with the text already dictated, unless the user stopped.
  void _closedBySystem(){
    if(!_wanted)return;
    final since=_since;
    if(since==null||DateTime.now().difference(since)>=dictationMaxLength){_finish();return;}
    Future<void>.delayed(const Duration(milliseconds:250),(){if(_wanted&&mounted&&!_speech.isListening)unawaited(_listen());});
  }

  void _finish(){
    _tick?.cancel(); _tick=null;
    _wanted=false; _since=null;
    if(_owner==this){_owner=null;dictationActive.value=false;}
    if(mounted)setState((){});
  }

  Future<void> _listen() async {
    _before=widget.controller.text;
    await _speech.listen(
      listenFor:dictationMaxLength,pauseFor:dictationPause,
      listenOptions:SpeechListenOptions(localeId:dictationLocale(S.lang),partialResults:true,cancelOnError:true,listenMode:ListenMode.dictation),
      onResult:(r){
        if(!_wanted)return;
        final c=widget.controller;
        final text=dictatedText(_before,r.recognizedWords);
        c.value=TextEditingValue(text:text,selection:TextSelection.collapsed(offset:text.length));
        widget.onChanged?.call();
      },
    );
  }

  Future<void> _toggle() async {
    if(!_offered){_snack(S.t('dictation.windows'));return;}
    if(_wanted){_finish();await _speech.stop();return;}
    try{
      _available??=await _speech.initialize(onStatus:_onStatus,onError:_onError);
    }catch(_){_available=false;}
    if(_available!=true){_snack(S.t('dictation.unavailable'));return;}
    _owner?._finish();
    _owner=this; _wanted=true; _since=DateTime.now(); dictationActive.value=true;
    _tick=Timer.periodic(const Duration(seconds:1),(_){
      if(!mounted)return;
      if(_since!=null&&DateTime.now().difference(_since!)>=dictationMaxLength){_finish();unawaited(_speech.stop());return;}
      setState((){});
    });
    setState((){});
    await _listen();
  }

  @override void dispose(){
    _tick?.cancel();
    if(_owner==this){_owner=null;dictationActive.value=false;if(_wanted)_speech.stop();}
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
    final since=_since;
    final elapsed=since==null?null:dictationElapsed(DateTime.now().difference(since));
    final button=widget.filled
      ? IconButton.filled(
          tooltip:_listening?S.t('dictation.stop'):S.t('dictation.start'),
          onPressed:_toggle,
          style:_listening?IconButton.styleFrom(backgroundColor:Colors.red):null,
          icon:Icon(_listening?Icons.stop:Icons.mic),
        )
      : IconButton(
          tooltip:_listening?S.t('dictation.stop'):S.t('dictation.start'),
          onPressed:_toggle,
          color:_listening?Colors.red:null,
          icon:Icon(_listening?Icons.mic:Icons.mic_none),
        );
    if(elapsed==null)return button;
    // Counter while listening (« 0:12 »).
    return Badge(key:const ValueKey('dictation-elapsed'),label:Text(elapsed),backgroundColor:Colors.red,offset:const Offset(-2,-2),child:button);
  }
}
