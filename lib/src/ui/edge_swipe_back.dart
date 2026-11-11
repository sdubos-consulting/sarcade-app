/// Swipe from the left edge to go back one step, as on iOS, for a screen
/// drawn over the map rather than pushed as a page (card « Outils : fermer
/// chaque écran avec la flèche retour en haut à gauche », 11 Nov 2026,
/// choice 2). Pages pushed with a [MaterialPageRoute] already have it.
library;

import 'package:flutter/material.dart';

/// Width of the edge that starts the gesture, as the system one.
const edgeSwipeWidth = 20.0;

class EdgeSwipeBack extends StatefulWidget {
  final Widget child;
  final VoidCallback onBack;
  const EdgeSwipeBack({super.key, required this.child, required this.onBack});
  @override
  State<EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<EdgeSwipeBack> {
  double _dx = 0;
  @override
  Widget build(BuildContext context) => Stack(children: [
    widget.child,
    Positioned(left: 0, top: 0, bottom: 0, width: edgeSwipeWidth, child: GestureDetector(
      key: const ValueKey('edge-swipe-back'),
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _dx = 0,
      onHorizontalDragUpdate: (d) => _dx += d.delta.dx,
      onHorizontalDragEnd: (d) {
        final w = MediaQuery.sizeOf(context).width;
        if (_dx > w / 3 || (d.primaryVelocity ?? 0) > 400) widget.onBack();
        _dx = 0;
      })),
  ]);
}
