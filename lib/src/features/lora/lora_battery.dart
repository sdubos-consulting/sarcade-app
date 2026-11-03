/// Low battery of the LoRa boxes (card « Boîtiers LoRa (MeshCore, puis
/// Meshtastic) : alerte de batterie faible », lot 25, choices validated on
/// 3 Nov 2026, 10 h 53):
/// 1. the module linked to this device is watched: warning at 20 % (orange
///    bar « Boîtier LoRa : batterie faible (18 %) »), alert at 10 % (red bar
///    and notification), once per threshold, reminder if the battery drops
///    5 % more;
/// 2. the MeshCore pill turns orange with a battery icon, the MeshCore line
///    of Liaisons gives the level;
/// 3. remote relays: same alert from their telemetry, with the name of the
///    relay (a [LoraBatteryMonitor.report] per box; no box sends a level
///    today);
/// 4. thresholds set in Outils › MeshCore, kept on this device;
/// 5. percentage from the voltage when the module does not give it (lithium
///    battery, 3.0 V = 0 %, 4.2 V = 100 %);
/// 6. the alert goes by itself once the box is charged (threshold + 5 %);
/// 7. the same for the future Meshtastic module ([LoraBox.meshtastic]).
library;

import 'package:flutter/foundation.dart';

import '../../l10n/strings.dart';

/// Kind of LoRa box watched.
enum LoraBox { meshcore, meshtastic, relay }

/// Level of a battery.
enum LoraBatteryLevel { ok, warning, alert }

/// Thresholds by default (point 1).
const int loraBatteryWarnDefault=20, loraBatteryAlertDefault=10;

/// Margin above a threshold before the alert goes (point 6) and drop that
/// brings a reminder (point 1).
const int loraBatteryMargin=5;

/// Preferences of the thresholds (point 4).
const String loraBatteryWarnKey='lora_battery_warn', loraBatteryAlertKey='lora_battery_alert';

/// Percentage of a lithium battery from its voltage in millivolts (point 5).
int loraBatteryPercent(int millivolts)=>((millivolts-3000)*100/1200).round().clamp(0,100);

/// Thresholds read from the preferences: alert under warning, both between
/// 1 and 99, defaults otherwise.
({int warn,int alert}) loraBatteryThresholds(String? warn,String? alert){
  var w=int.tryParse(warn??'')??loraBatteryWarnDefault, a=int.tryParse(alert??'')??loraBatteryAlertDefault;
  w=w.clamp(1,99); a=a.clamp(1,99);
  if(a>=w)a=(w-1).clamp(1,99);
  if(a>=w){w=loraBatteryWarnDefault;a=loraBatteryAlertDefault;}
  return (warn:w,alert:a);
}

/// State of one box: level shown, and what is said (bar, notification).
class LoraBatteryState {
  final String id, name; final LoraBox box;
  final int percent; final LoraBatteryLevel level;
  /// Lowest percentage already signalled at this level (reminder 5 % under).
  final int? signalled;
  const LoraBatteryState({required this.id,required this.name,required this.box,required this.percent,required this.level,this.signalled});
}

/// One step of the watch: the new state, and whether a notification goes.
typedef LoraBatteryStep=({LoraBatteryState state,bool notify});

/// Next state of a box from its new [percent] (pure, tested).
/// - the level goes down as soon as the percentage reaches a threshold;
/// - it goes back up only at the threshold + [loraBatteryMargin];
/// - a notification at the alert, once, then a reminder for each further
///   drop of [loraBatteryMargin].
LoraBatteryStep loraBatteryStep(LoraBatteryState? before,{required String id,required String name,required LoraBox box,
    required int percent,required int warn,required int alert}){
  final was=before?.level??LoraBatteryLevel.ok;
  LoraBatteryLevel level;
  if(percent<=alert){level=LoraBatteryLevel.alert;}
  else if(percent<=warn){level=was==LoraBatteryLevel.alert&&percent<alert+loraBatteryMargin?LoraBatteryLevel.alert:LoraBatteryLevel.warning;}
  else if(was!=LoraBatteryLevel.ok&&percent<warn+loraBatteryMargin){level=was==LoraBatteryLevel.alert&&percent<alert+loraBatteryMargin?LoraBatteryLevel.alert:LoraBatteryLevel.warning;}
  else{level=LoraBatteryLevel.ok;}
  var notify=false; int? signalled=level==was?before?.signalled:null;
  if(level!=LoraBatteryLevel.ok){
    final first=level.index>was.index;
    final reminder=!first&&signalled!=null&&percent<=signalled-loraBatteryMargin;
    if(first||reminder){
      signalled=percent;
      notify=level==LoraBatteryLevel.alert;
    }
  }
  if(level==LoraBatteryLevel.ok)signalled=null;
  return (state:LoraBatteryState(id:id,name:name,box:box,percent:percent,level:level,signalled:signalled),notify:notify);
}

/// Text of the bar: « Boîtier LoRa : batterie faible (18 %) », with the name
/// of the relay for a remote relay (point 3).
String loraBatteryText(LoraBatteryState s)=>s.box==LoraBox.relay
  ?S.t('lora.battery.relay',{'name':s.name,'p':s.percent})
  :S.t('lora.battery.low',{'p':s.percent});

/// Short level for the MeshCore line of Liaisons (point 2): « batterie 18 % ».
String loraBatteryLine(int percent)=>S.t('lora.battery.level',{'p':percent});

/// Watch of every LoRa box: the module of this device (MeshCore, later
/// Meshtastic) and the remote relays.
class LoraBatteryMonitor extends ChangeNotifier {
  LoraBatteryMonitor();
  static final LoraBatteryMonitor instance=LoraBatteryMonitor();

  /// Preferences of the device ([read]/[save]), set by the application.
  String? Function(String key)? read;
  Future<void> Function(String key,String? value)? save;
  /// Notification of the alert ([title], [body]).
  void Function(String title,String body)? notify;

  final Map<String,LoraBatteryState> _boxes={};

  ({int warn,int alert}) get thresholds=>loraBatteryThresholds(read?.call(loraBatteryWarnKey),read?.call(loraBatteryAlertKey));

  /// Thresholds set in Outils › MeshCore (point 4).
  Future<void> setThresholds({required int warn,required int alert}) async {
    final t=loraBatteryThresholds('$warn','$alert');
    await save?.call(loraBatteryWarnKey,'${t.warn}');
    await save?.call(loraBatteryAlertKey,'${t.alert}');
    notifyListeners();
  }

  /// A level read from a box: [percent] when it gives one, else from
  /// [millivolts] (point 5).
  void report({required String id,required String name,required LoraBox box,int? percent,int? millivolts}){
    final p=percent??(millivolts==null?null:loraBatteryPercent(millivolts));
    if(p==null)return;
    final t=thresholds;
    final step=loraBatteryStep(_boxes[id],id:id,name:name,box:box,percent:p.clamp(0,100),warn:t.warn,alert:t.alert);
    _boxes[id]=step.state;
    if(step.notify)notify?.call(S.t('lora.battery.title'),loraBatteryText(step.state));
    notifyListeners();
  }

  /// The box is no longer linked (forgotten, disconnected): its bar goes.
  void forget(String id){if(_boxes.remove(id)!=null)notifyListeners();}

  /// Last state of a box.
  LoraBatteryState? stateOf(String id)=>_boxes[id];

  /// Boxes whose battery is low, the worst first.
  List<LoraBatteryState> get low=>_boxes.values.where((s)=>s.level!=LoraBatteryLevel.ok).toList()
    ..sort((a,b){final l=b.level.index.compareTo(a.level.index);return l!=0?l:a.percent.compareTo(b.percent);});

  @visibleForTesting
  void resetForTest(){_boxes.clear();read=null;save=null;notify=null;}
}
