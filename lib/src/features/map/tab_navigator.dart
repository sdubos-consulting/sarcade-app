/// Phone: a tab of the bottom bar with its own stack of screens (card « Menu
/// du bas toujours visible (outils et Paramètres compris) », validated on
/// 8 Nov 2026). A tool or a page of Paramètres opens inside the tab, above
/// its first screen: the bottom bar stays visible under it, Back (arrow,
/// Android Back, iOS swipe) comes back to the first screen, and switching
/// tabs keeps what was open.
library;

import 'package:flutter/material.dart';

/// The stack of one tab; [root] is its first screen, rebuilt with the tab.
class TabNavigator extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget root;
  const TabNavigator({super.key, required this.navigatorKey, required this.root});

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    // Declarative first screen, so that it follows the rebuilds of the tab;
    // the screens opened above it are pushed (TabStack.open).
    pages: [MaterialPage<void>(key: const ValueKey('tab-root'), child: root)],
    onDidRemovePage: (_) {},
  );
}

/// Opening, closing and Back for the stack of a tab.
extension TabStack on GlobalKey<NavigatorState> {
  /// Opens [build] above the first screen (what was above it is closed:
  /// one tool at a time). The tab may not be built yet: then at the next frame.
  void open(Widget Function() build) {
    void push() {
      final nav = currentState;
      if (nav == null) return;
      nav.popUntil((r) => r.isFirst);
      nav.push(MaterialPageRoute<void>(builder: (_) => build()));
    }
    if (currentState != null) {
      push();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => push());
    }
  }

  /// Something is open above the first screen.
  bool get hasOpen => currentState?.canPop() ?? false;

  /// Back to the first screen; false when it was already shown.
  bool backToFirst() {
    final nav = currentState;
    if (nav == null || !nav.canPop()) return false;
    nav.popUntil((r) => r.isFirst);
    return true;
  }

  /// Android Back as the ← of the screen (card « Navigation : la flèche
  /// retour remonte d'un seul cran », 11 Nov 2026): the screen on top, or
  /// the first screen, may go back inside itself first (PopScope: a sub-page,
  /// a folder); false when nothing was left to close in the tab.
  Future<bool> maybeBack() async => await currentState?.maybePop() ?? false;

  /// Closes the screen on top; false when only the first one is left.
  bool back() {
    final nav = currentState;
    if (nav == null || !nav.canPop()) return false;
    nav.pop();
    return true;
  }
}
