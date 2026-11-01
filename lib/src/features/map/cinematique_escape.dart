/// Card « Échap : fiche d'opérateur et forme en cours » of the cinématique
/// review of lot 16 (constat L3, decided by the project owner, 1 Nov 2026,
/// 12 h 15): while drawing, a first Échap drops the shape being drawn, a
/// second one leaves the tool and closes the drawing bar (same order as
/// rule N1, PR #155).
library;

import 'package:flutter/foundation.dart';

import 'drawing/drawing_controller.dart';

/// Échap while a drawing tool is active. Returns false when no tool is
/// active (Échap goes on to the next thing open). [closeBar] closes the
/// drawing bar.
bool escapeDrawing(DrawingController c,{required VoidCallback closeBar}){
  if(!c.isDrawing)return false;
  if(c.draft.isNotEmpty){c.cancelDraft();return true;}
  c.selectTool(null);
  closeBar();
  return true;
}
