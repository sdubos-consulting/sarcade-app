/// Operator colour and initials, Core (lot C, card « Séparer le Core et les
/// modules », 1 Nov 2026): used by the traces, the points and the bearings
/// of the ADRASEC module alike. Moved from the bearings models.
///
/// Card « Carte : la trace d'un opérateur dans la couleur choisie dans son
/// profil » (validated on 10 Nov 2026, choices 1 to 8): each device shares
/// its colour (the one of the profile, else the automatic one of the event)
/// and the server passes it on with the devices and the positions; the
/// trace, the dot on the map, the line of Équipes and the TV all take it.
/// A device that shares none (former version) keeps the palette below.
library;

import 'package:flutter/material.dart';

/// Colour used instead of a red one: the red is reserved for the SOS and the
/// 121.5 MHz beacons (same as the points of interest, poi_sheet.dart).
const reservedRedFallback=0xFF1E88E5;

/// True for a red: hue within 20° of 0 and saturated enough to be read as red.
bool isReservedRed(int argb){
  final hsv=HSVColor.fromColor(Color(argb));
  return hsv.saturation>0.45&&hsv.value>0.35&&(hsv.hue<=20||hsv.hue>=340);
}

/// Colour shown for a profile colour (choice 4): opaque, a red replaced by
/// [reservedRedFallback].
int sharedOperatorColor(int profile){
  final c=profile|0xFF000000;
  return isReservedRed(c)?reservedRedFallback:c;
}

/// Colour of an operator: the one his device shares (profile, 10 Nov 2026),
/// else stable from the identifier (palette of 10, as before).
int operatorColor(String id){
  final shared=OperatorColors.instance.of(id);
  return shared!=null?sharedOperatorColor(shared):paletteColor(id);
}

/// Former colour, stable from the identifier: devices that share no colour.
int paletteColor(String id){
  const palette=[0xFFE53935,0xFFFB8C00,0xFF43A047,0xFF1E88E5,0xFF8E24AA,0xFF00897B,0xFFD81B60,0xFF6D4C41,0xFF3949AB,0xFF7CB342];
  var h=0; for(final c in id.codeUnits){h=(h*31+c)&0x7FFFFFFF;}
  return palette[h%palette.length];
}

/// Colours shared by the devices of the event (10 Nov 2026), learned from
/// the list of the devices, `device.updated` and the positions; this
/// device's own colour is set at once when the profile changes (choice 7:
/// the trace already shown is painted again, it is a display).
class OperatorColors extends ChangeNotifier {
  OperatorColors();
  static final OperatorColors instance=OperatorColors();
  final Map<String,int> _byDevice={};

  /// Colour shared by [id], null when none (palette).
  int? of(String id)=>_byDevice[id];

  /// Colour [colour] of [id] (an int from the JSON); null or 0 forgets it.
  /// True when it changed.
  bool learn(String id,Object? colour){
    if(id.isEmpty)return false;
    final c=colour is int&&colour>0&&colour<=0xFFFFFFFF?colour:null;
    if(_byDevice[id]==c)return false;
    if(c==null){_byDevice.remove(id);}else{_byDevice[id]=c;}
    notifyListeners();
    return true;
  }

  /// Colours of a list of devices or positions (`device_id`, `color`):
  /// only the entries that carry the key, so that a former server (no
  /// `color` at all) never erases a colour.
  void learnAll(Iterable<Map> list){
    for(final d in list){if(d.containsKey('color'))learn('${d['device_id']??''}',d['color']);}
  }

  /// The profile colour of this device changed (Paramètres): listeners
  /// read it again.
  void profileChanged()=>notifyListeners();

  @visibleForTesting
  void clear(){_byDevice.clear();notifyListeners();}
}

/// Initials shown in the dot: callsign or terminal, two characters.
String operatorInitials(String id){
  final t=id.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'),'');
  return t.length<=2?t:t.substring(0,2);
}
