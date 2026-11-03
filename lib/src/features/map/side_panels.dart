/// Side panels « Opérateurs » and « Messages » on a wide screen (computer,
/// tablet in landscape), card « PC : le panneau Opérateurs se ferme au clic
/// sur la carte » (lot 25, decided on 3 Nov 2026, 13 h 21):
/// 1. they stay open when the map is clicked; the map shrinks beside them
///    instead of being covered;
/// 2. they close by a new click on their icon of the rail or by the ✕ at
///    their top;
/// 3. open or closed, kept from one start of SARCADE to the next;
/// 4. phone unchanged: the panel covers the map and a touch on the map
///    closes it.
library;

/// Width under which the screen is a phone (`_compactWidth` of the map).
const double sidePanelsCompactWidth=600;

/// Preference holding the panel open on a wide screen (`teams`,
/// `messages`, or nothing).
const String sidePanelPreference='side_panel_open';

/// The two panels kept from one start to the next.
enum SidePanel { teams, messages }

/// Panel to open at start on a wide screen; none on a phone (the map first).
SidePanel? sidePanelAtStart(String? saved,{required double screenWidth}){
  if(screenWidth<sidePanelsCompactWidth)return null;
  for(final p in SidePanel.values){if(p.name==saved)return p;}
  return null;
}

/// Value saved for the panel now open (null: closed).
String? sidePanelSaved(SidePanel? open)=>open?.name;

/// A touch on the map closes the side panels on a phone only.
bool mapTapClosesSidePanels({required bool compact})=>compact;

/// Room always left to the map beside the Messages panel.
const double mapMinBesideMessages=280;

/// Messages panel: as wide as the room allows, up to the two-column layout
/// of the Messages screen (900, like WhatsApp Web), never under 420 (the
/// width of a conversation opened from an operator's sheet).
double messagesPanelWidth(double room)=>(room-mapMinBesideMessages).clamp(420.0,900.0).toDouble();
