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
/// Card « Diagnostic : modules LoRa (MeshCore, Meshtastic) injoignables,
/// lien vers Outils et reconnexion économe » (validated on 10 Nov 2026,
/// choices 2, 4 and 5): [outOfReach] after 5 minutes of failures (grey, a
/// try every 5 minutes), [bluetoothOff] while the Bluetooth of the phone is
/// off (grey, no try), [failed] (red) only for a real fault: the module
/// joined but not answering, or a connection asked by hand that fails.
enum LoraLinkState { none, connecting, connected, reconnecting, failed, waitingClick, disconnected, unavailable, outOfReach, bluetoothOff }

/// Colour family of the pill: 'off' (no module, disconnected on purpose,
/// out of reach, Bluetooth off: grey), 'ok', 'wait', 'bad'.
String loraPillTone(LoraLinkState s)=>switch(s){
  LoraLinkState.none||LoraLinkState.disconnected||LoraLinkState.outOfReach||LoraLinkState.bluetoothOff=>'off', LoraLinkState.connected=>'ok',
  LoraLinkState.connecting||LoraLinkState.reconnecting||LoraLinkState.waitingClick=>'wait', LoraLinkState.failed||LoraLinkState.unavailable=>'bad'};

/// Delay before the next attempt to join the module again: 5 s, 15 s,
/// 30 s, then every minute (until [loraOutOfReachAfter]).
Duration loraRetryDelay(int attempt)=>Duration(seconds:const [5,15,30,60][attempt.clamp(0,3)]);

/// Card « Diagnostic : modules LoRa… » (10 Nov 2026, choice 2): after 5
/// minutes of failures the module is « hors de portée » (grey, not counted
/// in « À vérifier »), and joined again every 5 minutes only (battery of
/// the phone and of the box).
const loraOutOfReachAfter=Duration(minutes:5), loraOutOfReachEvery=Duration(minutes:5);

/// State and delay after a failed attempt (pure, tested). [failing]: time
/// since the first failure of the series; [manual]: the attempt was asked
/// by hand (« Se connecter », choice of the module); [joined]: the module
/// answered the Bluetooth connection but not SARCADE (choice 5: red).
({LoraLinkState state,Duration wait}) loraAfterFailure({required int attempt,required Duration failing,bool manual=false,bool joined=false}){
  final late=failing>=loraOutOfReachAfter;
  final wait=late?loraOutOfReachEvery:loraRetryDelay(attempt);
  if(manual||joined)return (state:LoraLinkState.failed,wait:wait);
  return (state:late?LoraLinkState.outOfReach:LoraLinkState.reconnecting,wait:wait);
}

/// State shown while an attempt runs: a module out of reach stays grey
/// during its try every 5 minutes (no orange flash every 5 minutes).
LoraLinkState loraTryingState({required LoraLinkState before,required int attempt})=>
  before==LoraLinkState.outOfReach?LoraLinkState.outOfReach:attempt==0?LoraLinkState.connecting:LoraLinkState.reconnecting;

/// Text of the state (« connecté », « reconnexion… »).
String loraStateText(LoraLinkState s)=>S.t('mesh.state.${s.name}');

/// Text shown when the module cannot be reached; the technical error stays
/// in the journal only.
String? loraProblem({required LoraLinkState state,required bool trying,String? error,Duration? retryIn}){
  // Card « Diagnostic : modules LoRa… » (10 Nov 2026): Bluetooth off and
  // out of reach said as such (choices 2 and 4).
  if(state==LoraLinkState.bluetoothOff)return S.t('mesh.bluetoothOff');
  if(state==LoraLinkState.outOfReach&&!trying)return '${S.t('mesh.unreachable')} ${S.t('mesh.retryEveryMin',{'n':loraOutOfReachEvery.inMinutes})}';
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
