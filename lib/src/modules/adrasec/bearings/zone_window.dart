import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/strings.dart';
import '../../../operations/operations_service.dart';
import '../../../services/sarcade_api.dart';
import 'bearing_models.dart';

/// A probable zone touched on the map (label or circle), card « Plusieurs
/// zones : le découpage ne se fait pas quand un relevé est gardé à la
/// main », point 9 (1 Nov 2026).
class ZoneTap {
  final String search; final BearingZone zone; final List<Bearing> bearings;
  /// Where it was touched, in global coordinates.
  final Offset position;
  const ZoneTap({required this.search,required this.zone,required this.bearings,required this.position});
}

/// Auto / Plusieurs balises / Une seule balise (point 8), in the zone
/// window and in the bearing sheet (point 10).
class ZoneModeSelector extends StatelessWidget {
  final String mode; final ValueChanged<String>? onChanged;
  const ZoneModeSelector({super.key,required this.mode,this.onChanged});
  @override
  Widget build(BuildContext context){
    final current=zoneModes.contains(mode)?mode:'auto';
    // Chips in a Wrap: never cut on a narrow phone.
    return Wrap(key:const ValueKey('zone-mode-choice'),spacing:6,runSpacing:4,children:[
      for(final m in zoneModes)ChoiceChip(key:ValueKey('zone-mode-$m'),label:Text(S.t('zones.mode.$m')),selected:m==current,
        visualDensity:VisualDensity.compact,showCheckmark:false,
        onSelected:onChanged==null?null:(_){if(m!=current)onChanged!(m);}),
    ]);
  }
}

/// Lines of the zone window: frequency, bearings kept and set aside, size.
List<(String,String)> zoneFacts(ZoneTap t){
  final freq={for(final b in t.bearings)if(b.frequencyMhz!=null)b.frequencyMhz!};
  final z=t.zone;
  return [
    (S.t('zones.frequency'),freq.isEmpty?(t.search.isEmpty?'—':t.search):[for(final f in freq)'${f.toStringAsFixed(3).replaceAll('.',',')} MHz'].join(' · ')),
    (S.t('zones.kept'),'${z.bearings}'),
    (S.t('zones.setAside'),'${z.excluded.length}'),
    (S.t('zones.size'),z.centre==null?'—':z.bearings<minKeptBearings?S.t('bearings.zoneApprox'):'±${roundedDistance(z.radiusM)}'),
  ];
}

/// Small window floating on the map next to the zone touched; the mode
/// chosen is saved by [onMode] (true when the server took it), then the
/// window closes.
Future<void> showZoneWindow(BuildContext context,ZoneTap t,{required String mode,required Future<bool> Function(String mode) onMode}){
  return showGeneralDialog<void>(context:context,barrierDismissible:true,barrierLabel:S.t('common.close'),
    barrierColor:Colors.transparent,transitionDuration:const Duration(milliseconds:120),
    pageBuilder:(_,_,_)=>LayoutBuilder(builder:(c,box){
      final w=math.min(300.0,box.maxWidth-16);
      final left=(t.position.dx+12).clamp(8.0,math.max(8.0,box.maxWidth-w-8)).toDouble();
      final top=(t.position.dy-40).clamp(8.0,math.max(8.0,box.maxHeight-260)).toDouble();
      final title=[if(t.zone.index>0)S.t('bearings.zoneN',{'n':t.zone.index})else S.t('bearings.zoneTitle'),if(t.search.isNotEmpty)t.search].join(' · ');
      return Stack(children:[Positioned(left:left,top:top,width:w,child:Material(key:const ValueKey('zone-window'),elevation:8,
        borderRadius:BorderRadius.circular(10),color:Theme.of(c).colorScheme.surface,
        child:Padding(padding:const EdgeInsets.fromLTRB(14,10,8,12),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[
            Expanded(child:Text(title,maxLines:2,overflow:TextOverflow.ellipsis,style:Theme.of(c).textTheme.titleSmall)),
            IconButton(visualDensity:VisualDensity.compact,tooltip:S.t('common.close'),icon:const Icon(Icons.close,size:18),onPressed:()=>Navigator.pop(c)),
          ]),
          for(final (k,v) in zoneFacts(t))Padding(padding:const EdgeInsets.only(right:6,bottom:2),child:Row(children:[
            Expanded(child:Text(k,style:TextStyle(fontSize:13,color:Theme.of(c).colorScheme.onSurfaceVariant))),
            Flexible(child:Text(v,textAlign:TextAlign.end,style:const TextStyle(fontSize:13,fontWeight:FontWeight.w600))),
          ])),
          const SizedBox(height:10),
          ZoneModeSelector(mode:mode,onChanged:(m) async {
            final ok=await onMode(m);
            if(ok&&c.mounted)Navigator.pop(c);
          }),
        ])))),
      ]);
    }));
}

/// Saves the mode of [search] on the server (any operator, point 11), then
/// reads the settings again so that the map draws the new zones at once.
Future<bool> saveZoneMode(BuildContext context,{required SarcadeApi api,required OperationsService ops,required String eventId,
    required String actorId,required String search,required String mode}) async {
  final messenger=ScaffoldMessenger.maybeOf(context);
  try{
    await api.putZoneMode(eventId,actorId,search,mode);
    unawaited(ops.beat());
    return true;
  }catch(_){
    messenger?.showSnackBar(SnackBar(content:Text(S.t('zones.saveFailed'))));
    return false;
  }
}

/// Same choice in the bearing sheet, part « Signal recherché » (point 10).
class ZoneModeBlock extends StatelessWidget {
  final String mode; final ValueChanged<String> onChanged;
  const ZoneModeBlock({super.key,required this.mode,required this.onChanged});
  @override
  Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Column(
    key:const ValueKey('bearing-zone-mode'),crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(S.t('zones.sheetTitle'),style:Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height:6),
      ZoneModeSelector(mode:mode,onChanged:onChanged),
    ]));
}
