/// Bar « le navigateur demande un clic pour le reconnecter » (web), card
/// « Web, MeshCore : bandeau affiché en permanence » (lot 25, decided on
/// 2 Nov 2026, 21 h 57):
/// 1. « Plus tard » hides it until the next opening of SARCADE;
/// 2. « Reconnecter » that fails (module off or out of reach): the bar
///    goes, the state becomes « module indisponible »
///    ([MeshCoreLink.reconnectInBrowser]);
/// 3. one bar on the MeshCore screen: the one above the map is hidden while
///    the screen is open;
/// 4. the « MeshCore » pill stays at the top of the map to reconnect later.
library;

import 'package:flutter/foundation.dart';

import 'meshcore_link.dart';

/// « Plus tard » pressed: hidden until SARCADE is opened again (memory
/// only, never saved).
final ValueNotifier<bool> meshCoreBannerLater=ValueNotifier(false);

/// Number of MeshCore screens open (Outils › MeshCore).
final ValueNotifier<int> meshCoreScreensOpen=ValueNotifier(0);

/// The bar shows: the browser waits for a click, « Plus tard » not pressed,
/// and, for the bar above the map, no MeshCore screen open (it has its own).
bool meshCoreBannerShown({required MeshCoreState state,required bool later,required bool inScreen,required int screensOpen})=>
  state==MeshCoreState.waitingClick&&!later&&(inScreen||screensOpen==0);
