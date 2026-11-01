/// Outils › ADS-B (module ADRASEC, 1 Nov 2026): the « Aéronefs » layer on
/// or off, its filters, the aircraft heard, the limits of the source; the
/// sheet of one aircraft.
///
/// Lot 17 (cards validated 1 Nov 2026, 11 h 29 to 12 h 04):
/// - one slider over 0 → ∞ whose two handles are the thresholds between
///   Bas, Moyen and Haut, painted in the three colours, and one switch per
///   band (replaces the altitude range of #181); legend of the colours and
///   of the icons;
/// - the aircraft heard in folded sections, one per band shown, emergencies
///   on top out of the sections, « Suivis » first;
/// - the sheet floats over the map (top left on a computer, at the bottom
///   on a phone, a third of the screen at most): the map stays visible.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/strings.dart';
import '../../../ui/link_status.dart';
import '../../../ui/theme.dart';
import 'adsb_controller.dart';
import 'adsb_icons.dart';
import 'adsb_layer.dart';
import 'adsb_models.dart';

/// Slider positions: 0..90 = 0..45 000 ft by 500 ft, 91 = ∞ (end of the
/// scale; a threshold stops at 45 000 ft).
const adsbSliderTop=AdsbFilters.topFt~/AdsbFilters.stepFt+1;
const _maskedBand=Color(0xFFBDBDBD);

/// Colour of a band on the slider and the switches; grey when masked.
Color adsbBandColor(AdsbBand b,{bool shown=true})=>shown?Color(adsbBandColorValue(b)):_maskedBand;

/// « Bas », « Moyen », « Haut », « Au sol ou altitude inconnue ».
String adsbBandName(AdsbBand b)=>S.t('adsb.band.${b.name}');

/// Track of the bands slider: three coloured segments (0 → threshold 1,
/// threshold 1 → threshold 2, threshold 2 → ∞), a masked band in grey, and
/// the value of each threshold above its handle.
class AdsbBandsTrackShape extends RangeSliderTrackShape with BaseRangeSliderTrackShape {
  final List<Color> colors; final List<String> labels; final Color labelColor;
  const AdsbBandsTrackShape({required this.colors,required this.labels,required this.labelColor});

  @override void paint(PaintingContext context,Offset offset,{required RenderBox parentBox,required SliderThemeData sliderTheme,
      required Animation<double> enableAnimation,required Offset startThumbCenter,required Offset endThumbCenter,
      bool isEnabled=false,bool isDiscrete=false,required TextDirection textDirection}){
    final rect=getPreferredRect(parentBox:parentBox,offset:offset,sliderTheme:sliderTheme,isEnabled:isEnabled,isDiscrete:isDiscrete);
    final canvas=context.canvas, h=rect.height, r=Radius.circular(h/2);
    final xs=[rect.left,startThumbCenter.dx,endThumbCenter.dx,rect.right];
    for(var i=0;i<3;i++){
      if(xs[i+1]<=xs[i])continue;
      final seg=Rect.fromLTRB(xs[i],rect.top,xs[i+1],rect.bottom);
      canvas.drawRRect(RRect.fromRectAndCorners(seg,topLeft:i==0?r:Radius.zero,bottomLeft:i==0?r:Radius.zero,
        topRight:i==2?r:Radius.zero,bottomRight:i==2?r:Radius.zero),Paint()..color=colors[i]);
    }
    final centres=[startThumbCenter,endThumbCenter];
    for(var i=0;i<2&&i<labels.length;i++){
      final tp=TextPainter(text:TextSpan(text:labels[i],style:TextStyle(fontSize:11,fontWeight:FontWeight.w600,color:labelColor)),
        textDirection:textDirection)..layout();
      // Two close handles: the labels move apart.
      final shift=(endThumbCenter.dx-startThumbCenter.dx)<tp.width+8?(i==0?-tp.width/2-4:tp.width/2+4):0.0;
      tp.paint(canvas,Offset(centres[i].dx-tp.width/2+shift,rect.top-tp.height-12));
      tp.dispose();
    }
  }
}

/// Filters of the layer, in Outils › ADS-B and under the layer of « Fond
/// et affichage »: the bands slider, the switches Bas / Moyen / Haut, the
/// aircraft on the ground, the callsigns, « Ne plus suivre aucun avion ».
class AdsbFiltersTiles extends StatelessWidget {
  final AdsbController adsb;
  const AdsbFiltersTiles({super.key,required this.adsb});
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:adsb,builder:(context,_){
    final f=adsb.filters; final t=Theme.of(context);
    const top=AdsbFilters.topFt~/AdsbFilters.stepFt;
    Widget band(AdsbBand b)=>SwitchListTile(key:ValueKey('adsb-band-${b.name}'),contentPadding:EdgeInsets.zero,dense:true,
      secondary:_Dot(adsbBandColor(b,shown:f.shown(b))),value:f.shown(b),onChanged:(v)=>adsb.filters=f.withBand(b,v),
      title:Text(adsbBandName(b)),subtitle:Text(f.rangeOf(b)));
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.only(top:8),child:Row(children:[
        Expanded(child:Text(S.t('adsb.bands'),style:t.textTheme.titleSmall)),
        TextButton(key:const ValueKey('adsb-all'),onPressed:()=>adsb.filters=f.all,child:Text(S.t('adsb.showAll'))),
        TextButton(key:const ValueKey('adsb-defaults'),onPressed:()=>adsb.filters=f.defaults,child:Text(S.t('adsb.defaults'))),
      ])),
      Padding(padding:const EdgeInsets.only(top:18),child:SliderTheme(
        data:SliderTheme.of(context).copyWith(trackHeight:8,rangeTrackShape:AdsbBandsTrackShape(
          colors:[for(final b in [AdsbBand.low,AdsbBand.mid,AdsbBand.high])adsbBandColor(b,shown:f.shown(b))],
          labels:['${_feet(f.lowFt)} ft','${_feet(f.highFt)} ft'],labelColor:t.colorScheme.onSurface)),
        child:RangeSlider(key:const ValueKey('adsb-slider'),min:0,max:adsbSliderTop.toDouble(),divisions:adsbSliderTop,
          values:RangeValues(f.lowFt/AdsbFilters.stepFt,f.highFt/AdsbFilters.stepFt),
          onChanged:(r)=>adsb.filters=f.withThresholds(math.min(r.start.round(),top)*AdsbFilters.stepFt,
            math.min(r.end.round(),top)*AdsbFilters.stepFt)))),
      Padding(padding:const EdgeInsets.symmetric(horizontal:24),child:Row(children:[
        Text('0 ft',style:t.textTheme.bodySmall),const Spacer(),Text('∞',style:t.textTheme.bodySmall)])),
      band(AdsbBand.low),band(AdsbBand.mid),band(AdsbBand.high),
      SwitchListTile(key:const ValueKey('adsb-ground'),contentPadding:EdgeInsets.zero,dense:true,value:f.ground,
        secondary:_Dot(adsbBandColor(AdsbBand.ground,shown:f.ground)),
        onChanged:(v)=>adsb.filters=f.copyWith(ground:v),title:Text(S.t('adsb.ground'))),
      SwitchListTile(key:const ValueKey('adsb-labels'),contentPadding:EdgeInsets.zero,dense:true,value:f.labels,
        onChanged:(v)=>adsb.filters=f.copyWith(labels:v),title:Text(S.t('adsb.labels'))),
      if(adsb.on&&adsb.hiddenCount>0)Text(S.t('adsb.hidden',{'n':'${adsb.hiddenCount}'}),style:t.textTheme.bodySmall),
      Text(S.t('adsb.urgentAlways'),style:t.textTheme.bodySmall),
      if(adsb.followed.isNotEmpty)Align(alignment:Alignment.centerLeft,child:Padding(padding:const EdgeInsets.only(top:6),
        child:OutlinedButton.icon(key:const ValueKey('adsb-unfollow-all'),onPressed:adsb.unfollowAll,
          icon:const Icon(Icons.gps_off,color:adsbFollowColor),label:Text(S.t('adsb.unfollowAll'))))),
    ]);
  });
}

/// Legend of the fixed colours and of the icons (Outils › ADS-B); the bands
/// are told by the slider and the switches.
class AdsbLegend extends StatelessWidget {
  const AdsbLegend({super.key});
  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    Widget item(Widget icon,String text)=>Row(mainAxisSize:MainAxisSize.min,children:[icon,const SizedBox(width:6),Text(text,style:t.textTheme.bodySmall)]);
    return Column(key:const ValueKey('adsb-legend'),crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(S.t('adsb.legend.colors'),style:t.textTheme.titleSmall),
      const SizedBox(height:6),
      Wrap(spacing:14,runSpacing:6,children:[
        item(const _Dot(Color(adsbUrgentValue)),S.t('adsb.legend.urgent')),
        item(const _Ring(adsbFollowColor),S.t('adsb.legend.followed')),
        item(const Opacity(opacity:0.5,child:_Dot(Color(adsbGroundValue))),S.t('adsb.legend.stale')),
      ]),
      const SizedBox(height:12),
      Text(S.t('adsb.legend.icons'),style:t.textTheme.titleSmall),
      const SizedBox(height:6),
      Wrap(spacing:14,runSpacing:6,children:[
        for(final k in AircraftKind.values)item(AircraftIcon(key:ValueKey('adsb-legend-${k.name}'),kind:k,color:t.colorScheme.onSurfaceVariant,size:22),aircraftKindText(k)),
      ]),
    ]);
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);
  @override Widget build(BuildContext context)=>Container(width:14,height:14,decoration:BoxDecoration(color:color,shape:BoxShape.circle));
}

class _Ring extends StatelessWidget {
  final Color color;
  const _Ring(this.color);
  @override Widget build(BuildContext context)=>Container(width:14,height:14,
    decoration:BoxDecoration(color:color.withValues(alpha:0.25),shape:BoxShape.circle,border:Border.all(color:color,width:1.5)));
}

String _feet(int v){
  final s=v.toString(), out=StringBuffer();
  for(var i=0;i<s.length;i++){if(i>0&&(s.length-i)%3==0)out.write(' ');out.write(s[i]);}
  return out.toString();
}

/// One line of the lists: icon of the kind, label, type or country.
Widget _aircraftTile(Aircraft a,AdsbFilters f,void Function(Aircraft) onShow)=>ListTile(key:ValueKey('adsb-row-${a.icao24}'),
  contentPadding:EdgeInsets.zero,dense:true,
  leading:AircraftIcon(kind:aircraftKind(a),color:aircraftColor(a,f),size:26,turnDeg:(a.trackDeg??0).toDouble()),
  title:Text(aircraftLabel(a)),
  subtitle:a.urgent?Text(emergencyText(a.emergency!),style:const TextStyle(color:adsbUrgentColor)):Text(aircraftTypeText(a)),
  onTap:()=>onShow(a));

class AdsbPage extends StatelessWidget {
  final AdsbController adsb; final void Function(Aircraft) onShow;
  const AdsbPage({super.key,required this.adsb,required this.onShow});

  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:adsb,builder:(context,_){
    final t=Theme.of(context), f=adsb.filters;
    final sections=adsbSections(adsb.aircraft,f,followed:adsb.followed);
    final heard=sections.urgent.length+sections.bands.values.fold<int>(0,(n,l)=>n+l.length);
    return Scaffold(appBar:LinkedAppBar(title:Text(S.t('adsb.title'))),body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:760),child:ListView(padding:const EdgeInsets.all(16),children:[
      SwitchListTile(key:const ValueKey('adsb-on'),contentPadding:EdgeInsets.zero,title:Text(S.t('adsb.layer')),subtitle:Text(S.t('adsb.layerHelp')),
        value:adsb.on,onChanged:(v)=>adsb.setOn(v)),
      AdsbFiltersTiles(adsb:adsb),
      if(adsb.on&&adsb.serverEnabled==false)Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Text(S.t('adsb.serverOff'),style:TextStyle(color:t.colorScheme.error))),
      if(adsb.on&&adsb.error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Text('${S.t('adsb.failed')} (${adsb.error})',style:TextStyle(color:t.colorScheme.error))),
      if(adsb.on)...[
        Padding(padding:const EdgeInsets.fromLTRB(0,12,0,6),child:Text(S.t('adsb.count',{'n':'$heard'}),style:t.textTheme.titleSmall)),
        // Emergencies: always on top, out of the sections, never folded.
        for(final a in sections.urgent)_aircraftTile(a,f,onShow),
        // Aircraft followed: open when there are some.
        if(sections.followed.isNotEmpty)ExpansionTile(key:const ValueKey('adsb-section-followed'),initiallyExpanded:true,
          tilePadding:EdgeInsets.zero,leading:const _Ring(adsbFollowColor),
          title:Text('${S.t('adsb.followed')} · ${sections.followed.length}'),
          children:[for(final a in sections.followed)_aircraftTile(a,f,onShow)]),
        // One section per band shown, folded at each opening of the page.
        for(final e in sections.bands.entries)ExpansionTile(key:ValueKey('adsb-section-${e.key.name}'),
          tilePadding:EdgeInsets.zero,leading:_Dot(adsbBandColor(e.key)),
          title:Text([adsbBandName(e.key),if(e.key!=AdsbBand.ground)f.rangeOf(e.key),'${e.value.length}'].join(' · ')),
          children:[for(final a in e.value)_aircraftTile(a,f,onShow)]),
        if(sections.hidden>0)Padding(padding:const EdgeInsets.only(top:6),
          child:Text(S.t('adsb.hidden',{'n':'${sections.hidden}'}),key:const ValueKey('adsb-hidden'),style:t.textTheme.bodySmall)),
      ],
      const SizedBox(height:16),
      const AdsbLegend(),
      const SizedBox(height:16),
      Text(S.t('adsb.source'),style:t.textTheme.bodySmall),
      const SizedBox(height:6),
      Text(S.t('adsb.limits'),style:t.textTheme.bodySmall),
    ]))));
  });
}

/// Sheet of one aircraft, floating over the map (lot 17, 1 Nov 2026,
/// 11 h 34): about 300 px wide at the top left on a computer or a tablet;
/// at the bottom on a phone, a third of the screen at most. « Suivre »
/// adds the aircraft to those followed; closing the sheet keeps them.
class AircraftCard extends StatelessWidget {
  final AdsbController adsb; final VoidCallback onClose; final bool compact;
  const AircraftCard({super.key,required this.adsb,required this.onClose,this.compact=false});

  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:adsb,builder:(context,_){
    final t=Theme.of(context), id=adsb.selectedId;
    if(id==null)return const SizedBox.shrink();
    final a=adsb.selected, f=adsb.filters, h=MediaQuery.sizeOf(context).height;
    final followed=adsb.isFollowed(id);
    return Container(key:const ValueKey('adsb-card'),width:compact?null:300,
      constraints:BoxConstraints(maxHeight:compact?h/3:math.max(200.0,h*0.6)),
      decoration:glass(context,radius:16,border:(a!=null&&a.urgent?adsbUrgentColor:adsbFollowColor).withValues(alpha:0.6)),
      child:SingleChildScrollView(padding:const EdgeInsets.fromLTRB(14,6,6,12),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[
          if(a!=null)...[AircraftIcon(kind:aircraftKind(a),color:aircraftColor(a,f),size:26,turnDeg:(a.trackDeg??0).toDouble()),const SizedBox(width:8)],
          Expanded(child:Text(a?.name??id.toUpperCase(),style:t.textTheme.titleMedium)),
          IconButton(key:const ValueKey('adsb-close'),tooltip:S.t('common.close'),onPressed:onClose,icon:const Icon(Icons.close)),
        ]),
        if(a==null)Text(S.t('adsb.gone'))
        else ...[
          if(a.urgent)Padding(padding:const EdgeInsets.only(bottom:4),child:Text(S.t('adsb.urgent',{'what':emergencyText(a.emergency!)}),
            style:const TextStyle(color:adsbUrgentColor,fontWeight:FontWeight.w700))),
          if(aircraftStale(a,adsb.serverNow))Text(S.t('adsb.stale'),style:t.textTheme.bodySmall?.copyWith(fontWeight:FontWeight.w700)),
          for(final (k,v) in aircraftLines(a,now:adsb.serverNow))Padding(padding:const EdgeInsets.symmetric(vertical:2),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
            SizedBox(width:118,child:Text(S.t(k),style:t.textTheme.bodySmall)),Expanded(child:Text(v,style:t.textTheme.bodyMedium))])),
        ],
        if(followed&&(adsb.routes[id]?.length??0)>1)Padding(padding:const EdgeInsets.only(top:4),child:Text(S.t('adsb.routeShown'),style:t.textTheme.bodySmall)),
        const SizedBox(height:8),
        Wrap(spacing:8,runSpacing:8,children:[
          if(a!=null||followed)FilledButton.tonalIcon(key:const ValueKey('adsb-follow'),
            onPressed:(){if(followed){adsb.unfollow(id);}else{unawaited(adsb.follow(a!));}},
            icon:Icon(followed?Icons.gps_off:Icons.gps_fixed),label:Text(S.t(followed?'adsb.unfollow':'adsb.follow'))),
          OutlinedButton(onPressed:onClose,child:Text(S.t('common.close'))),
        ]),
      ])));
  });
}
