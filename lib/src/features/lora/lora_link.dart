// SPDX-License-Identifier: MPL-2.0
// © SDUBOS Consulting et contributeurs SARCADE

/// What the Bluetooth links to a LoRa module share (lot 28, card « Module
/// Meshtastic, sur le modèle de MeshCore »): the states of the link, the
/// colour of the pill, the delays between attempts, and the short texts of
/// the lists (« il y a 3 min », « 2 sauts »). MeshCore (meshcore_link.dart)
/// and Meshtastic (meshtastic_link.dart) use them alike.
library;

import '../../l10n/strings.dart';

/// [waitingClick]: web app, the browser lets join the module only after a
/// click in this tab. [disconnected]: « Déconnecter » was pressed, the
/// module stays remembered but is not joined again until « Se connecter ».
/// [unavailable]: web app, « Reconnecter » failed (module off or out of
/// reach); no automatic attempt.
enum LoraLinkState { none, connecting, connected, reconnecting, failed, waitingClick, disconnected, unavailable }

/// Colour family of the pill: 'off' (no module, or disconnected on purpose:
/// grey), 'ok', 'wait', 'bad'.
String loraPillTone(LoraLinkState s)=>switch(s){
  LoraLinkState.none||LoraLinkState.disconnected=>'off', LoraLinkState.connected=>'ok',
  LoraLinkState.connecting||LoraLinkState.reconnecting||LoraLinkState.waitingClick=>'wait', LoraLinkState.failed||LoraLinkState.unavailable=>'bad'};

/// Delay before the next attempt to join the module again: 5 s, 15 s,
/// 30 s, then every minute.
Duration loraRetryDelay(int attempt)=>Duration(seconds:const [5,15,30,60][attempt.clamp(0,3)]);

/// Text of the state (« connecté », « reconnexion… »).
String loraStateText(LoraLinkState s)=>S.t('mesh.state.${s.name}');

/// Text shown when the module cannot be reached; the technical error stays
/// in the journal only.
String? loraProblem({required LoraLinkState state,required bool trying,String? error,Duration? retryIn}){
  if(error==null||trying||state==LoraLinkState.connected||state==LoraLinkState.none||state==LoraLinkState.disconnected)return null;
  final wait=retryIn==null?'':' ${S.t('mesh.retryIn',{'s':retryIn.inSeconds})}';
  return '${S.t('mesh.unreachable')}$wait';
}

/// The bar « le navigateur demande un clic » shows: the browser waits for a
/// click, « Plus tard » not pressed, and, for the bar above the map, no
/// screen of the module open (it has its own).
bool loraBannerShown({required LoraLinkState state,required bool later,required bool inScreen,required int screensOpen})=>
  state==LoraLinkState.waitingClick&&!later&&(inScreen||screensOpen==0);

/// « il y a 3 min », « il y a 2 h », « il y a 4 j ».
String loraAge(DateTime? at,DateTime now){
  if(at==null)return S.t('mesh.never');
  final d=now.difference(at);
  if(d.inMinutes<1)return S.t('mesh.ageNow');
  if(d.inHours<1)return S.t('mesh.ageMin',{'n':'${d.inMinutes}'});
  if(d.inDays<1)return S.t('mesh.ageHour',{'n':'${d.inHours}'});
  return S.t('mesh.ageDay',{'n':'${d.inDays}'});
}

/// « direct », « 2 sauts », « route inconnue ».
String loraHops(int? hops)=>hops==null?S.t('mesh.hopsUnknown'):hops==0?S.t('mesh.hopsDirect'):S.t('mesh.hops',{'n':'$hops'});
