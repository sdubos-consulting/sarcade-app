/// Estimated time of arrival of a move order (card « Android Auto : heure
/// d'arrivée estimée envoyée au PCO », lot 24, 3 Nov 2026, choice 3): sent
/// by the car of the operator (PUT …/move-orders/{id}/eta), shown to the PCO
/// in the list of the orders (« arrivée estimée 8 h 15 ») and on the map,
/// next to the operator (or the flag when his position is unknown). The
/// server clears it at « arrivé », « refusé » and « annulé ».
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../l10n/strings.dart';
import '../map/drawing/geometry.dart' show formatDistance;
import 'move_orders.dart';

extension MoveOrderEta on MoveOrder {
  /// Estimated arrival, only while the order is accepted.
  DateTime? get eta=>status=='accepted'?DateTime.tryParse('${json['eta']??''}'):null;
  DateTime? get etaUpdatedAt=>DateTime.tryParse('${json['eta_updated_at']??''}');
  String get etaBy=>'${json['eta_by']??''}';
  /// Distance still to drive, metres, when the car sent it.
  double? get etaRemainingM=>(json['eta_remaining_m'] as num?)?.toDouble();
}

/// « 8 h 15 » in French, « 8:15 » in English (local time).
String etaClock(DateTime t){
  final l=t.toLocal(); final m=l.minute.toString().padLeft(2,'0');
  return S.lang=='fr'?'${l.hour} h $m':'${l.hour}:$m';
}

/// « arrivée estimée 8 h 15 · encore 3,20 km », null without estimate.
String? moveOrderEtaText(MoveOrder o){
  final t=o.eta; if(t==null)return null;
  final d=o.etaRemainingM;
  return [S.t('orders.eta.at',{'time':etaClock(t)}),if(d!=null)S.t('orders.eta.remaining',{'d':formatDistance(d)})].join(' · ');
}

/// Subtitle of an order in the list: its state, then the estimate.
String moveOrderSubtitle(MoveOrder o)=>[S.t(o.finished?'orders.status.finished':'order.status.${o.status}'),?moveOrderEtaText(o)].join(' · ');

/// Labels « Arrivée 8 h 15 » under the operator going to an order, or
/// under the flag when his position is unknown.
List<Widget> buildEtaLayers(List<MoveOrder> orders,LatLng? Function(String deviceId) positionOf,void Function(MoveOrder) onTap){
  final markers=<Marker>[];
  for(final o in orders){
    final t=o.eta; if(t==null)continue;
    final at=positionOf(o.targetId)??o.destination;
    final d=o.etaRemainingM;
    final text=[S.t('orders.eta.label',{'time':etaClock(t)}),if(d!=null)formatDistance(d)].join(' · ');
    markers.add(Marker(point:at,width:170,height:26,alignment:Alignment.bottomCenter,child:GestureDetector(onTap:()=>onTap(o),
      child:Align(alignment:Alignment.topCenter,child:Container(key:ValueKey('order-eta-${o.id}'),
        padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
        decoration:BoxDecoration(color:Colors.white.withValues(alpha:0.92),borderRadius:BorderRadius.circular(6),border:Border.all(color:moveOrderColor(o.status))),
        child:Row(mainAxisSize:MainAxisSize.min,children:[
          Icon(Icons.schedule,size:12,color:moveOrderColor(o.status)),const SizedBox(width:3),
          Flexible(child:Text(text,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w700,color:Colors.black87))),
        ]))))));
  }
  return markers.isEmpty?const []:[MarkerLayer(markers:markers)];
}
