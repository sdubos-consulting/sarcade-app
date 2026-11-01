/// Outils › ADS-B (module ADRASEC, step 1, 1 Nov 2026): the « Aéronefs »
/// layer on or off, the aircraft heard, the limits of the source.
library;

import 'package:flutter/material.dart';

import '../../../l10n/strings.dart';
import '../../../ui/link_status.dart';
import 'adsb_controller.dart';
import 'adsb_layer.dart';
import 'adsb_models.dart';

/// Sheet of one aircraft (touch on its icon).
Future<void> showAircraftSheet(BuildContext context,Aircraft a)=>showModalBottomSheet<void>(context:context,showDragHandle:true,
  builder:(c)=>SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(20,0,20,16),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[
      Icon(Icons.flight,color:aircraftColor(a)),const SizedBox(width:10),
      Expanded(child:Text(a.name,style:Theme.of(c).textTheme.titleLarge)),
    ]),
    if(a.urgent)Padding(padding:const EdgeInsets.only(top:6),child:Text(S.t('adsb.urgent',{'what':emergencyText(a.emergency!)}),
      style:TextStyle(color:adsbUrgentColor,fontWeight:FontWeight.w700))),
    const SizedBox(height:8),
    for(final (k,v) in aircraftLines(a))Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(children:[
      SizedBox(width:150,child:Text(S.t(k),style:Theme.of(c).textTheme.bodySmall)),Expanded(child:Text(v))])),
  ]))));

class AdsbPage extends StatelessWidget {
  final AdsbController adsb; final void Function(Aircraft) onShow;
  const AdsbPage({super.key,required this.adsb,required this.onShow});

  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:adsb,builder:(context,_){
    final t=Theme.of(context);
    final list=[...adsb.aircraft]..sort((a,b)=>a.urgent==b.urgent?a.name.compareTo(b.name):(a.urgent?-1:1));
    return Scaffold(appBar:LinkedAppBar(title:Text(S.t('adsb.title'))),body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:760),child:ListView(padding:const EdgeInsets.all(16),children:[
      SwitchListTile(key:const ValueKey('adsb-on'),contentPadding:EdgeInsets.zero,title:Text(S.t('adsb.layer')),subtitle:Text(S.t('adsb.layerHelp')),
        value:adsb.on,onChanged:(v)=>adsb.setOn(v)),
      if(adsb.on&&adsb.serverEnabled==false)Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Text(S.t('adsb.serverOff'),style:TextStyle(color:t.colorScheme.error))),
      if(adsb.on&&adsb.error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Text('${S.t('adsb.failed')} (${adsb.error})',style:TextStyle(color:t.colorScheme.error))),
      if(adsb.on)Padding(padding:const EdgeInsets.fromLTRB(0,12,0,6),child:Text(S.t('adsb.count',{'n':'${list.length}'}),style:t.textTheme.titleSmall)),
      for(final a in list)ListTile(contentPadding:EdgeInsets.zero,
        leading:Icon(Icons.flight,color:aircraftColor(a)),
        title:Text(aircraftLabel(a)),
        subtitle:a.urgent?Text(emergencyText(a.emergency!),style:const TextStyle(color:adsbUrgentColor)):(a.country==null?null:Text(a.country!)),
        onTap:()=>onShow(a)),
      const SizedBox(height:16),
      Text(S.t('adsb.source'),style:t.textTheme.bodySmall),
      const SizedBox(height:6),
      Text(S.t('adsb.limits'),style:t.textTheme.bodySmall),
    ]))));
  });
}
