/// Low battery of the LoRa boxes on screen (lot 25, lora_battery.dart): the
/// bar above the map, the pill, the thresholds of Outils › MeshCore.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import 'lora_battery.dart';

/// Orange of the warning, red of the alert.
const loraBatteryOrange=Color(0xFFE65100), loraBatteryRed=Color(0xFFC62828);

/// Bar above the map: the worst box first, one line per low box.
class LoraBatteryBanner extends StatelessWidget {
  final LoraBatteryMonitor? monitor;
  const LoraBatteryBanner({super.key,this.monitor});
  @override Widget build(BuildContext context){
    final m=monitor??LoraBatteryMonitor.instance;
    return ListenableBuilder(listenable:m,builder:(context,_){
      final low=m.low;
      if(low.isEmpty)return const SizedBox.shrink();
      return Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        for(final s in low)Material(key:ValueKey('lora-battery-box-${s.id}'),color:s.level==LoraBatteryLevel.alert?loraBatteryRed:loraBatteryOrange,
          child:SafeArea(bottom:false,child:Padding(padding:const EdgeInsets.fromLTRB(14,8,14,8),child:Row(children:[
            Icon(s.level==LoraBatteryLevel.alert?Icons.battery_alert:Icons.battery_2_bar,key:ValueKey('lora-battery-${s.level.name}'),color:Colors.white),const SizedBox(width:10),
            Expanded(child:Text(loraBatteryText(s),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w600))),
          ])))),
      ]);
    });
  }
}

/// Tone of the MeshCore pill (point 2): orange with a battery ('battery')
/// while the module linked is low, else [tone] unchanged.
String meshCorePillToneWithBattery(String tone,String? deviceId,{LoraBatteryMonitor? monitor}){
  final s=deviceId==null?null:(monitor??LoraBatteryMonitor.instance).stateOf(deviceId);
  return tone=='ok'&&s!=null&&s.level!=LoraBatteryLevel.ok?'battery':tone;
}

/// « Afficher le pourcentage de batterie » next to « Alerte de batterie »
/// (card « Diagnostic : modules LoRa… », 10 Nov 2026, choice 10): kept on
/// this device, on by default; the low battery alerts stay on when off.
class LoraBatteryShownTile extends StatelessWidget {
  final LoraBatteryMonitor? monitor;
  const LoraBatteryShownTile({super.key,this.monitor});
  @override Widget build(BuildContext context){
    final m=monitor??LoraBatteryMonitor.instance;
    return ListenableBuilder(listenable:m,builder:(context,_)=>SwitchListTile(key:const ValueKey('lora-battery-shown'),dense:true,
      contentPadding:const EdgeInsets.symmetric(horizontal:4),
      secondary:const Icon(Icons.battery_std_outlined),
      title:Text(S.t('lora.battery.show')),subtitle:Text(S.t('lora.battery.showHelp')),
      value:m.percentShown,onChanged:(v)=>unawaited(m.setPercentShown(v))));
  }
}

/// « Alerte de batterie » in Outils › MeshCore (point 4).
class LoraBatteryThresholdsTile extends StatelessWidget {
  final LoraBatteryMonitor? monitor;
  const LoraBatteryThresholdsTile({super.key,this.monitor});
  @override Widget build(BuildContext context){
    final m=monitor??LoraBatteryMonitor.instance;
    return ListenableBuilder(listenable:m,builder:(context,_){
      final t=m.thresholds;
      return ListTile(key:const ValueKey('lora-battery-thresholds'),contentPadding:const EdgeInsets.symmetric(horizontal:4),
        leading:const Icon(Icons.battery_alert_outlined),
        title:Text(S.t('lora.battery.settings')),
        subtitle:Text(S.t('lora.battery.settingsValue',{'w':t.warn,'a':t.alert})),
        trailing:const Icon(Icons.chevron_right),
        onTap:()=>unawaited(_edit(context,m)));
    });
  }

  Future<void> _edit(BuildContext context,LoraBatteryMonitor m) async {
    final t=m.thresholds;
    var warn=t.warn, alert=t.alert;
    const choices=[5,10,15,20,25,30,40,50];
    List<DropdownMenuItem<int>> items(int current)=>[for(final v in {...choices,current}.toList()..sort())DropdownMenuItem(value:v,child:Text('$v %'))];
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(
      title:Text(S.t('lora.battery.settings')),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        DropdownButtonFormField<int>(key:const ValueKey('lora-battery-warn'),initialValue:warn,items:items(warn),
          decoration:InputDecoration(labelText:S.t('lora.battery.warn')),onChanged:(v)=>set(()=>warn=v??warn)),
        const SizedBox(height:12),
        DropdownButtonFormField<int>(key:const ValueKey('lora-battery-alert'),initialValue:alert,items:items(alert),
          decoration:InputDecoration(labelText:S.t('lora.battery.alert')),onChanged:(v)=>set(()=>alert=v??alert)),
        if(alert>=warn)Padding(padding:const EdgeInsets.only(top:8),child:Text(S.t('lora.battery.order'),style:TextStyle(color:Theme.of(c).colorScheme.error))),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:alert<warn?()=>Navigator.pop(c,true):null,child:Text(S.t('common.save'))),
      ])));
    if(ok==true)await m.setThresholds(warn:warn,alert:alert);
  }
}
