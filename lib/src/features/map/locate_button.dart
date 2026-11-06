import 'dart:async';

import 'package:flutter/material.dart';

import 'locate_cycle.dart';

/// The single position button with its short label shown 2 s at each
/// change of mode (« Suivi », « Boussole », « Tous les opérateurs »).
class LocateButton extends StatefulWidget {
  final LocateMode mode; final Widget Function(String tooltip,Widget icon,bool active) fab;
  /// Rotation of the map in degrees when north is not up (card « petite
  /// boussole N », lot 29): the icon becomes « N » with its needle.
  final double? north; final String northTooltip;
  const LocateButton({super.key,required this.mode,required this.fab,this.north,this.northTooltip='N'});
  @override State<LocateButton> createState()=>_LocateButtonState();
}

class _LocateButtonState extends State<LocateButton> {
  String? _label; Timer? _timer;
  @override void didUpdateWidget(LocateButton old){
    super.didUpdateWidget(old);
    if(old.mode==widget.mode)return;
    _timer?.cancel();
    _label=locateLabel(widget.mode);
    if(_label!=null)_timer=Timer(const Duration(seconds:2),(){if(mounted)setState(()=>_label=null);});
  }
  @override void dispose(){_timer?.cancel();super.dispose();}
  @override Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme; final m=widget.mode;
    final active=m==LocateMode.follow||m==LocateMode.compass;
    return Row(mainAxisSize:MainAxisSize.min,children:[
      if(_label!=null)Container(margin:const EdgeInsets.only(right:8),padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
        decoration:BoxDecoration(color:s.inverseSurface,borderRadius:BorderRadius.circular(12)),
        child:Text(_label!,style:TextStyle(fontSize:13,color:s.onInverseSurface))),
      if(widget.north!=null)widget.fab(widget.northTooltip,AnimatedSwitcher(duration:const Duration(milliseconds:200),child:NorthNeedle(key:const ValueKey('north'),rotation:widget.north!)),false)
      else widget.fab(locateTooltip(m),AnimatedSwitcher(duration:const Duration(milliseconds:200),child:Icon(locateIcon(m),key:ValueKey(m))),active),
    ]);
  }
}

/// North is « up » within 2° (card « petite boussole N »).
bool northUp(double rotation){final r=rotation%360;return r<=2||r>=358;}

/// Needle of the « N » compass: points to the north of the turned map.
class NorthNeedle extends StatelessWidget {
  final double rotation;
  const NorthNeedle({super.key,required this.rotation});
  @override Widget build(BuildContext context){
    final fg=IconTheme.of(context).color;
    return Transform.rotate(angle:-rotation*3.141592653589793/180,child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text('N',style:TextStyle(fontSize:11,height:1,fontWeight:FontWeight.w800,color:fg)),
      const Icon(Icons.navigation,size:16,color:Color(0xFFD93025)),
    ]));
  }
}
