/// Paramètres as a list (card « Paramètres : moins d'onglets », option B,
/// validated on 9 Nov 2026, with the header of the account opening « Mon
/// profil » and Diagnostic and À propos as two lines): no tabs any more. At
/// the top the account (initials, name of the device and callsign, state of
/// the connection), then one line per section with its summary; each opens
/// its page with ←. On a computer or a tablet, the list on the left and the
/// page on the right.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../ui/operator_color.dart' show operatorInitials;
import '../map/phone_tab_item.dart' show logoNightBlue;

/// From this width the list stays on the left and the page on the right.
const settingsWideWidth=840.0;

/// Title of a section in the list and on its page (« Cet appareil »).
String settingsRowTitle(String id)=>id=='admin'?S.t('admin.title'):S.t('settings.row.$id');

/// Summary under the title (« Serveur, nom, langue, batterie »).
String settingsRowHelp(String id)=>S.t('settings.rowHelp.$id');

IconData settingsRowIcon(String id)=>switch(id){
  'general'=>Icons.smartphone,'profile'=>Icons.person_outline,'notifications'=>Icons.notifications_none,
  'event'=>Icons.event_outlined,'admin'=>Icons.admin_panel_settings_outlined,'diagnostics'=>Icons.monitor_heart_outlined,
  // Card « Paramètres : menu « Aide » » (10 Nov 2026, choice 1).
  'help'=>Icons.help_outline,
  _=>Icons.info_outline};

/// « PCO-iphone · F4ABC-7 »; the device alone without a callsign.
String settingsAccountTitle(String device,String callsign)=>callsign.trim().isEmpty?device:'$device · ${callsign.trim()}';

/// One section of Paramètres on one line: icon in a pale round, title,
/// summary, a value on the right (orange for something to look at), « › ».
class SettingsListRow extends StatelessWidget {
  final String id; final String? value; final bool warn; final bool selected; final VoidCallback onTap;
  const SettingsListRow({super.key,required this.id,required this.onTap,this.value,this.warn=false,this.selected=false});
  @override Widget build(BuildContext context){
    final t=Theme.of(context); final s=t.colorScheme;
    final day=s.brightness==Brightness.light;
    return Material(color:selected?s.primaryContainer.withValues(alpha:0.5):Colors.transparent,child:InkWell(key:ValueKey('settings-row-$id'),onTap:onTap,
      child:Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:10),child:Row(children:[
        Container(width:40,height:40,decoration:BoxDecoration(shape:BoxShape.circle,color:day?const Color(0xFFDCE3EE):const Color(0xFF1C3A66)),
          child:Icon(settingsRowIcon(id),size:21,color:day?logoNightBlue:Colors.white)),
        const SizedBox(width:16),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(settingsRowTitle(id),style:t.textTheme.bodyLarge),
          Text(settingsRowHelp(id),style:t.textTheme.bodySmall?.copyWith(color:s.onSurfaceVariant)),
        ])),
        if(value!=null)...[const SizedBox(width:8),Text(value!,key:ValueKey('settings-row-$id-value'),
          style:t.textTheme.bodyMedium?.copyWith(color:warn?Colors.orange.shade800:s.onSurfaceVariant))],
        Icon(Icons.chevron_right,color:s.onSurfaceVariant),
      ]))));
  }
}

/// Header of the list: the account; a touch opens « Mon profil ».
class SettingsAccountHeader extends StatelessWidget {
  final String device, callsign, connection; final bool selected; final VoidCallback onTap;
  const SettingsAccountHeader({super.key,required this.device,required this.callsign,required this.connection,required this.onTap,this.selected=false});
  @override Widget build(BuildContext context){
    final t=Theme.of(context); final s=t.colorScheme;
    return Material(color:selected?s.primaryContainer.withValues(alpha:0.5):Colors.transparent,child:InkWell(key:const ValueKey('settings-row-profile'),onTap:onTap,
      child:Padding(padding:const EdgeInsets.fromLTRB(16,8,16,14),child:Row(children:[
        CircleAvatar(radius:28,backgroundColor:logoNightBlue,
          child:Text(operatorInitials(device),style:const TextStyle(color:Colors.white,fontSize:19,fontWeight:FontWeight.w600))),
        const SizedBox(width:16),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(settingsAccountTitle(device,callsign),style:t.textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w600)),
          Text(connection,key:const ValueKey('settings-account-connection'),style:t.textTheme.bodySmall?.copyWith(color:s.onSurfaceVariant)),
        ])),
        Icon(Icons.chevron_right,color:s.onSurfaceVariant),
      ]))));
  }
}
