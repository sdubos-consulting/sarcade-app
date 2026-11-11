/// Icon of an operator on the map (card « Traces des opérateurs façon
/// aprs.fi et icônes », 1 Nov 2026): same meanings as the APRS symbols,
/// chosen in Paramètres › Profil; the icon chosen in SARCADE wins over the
/// APRS one for the same person (station linked by its callsign).
library;

import 'package:flutter/material.dart';

/// Ids shared with the server (sarcade.profile.preferences.OPERATOR_ICONS).
const operatorIconIds=['walk','bike','moto','car','4x4','truck','ambulance','fire','boat','helicopter','plane','fixed','relay','pco'];

/// Local preference key of the icon of this device.
const operatorIconKey='operator_icon';

IconData? operatorIcon(String? id)=>switch(id){
  'walk'=>Icons.directions_walk,'bike'=>Icons.pedal_bike,'moto'=>Icons.two_wheeler,'car'=>Icons.directions_car,
  '4x4'=>Icons.directions_car_filled,'truck'=>Icons.local_shipping,'ambulance'=>Icons.emergency,'fire'=>Icons.fire_truck,
  'boat'=>Icons.directions_boat,'helicopter'=>Icons.airplanemode_active,'plane'=>Icons.flight,'fixed'=>Icons.home,
  'relay'=>Icons.cell_tower,'pco'=>Icons.flag,_=>null,
};

/// Callsign without its SSID: « F4XYZ-9 » → « F4XYZ ».
String baseCallsign(String? c)=>(c??'').trim().toUpperCase().split('-').first;

/// Icon chosen in SARCADE by the device of [deviceId], or by the device
/// whose callsign is that of the APRS station [callsign].
String? chosenIcon(Map<String,Map<String,dynamic>> devices,{String? deviceId,String? callsign}){
  final own=deviceId==null?null:devices[deviceId]?['icon'];
  if(own is String&&operatorIcon(own)!=null)return own;
  final base=baseCallsign(callsign);
  if(base.isEmpty)return null;
  for(final d in devices.values){
    final i=d['icon'];
    if(i is String&&operatorIcon(i)!=null&&baseCallsign('${d['callsign']??''}')==base)return i;
  }
  return null;
}
