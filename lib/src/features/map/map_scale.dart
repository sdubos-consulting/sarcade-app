/// Scale of the map like Google Maps (card « échelle discrète et
/// temporaire », lot 29.2): a thin line with a small tick at each end, the
/// value above on the right, metres only; no box. It shows when the zoom
/// changes and fades 2 s later; moving the map does not bring it back.
/// Always shown when [always] (TV: nobody zooms).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/map_view.dart';

/// Time the scale stays after the last change of zoom.
const scaleShowFor=Duration(seconds:2);
/// Fade in and out.
const scaleFade=Duration(milliseconds:300);

/// A change of zoom large enough to show the scale (not a rounding).
bool zoomChanged(double? before,double now)=>before!=null&&(now-before).abs()>0.001;

class FadingScale extends StatefulWidget {
  final double zoom, latitude; final bool always;
  const FadingScale({super.key,required this.zoom,required this.latitude,this.always=false});
  @override State<FadingScale> createState()=>_FadingScaleState();
}

class _FadingScaleState extends State<FadingScale> {
  bool _shown=false; Timer? _timer;
  @override void didUpdateWidget(FadingScale old){
    super.didUpdateWidget(old);
    if(!zoomChanged(old.zoom,widget.zoom))return;
    _timer?.cancel();
    _shown=true;
    _timer=Timer(scaleShowFor,(){if(mounted)setState(()=>_shown=false);});
  }
  @override void dispose(){_timer?.cancel();super.dispose();}
  @override Widget build(BuildContext context){
    final b=scaleBar(widget.zoom,widget.latitude,maxPx:90);
    final dark=Theme.of(context).brightness==Brightness.dark;
    final ink=dark?Colors.white:const Color(0xFF202124);
    final halo=dark?const Color(0x99000000):const Color(0xCCFFFFFF);
    final side=BorderSide(color:ink,width:1.5);
    return IgnorePointer(child:AnimatedOpacity(opacity:widget.always||_shown?1:0,duration:scaleFade,
      child:Column(crossAxisAlignment:CrossAxisAlignment.end,mainAxisSize:MainAxisSize.min,children:[
        Text(b.label,style:TextStyle(fontSize:11,fontWeight:FontWeight.w600,color:ink,shadows:[Shadow(color:halo,blurRadius:3)])),
        const SizedBox(height:1),
        Container(width:b.px,height:5,decoration:BoxDecoration(border:Border(left:side,right:side,bottom:side))),
      ])));
  }
}
