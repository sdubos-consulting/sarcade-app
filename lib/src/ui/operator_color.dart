/// Operator colour and initials, Core (lot C, card « Séparer le Core et les
/// modules », 1 Nov 2026): used by the traces, the points and the bearings
/// of the ADRASEC module alike. Moved from the bearings models.
library;

/// Colour of an operator (dot where a bearing was taken), stable from the
/// identifier, until the operator colours of the event exist.
int operatorColor(String id){
  const palette=[0xFFE53935,0xFFFB8C00,0xFF43A047,0xFF1E88E5,0xFF8E24AA,0xFF00897B,0xFFD81B60,0xFF6D4C41,0xFF3949AB,0xFF7CB342];
  var h=0; for(final c in id.codeUnits){h=(h*31+c)&0x7FFFFFFF;}
  return palette[h%palette.length];
}

/// Initials shown in the dot: callsign or terminal, two characters.
String operatorInitials(String id){
  final t=id.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'),'');
  return t.length<=2?t:t.substring(0,2);
}
