/// Outils › ADS-B (module ADRASEC, 1 Nov 2026): the « Aéronefs » layer on
/// or off, its filters (altitude range 0 ft → ∞, aircraft on the ground,
/// callsigns), the aircraft heard, the limits of the source; the sheet of
/// one aircraft (side panel on computers and tablets, bottom sheet on a
/// phone) with « Suivre ».
library;

import 'package:flutter/material.dart';

import '../../../l10n/strings.dart';
import '../../../ui/link_status.dart';
import 'adsb_controller.dart';
import 'adsb_layer.dart';
import 'adsb_models.dart';

/// Slider position of a ceiling: 0..90 = 0..45 000 ft by 500 ft, 91 = ∞.
const adsbSliderTop=AdsbFilters.topFt~/AdsbFilters.stepFt+1;
double adsbSliderOf(int? ft)=>ft==null?adsbSliderTop.toDouble():(ft/AdsbFilters.stepFt).roundToDouble();
int? adsbFeetOf(double v)=>v>=adsbSliderTop?null:(v.round()*AdsbFilters.stepFt);

/// Content of the sheet of one aircraft, read live from [adsb].
class AircraftDetails extends StatelessWidget {
  final AdsbController adsb; final VoidCallback onClose;
  /// Side panel: the title bar with « Fermer » (the bottom sheet has its handle).
  final bool panel;
  const AircraftDetails({super.key,required this.adsb,required this.onClose,this.panel=false});

  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:adsb,builder:(context,_){
    final a=adsb.selected; final t=Theme.of(context);
    if(a==null)return Padding(padding:const EdgeInsets.all(20),child:Text(S.t('adsb.gone')));
    return Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(children:[
        Icon(Icons.flight,color:aircraftColor(a)),const SizedBox(width:10),
        Expanded(child:Text(a.name,style:t.textTheme.titleLarge)),
        if(panel)IconButton(key:const ValueKey('adsb-close'),tooltip:S.t('common.close'),onPressed:onClose,icon:const Icon(Icons.close)),
      ]),
      if(a.urgent)Padding(padding:const EdgeInsets.only(top:6),child:Text(S.t('adsb.urgent',{'what':emergencyText(a.emergency!)}),
        style:const TextStyle(color:adsbUrgentColor,fontWeight:FontWeight.w700))),
      const SizedBox(height:8),
      for(final (k,v) in aircraftLines(a))Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(children:[
        SizedBox(width:150,child:Text(S.t(k),style:t.textTheme.bodySmall)),Expanded(child:Text(v))])),
      if(adsb.track.length>1)Padding(padding:const EdgeInsets.only(top:6),child:Text(S.t('adsb.trackShown'),style:t.textTheme.bodySmall)),
      const SizedBox(height:12),
      Wrap(spacing:8,runSpacing:8,children:[
        FilledButton.tonalIcon(key:const ValueKey('adsb-follow'),onPressed:()=>adsb.setFollow(!adsb.follow),
          icon:Icon(adsb.follow?Icons.gps_off:Icons.gps_fixed),label:Text(S.t(adsb.follow?'adsb.unfollow':'adsb.follow'))),
        OutlinedButton(onPressed:onClose,child:Text(S.t('common.close'))),
      ]),
    ]);
  });
}

/// Bottom sheet of one aircraft (phone).
Future<void> showAircraftSheet(BuildContext context,AdsbController adsb)=>showModalBottomSheet<void>(context:context,showDragHandle:true,
  builder:(c)=>SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(20,0,20,16),
    child:AircraftDetails(adsb:adsb,onClose:()=>Navigator.pop(c))))).whenComplete(()=>adsb.select(null));

/// Side panel of one aircraft (computer, tablet).
class AircraftPanel extends StatelessWidget {
  final AdsbController adsb; final VoidCallback onClose;
  const AircraftPanel({super.key,required this.adsb,required this.onClose});
  @override Widget build(BuildContext context)=>Material(child:SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.all(16),
    child:AircraftDetails(adsb:adsb,onClose:onClose,panel:true))));
}

/// Filters of the layer, in Outils › ADS-B and under the layer of « Fond
/// et affichage ».
class AdsbFiltersTiles extends StatelessWidget {
  final AdsbController adsb;
  const AdsbFiltersTiles({super.key,required this.adsb});
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:adsb,builder:(context,_){
    final f=adsb.filters; final t=Theme.of(context);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.only(top:8),child:Row(children:[
        Expanded(child:Text('${S.t('adsb.altitude')} : ${f.rangeText}',key:const ValueKey('adsb-range'))),
        TextButton(key:const ValueKey('adsb-all'),onPressed:()=>adsb.filters=AdsbFilters.all.copyWith(labels:f.labels),child:Text(S.t('adsb.showAll'))),
      ])),
      RangeSlider(key:const ValueKey('adsb-slider'),min:0,max:adsbSliderTop.toDouble(),divisions:adsbSliderTop,
        values:RangeValues(adsbSliderOf(f.minFt),adsbSliderOf(f.maxFt)),
        labels:RangeLabels('${adsbFeetOf(adsbSliderOf(f.minFt))??0} ft',f.maxFt==null?'∞':'${f.maxFt} ft'),
        onChanged:(r){
          final lo=adsbFeetOf(r.start)??AdsbFilters.topFt, hi=adsbFeetOf(r.end);
          adsb.filters=hi==null?f.copyWith(minFt:lo,clearMax:true):f.copyWith(minFt:lo,maxFt:hi);
        }),
      SwitchListTile(key:const ValueKey('adsb-ground'),contentPadding:EdgeInsets.zero,value:f.ground,
        onChanged:(v)=>adsb.filters=f.copyWith(ground:v),title:Text(S.t('adsb.ground'))),
      SwitchListTile(key:const ValueKey('adsb-labels'),contentPadding:EdgeInsets.zero,value:f.labels,
        onChanged:(v)=>adsb.filters=f.copyWith(labels:v),title:Text(S.t('adsb.labels'))),
      if(adsb.on&&adsb.hiddenCount>0)Text(S.t('adsb.hidden',{'n':'${adsb.hiddenCount}'}),style:t.textTheme.bodySmall),
      Text(S.t('adsb.urgentAlways'),style:t.textTheme.bodySmall),
    ]);
  });
}

class AdsbPage extends StatelessWidget {
  final AdsbController adsb; final void Function(Aircraft) onShow;
  const AdsbPage({super.key,required this.adsb,required this.onShow});

  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:adsb,builder:(context,_){
    final t=Theme.of(context);
    final list=[...adsb.shown]..sort((a,b)=>a.urgent==b.urgent?a.name.compareTo(b.name):(a.urgent?-1:1));
    return Scaffold(appBar:LinkedAppBar(title:Text(S.t('adsb.title'))),body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:760),child:ListView(padding:const EdgeInsets.all(16),children:[
      SwitchListTile(key:const ValueKey('adsb-on'),contentPadding:EdgeInsets.zero,title:Text(S.t('adsb.layer')),subtitle:Text(S.t('adsb.layerHelp')),
        value:adsb.on,onChanged:(v)=>adsb.setOn(v)),
      AdsbFiltersTiles(adsb:adsb),
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
