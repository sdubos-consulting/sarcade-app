/// Sheets from the bottom of the app (card « Carte : fermer le panneau
/// « Carte » en le glissant vers le bas, et vignette du fond deux fois plus
/// large », validated on 10 Nov 2026, choices 1 and 5): every sheet has the
/// small handle at the top and closes by a swipe down, like the windows of
/// the iPhone — from the handle, the title or anywhere on the content; a
/// list that scrolls first goes back to its top, then the same swipe pulls
/// the sheet down. Released below half its height, or flung down, the sheet
/// closes; otherwise it goes back up.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// [showModalBottomSheet] with the handle and the swipe down that closes,
/// the same for every sheet of the app. Same parameters.
Future<T?> showAppSheet<T>({required BuildContext context,required WidgetBuilder builder,
    bool isScrollControlled=false,bool useSafeArea=false,bool showDragHandle=true,
    BoxConstraints? constraints,Clip? clipBehavior,ShapeBorder? shape}) async {
  // The sheet's own animation, moved by the finger when a list is at its top.
  final sheet=BottomSheet.createAnimationController(Navigator.of(context));
  try{
    return await showModalBottomSheet<T>(context:context,transitionAnimationController:sheet,
      isScrollControlled:isScrollControlled,useSafeArea:useSafeArea,showDragHandle:showDragHandle,
      constraints:constraints,clipBehavior:clipBehavior,shape:shape,
      builder:(c)=>SheetPullToClose(sheet:sheet,child:Builder(builder:builder)));
  }finally{
    _disposeWhenGone(sheet);
  }
}

/// The route does not dispose an animation it was given: done here once
/// the sheet has gone down.
void _disposeWhenGone(AnimationController sheet){
  if(sheet.isDismissed){Future.microtask(sheet.dispose);return;}
  void gone(AnimationStatus s){
    if(s!=AnimationStatus.dismissed)return;
    sheet.removeStatusListener(gone);
    Future.microtask(sheet.dispose);
  }
  sheet.addStatusListener(gone);
}

/// Released below this share of its height, the sheet closes (as the
/// handle of Flutter).
const sheetCloseShare=0.5;
/// Flung down faster than this (pixels per second), the sheet closes.
const sheetCloseVelocity=700.0;

/// Content of a sheet: a swipe down on a list already at its top pulls
/// [sheet] down instead of bouncing the list.
class SheetPullToClose extends StatefulWidget {
  final AnimationController sheet; final Widget child;
  const SheetPullToClose({super.key,required this.sheet,required this.child});
  @override State<SheetPullToClose> createState()=>_SheetPullToCloseState();
}

class _SheetPullToCloseState extends State<SheetPullToClose> {
  /// True while the finger holds the sheet below its full height.
  bool pulling=false;

  double get _height=>math.max(1.0,(context.findRenderObject() as RenderBox?)?.size.height??1.0);

  /// Moves the sheet by [delta] (positive: down) and returns the part the
  /// sheet did not take (the sheet already fully up or down).
  double pull(double delta){
    final sheet=widget.sheet;
    if(!mounted||sheet.isAnimating&&!pulling&&sheet.status==AnimationStatus.forward)return delta;
    final before=sheet.value;
    final after=(before-delta/_height).clamp(0.0,1.0);
    sheet.value=after;
    pulling=after<1.0;
    return delta-(before-after)*_height;
  }

  bool _onEnd(ScrollEndNotification n){
    if(!pulling)return false;
    pulling=false;
    final v=n.dragDetails?.velocity.pixelsPerSecond.dy??0;
    if(v>sheetCloseVelocity||widget.sheet.value<sheetCloseShare){
      Navigator.maybePop(context).then((popped){if(!popped&&mounted)widget.sheet.forward();});
    }else{
      widget.sheet.forward();
    }
    return false;
  }

  @override Widget build(BuildContext context){
    final behavior=ScrollConfiguration.of(context);
    return NotificationListener<ScrollEndNotification>(onNotification:_onEnd,
      child:ScrollConfiguration(behavior:behavior.copyWith(physics:_PullPhysics(this,parent:behavior.getScrollPhysics(context))),
        child:widget.child));
  }
}

/// Physics of the lists of a sheet: at the top, the swipe down goes to the
/// sheet; while the sheet is pulled, the swipe up first brings it back.
class _PullPhysics extends ScrollPhysics {
  final _SheetPullToCloseState pull;
  const _PullPhysics(this.pull,{super.parent});
  @override _PullPhysics applyTo(ScrollPhysics? ancestor)=>_PullPhysics(pull,parent:buildParent(ancestor));

  @override double applyPhysicsToUserOffset(ScrollMetrics position,double offset){
    if(position.axisDirection==AxisDirection.down){
      if(offset>0&&position.pixels<=position.minScrollExtent){pull.pull(offset);return 0;}
      if(offset<0&&pull.pulling)return super.applyPhysicsToUserOffset(position,pull.pull(offset));
    }
    return super.applyPhysicsToUserOffset(position,offset);
  }

  @override Simulation? createBallisticSimulation(ScrollMetrics position,double velocity)=>
    pull.pulling&&position.axisDirection==AxisDirection.down?null:super.createBallisticSimulation(position,velocity);
}
