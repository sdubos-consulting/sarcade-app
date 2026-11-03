/// Status of an operator in one touch (card « Android Auto : statut en un
/// appui », lot 24, 3 Nov 2026): « En route », « Sur place », « Disponible »,
/// « Pause », or none. The same status on the phone, the PC, the car and the
/// TV (choice 4): kept by the server on the device of the event, the most
/// recent choice (`at`) wins.
///
/// Received from GET …/devices, `device.updated`, `operator.status` and the
/// changes feed (`operator_status`); sent by [sendOperatorStatus] (PUT
/// …/devices/{device}/status, else the Outbox when the server cannot be
/// reached). Shown as a coloured pastille on the marker, in Équipes and in
/// the sheet of the operator.
library;

import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../offline/sync_service.dart';
import '../../services/sarcade_api.dart';

/// Order of the grid, same as the server and the car.
const operatorStatuses=['en_route','sur_place','disponible','pause'];

/// Colours of the pastille (server contract, as the TV).
const operatorStatusColors={
  'en_route':Color(0xFFFFB020),'sur_place':Color(0xFF4ADE80),'disponible':Color(0xFF3DD6F5),'pause':Color(0xFF9AA3AD),
};

/// A known status, else null (unknown values of a newer server ignored).
String? knownOperatorStatus(Object? v)=>v is String&&operatorStatuses.contains(v)?v:null;

/// « En route », « Sur place »… in the language of the device.
String operatorStatusLabel(String status)=>S.t('team.status.$status');

/// « 8 h 10 » in French, « 8:10 » in English (local time).
String statusClock(DateTime t){
  final l=t.toLocal(); final m=l.minute.toString().padLeft(2,'0');
  return S.lang=='fr'?'${l.hour} h $m':'${l.hour}:$m';
}

/// « En route · depuis 8 h 10 ».
String operatorStatusText(String status,DateTime? since)=>
  since==null?operatorStatusLabel(status):'${operatorStatusLabel(status)} · ${S.t('team.status.since',{'time':statusClock(since)})}';

typedef OperatorStatusEntry=({String? status,DateTime? at});

/// Statuses of the operators of one event, the most recent (`at`) winning
/// whatever the order in which realtime, the device list and the changes
/// feed bring them.
class OperatorStatusBook extends ChangeNotifier {
  final Map<String,OperatorStatusEntry> _entries={};
  /// Saved on the device, so that the pastilles stay without network.
  final void Function(Map<String,dynamic> json)? save;
  OperatorStatusBook({Map<String,dynamic>? saved,this.save}){
    final m=saved?['statuses'];
    if(m is Map){
      for(final e in m.entries){
        if(e.value is Map){final v=e.value as Map;_entries['${e.key}']=(status:knownOperatorStatus(v['s']),at:DateTime.tryParse('${v['at']??''}'));}
      }
    }
  }

  String? statusOf(String deviceId)=>_entries[deviceId]?.status;
  DateTime? sinceOf(String deviceId)=>_entries[deviceId]?.at;

  /// Sets the status of [deviceId] unless a more recent one is known.
  /// A state without time (device that never chose) only fills a gap.
  bool apply(String deviceId,String? status,DateTime? at){
    if(deviceId.isEmpty)return false;
    final old=_entries[deviceId];
    if(old!=null){
      if(at==null)return false;
      if(old.at!=null&&!at.isAfter(old.at!))return false;
      // The same status again keeps its first time (« depuis 8 h 10 »).
      if(old.status==status&&old.at!=null)return false;
    }else if(at==null&&status==null){return false;}
    _entries[deviceId]=(status:status,at:at?.toUtc());
    _changed();
    return true;
  }

  /// A device, a position, `operator.status` or a change of the feed: only
  /// when it carries `operator_status` (older servers say nothing).
  bool applyJson(Map<String,dynamic> j){
    if(!j.containsKey('operator_status'))return false;
    return apply('${j['device_id']??''}',knownOperatorStatus(j['operator_status']),DateTime.tryParse('${j['operator_status_at']??''}'));
  }

  /// Puts back an entry (status refused by the server).
  void restore(String deviceId,OperatorStatusEntry? entry){
    if(entry==null){if(_entries.remove(deviceId)==null)return;}else{_entries[deviceId]=entry;}
    _changed();
  }
  OperatorStatusEntry? entryOf(String deviceId)=>_entries[deviceId];

  void applyAll(Iterable<Map<String,dynamic>> list){for(final j in list){applyJson(j);}}

  Map<String,dynamic> toJson()=>{'statuses':{for(final e in _entries.entries)e.key:{'s':e.value.status,'at':e.value.at?.toIso8601String()}}};

  void _changed(){save?.call(toJson());notifyListeners();}
}

/// Body of PUT …/status and payload of the Outbox (`at` always sent: the
/// most recent choice wins, even sent late).
Map<String,dynamic> operatorStatusPayload(String deviceId,String? status,DateTime at,{String? actorId})=>
  {'device_id':deviceId,'status':status,'at':at.toUtc().toIso8601String(),'actor_id':?actorId};

/// Outcome of [sendOperatorStatus].
enum StatusSend{sent,queued,failed}

/// « Mon statut »: the one function the phone, the PC and the car call.
/// The status is shown at once in [book]; PUT …/devices/{device}/status,
/// and when the server cannot be reached the change waits in the Outbox
/// (`operator_status` / `update`, object = device). [sync] defaults to the
/// service of the open map ([OfflineSyncService.active]).
Future<StatusSend> sendOperatorStatus({required SarcadeApi api,required String eventId,required String deviceId,
    required String? status,DateTime? at,OperatorStatusBook? book,OfflineSyncService? sync}) async {
  final when=(at??DateTime.now()).toUtc();
  final before=book?.entryOf(deviceId);
  book?.apply(deviceId,status,when);
  try{
    final r=await api.putOperatorStatus(eventId,deviceId,operatorStatusPayload(deviceId,status,when,actorId:deviceId));
    book?.applyJson(r);
    return StatusSend.sent;
  }on SarcadeHttpException catch(e){
    if(e.isPermanent){debugPrint('SARCADE status refused: $e');book?.restore(deviceId,before);return StatusSend.failed;}
  }catch(e){debugPrint('SARCADE status not sent: $e');}
  final s=sync??OfflineSyncService.active;
  if(s==null||s.eventId!=eventId)return StatusSend.failed;
  await s.queue(objectId:deviceId,objectType:'operator_status',action:'update',payload:operatorStatusPayload(deviceId,status,when,actorId:deviceId));
  return StatusSend.queued;
}

/// Coloured pastille of a status (nothing without status).
class StatusDot extends StatelessWidget {
  final String? status; final double size;
  const StatusDot({super.key,required this.status,this.size=12});
  @override Widget build(BuildContext context){
    final c=operatorStatusColors[status];
    if(c==null)return const SizedBox.shrink();
    return Tooltip(message:operatorStatusLabel(status!),child:Container(key:ValueKey('status-dot-$status'),width:size,height:size,
      decoration:BoxDecoration(color:c,shape:BoxShape.circle,border:Border.all(color:Colors.black45,width:1.5))));
  }
}

/// [child] (marker icon, avatar) with the pastille at its bottom right.
Widget withStatusDot(Widget child,String? status,{double size=12}){
  if(operatorStatusColors[status]==null)return child;
  return Stack(clipBehavior:Clip.none,children:[child,Positioned(right:-2,bottom:-2,child:StatusDot(status:status,size:size))]);
}

/// « Mon statut »: four choices; touching the current one removes it.
class MyStatusPicker extends StatelessWidget {
  final String? status; final DateTime? since;
  final ValueChanged<String?> onChanged;
  const MyStatusPicker({super.key,required this.status,required this.onChanged,this.since});
  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    return Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
      Text(status!=null&&since!=null?'${S.t('team.status.mine')} · ${S.t('team.status.since',{'time':statusClock(since!)})}':S.t('team.status.mine'),
        style:t.textTheme.labelLarge?.copyWith(color:t.colorScheme.onSurfaceVariant)),
      const SizedBox(height:6),
      Wrap(spacing:6,runSpacing:6,children:[for(final s in operatorStatuses)ChoiceChip(key:ValueKey('my-status-$s'),
        avatar:StatusDot(status:s),label:Text(operatorStatusLabel(s)),selected:status==s,showCheckmark:false,
        visualDensity:VisualDensity.compact,tooltip:status==s?S.t('team.status.clear'):null,
        onSelected:(_)=>onChanged(status==s?null:s))]),
    ]);
  }
}

/// Choice of « Mon statut » on the phone or the PC: sent, and a short note
/// when it waits in the Outbox or could not leave.
Future<void> chooseMyStatus(BuildContext context,{required SarcadeApi api,required String eventId,required String deviceId,
    required String? status,required OperatorStatusBook book,OfflineSyncService? sync}) async {
  final messenger=ScaffoldMessenger.maybeOf(context);
  final r=await sendOperatorStatus(api:api,eventId:eventId,deviceId:deviceId,status:status,book:book,sync:sync);
  if(r==StatusSend.sent)return;
  messenger?.showSnackBar(SnackBar(content:Text(S.t(r==StatusSend.queued?'team.status.queued':'team.status.failed'))));
}
