/// Keyboard of phones and tablets (card « Messages : le clavier reste ouvert
/// après l'envoi », validated on 5 Nov 2026, 17 h 13; blocking at 18 h 54:
/// the porter had to close SARCADE to leave the search of Messages).
///
/// Flutter keeps the on-screen keyboard open when a finger touches the
/// screen outside a text field (platform convention); SARCADE closes it,
/// on every text field of the application, so that the bottom menu is
/// always reachable again.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Phone or tablet (iOS, Android, and their browsers): the keyboard is on the
/// screen and hides part of it.
bool get touchKeyboard=>defaultTargetPlatform==TargetPlatform.iOS||defaultTargetPlatform==TargetPlatform.android;

/// Closes the keyboard of any text field touched outside (pointer down
/// outside the field and its selection toolbar).
Widget closeKeyboardOnTapOutside(Widget child)=>Actions(
  actions:<Type,Action<Intent>>{
    EditableTextTapOutsideIntent:CallbackAction<EditableTextTapOutsideIntent>(onInvoke:(intent){
      intent.focusNode.unfocus();
      return null;
    }),
  },
  child:child);

/// Closes the keyboard (any focused text field).
void closeKeyboard()=>FocusManager.instance.primaryFocus?.unfocus();
