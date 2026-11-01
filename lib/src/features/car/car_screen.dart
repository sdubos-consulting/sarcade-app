/// SARCADE screen in the car with tabs (card « Voiture : vraie interface
/// SARCADE avec onglets », lot 17, choices validated on 1 Nov 2026, 11 h 00):
/// what the Android Auto screen shows and what the driver does there.
///
/// - the application computes everything (texts, distances, colours) and
///   writes it as JSON for the plugin `third_party/sarcade_car`, which only
///   draws the templates of the Car App Library: one source of the texts
///   (`car.*` of strings.dart, French and English);
/// - tabs Messages, Ordres, Points, Équipe; SOS always there, confirmed;
///   tiles with the icon and the colour of the operator, priority in
///   colour; no typing (voice only), no SARCADE map;
/// - the driver's actions come back as [CarAction]s, applied by
///   [applyCarAction] with the same objects as the phone (acknowledgement,
///   message, move order, distress).
///
/// Pure code, testable without Flutter widgets.
library;

import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/strings.dart';
import '../../models/comm_group.dart';
import '../../models/message.dart';
import '../../models/poi.dart';
import '../../models/position.dart';
import '../../ui/operator_color.dart';
import '../map/drawing/geometry.dart' show bearingDeg, distanceM, formatDistance;
import '../map/operator_icons.dart' show chosenIcon;
import '../map/stations.dart' show ageLabel;
import '../messages/conversations.dart';
import '../orders/move_orders.dart';
import '../poi/poi_icons.dart' show poiIconLabel;
import '../poi/poi_sheet.dart' show poiColor;
import 'car_messaging.dart' show carReply;

/// Messages of a conversation kept for the car (text and reading aloud).
const carConversationMessages=5;
/// Messages read aloud by « Lire ».
const carSpokenMessages=3;
/// Conversations, points, operators sent to the car (the car shows fewer).
const carMaxItems=30;
/// High points and relays: the nearest ones, within this distance.
const carReferenceRadiusM=50000.0;
const carReferencesPerKind=5;

const _highPointColor=0xFF6D4C41, _relayColor=0xFF8E24AA, _allColor=0xFF1E88E5;

/// High point or relay of the radio reference (ADRASEC module), given by
/// the map page: the Core does not import the module.
typedef CarSite=({String id,String name,bool relay,double lat,double lon,double? mhz,double? altM});

/// What the application knows when the car asks (see the map page).
class CarScreenInput {
  final String me, eventId;
  final List<SarcadeMessage> messages;
  final Map<String,CommGroup> groups;
  final List<SarcadeAck> acks;
  final List<MoveOrder> orders;
  final List<SarcadePoi> pois;
  final List<CarSite> references;
  final List<SarcadePosition> positions;
  final Map<String,Map<String,dynamic>> devices;
  /// Position of this phone, null when unknown (no distance then).
  final LatLng? here;
  final bool inDistress;
  final DateTime now;
  const CarScreenInput({required this.me,required this.eventId,this.messages=const [],this.groups=const {},this.acks=const [],
    this.orders=const [],this.pois=const [],this.references=const [],this.positions=const [],this.devices=const {},
    this.here,this.inDistress=false,required this.now});
}

/// « 4,2 km au nord-ouest », empty without position.
String carAway(LatLng? from,LatLng to){
  if(from==null)return '';
  final d=distanceM(from,to);
  if(d<20)return S.t('car.here');
  const dirs=['n','ne','e','se','s','sw','w','nw'];
  final dir=dirs[((bearingDeg(from,to)+22.5)%360~/45)%8];
  return S.t('car.away',{'d':formatDistance(d),'dir':S.t('car.dir.$dir')});
}

String _join(Iterable<String> parts)=>parts.where((p)=>p.trim().isNotEmpty).join(' · ');

String _hm(DateTime t){final l=t.toLocal();String two(int v)=>v.toString().padLeft(2,'0');return '${two(l.hour)}:${two(l.minute)}';}

/// « URGENT » for a raised priority, empty for routine.
String _prioLabel(String p)=>priorityRaised(p)?S.t(priorityKey(p)).toUpperCase():'';

/// Messages of this terminal grouped by conversation, the latest first.
Map<String,List<SarcadeMessage>> carConversations(CarScreenInput i){
  final out=<String,List<SarcadeMessage>>{};
  final list=i.messages.where((m)=>m.eventId==i.eventId&&!m.deleted&&(m.senderId==i.me||addressedTo(m.recipientIds,i.me,i.groups))).toList()
    ..sort((a,b)=>a.createdAt.compareTo(b.createdAt));
  for(final m in list){(out[conversationOf(m,i.me,i.groups)]??=[]).add(m);}
  final keys=out.keys.toList()..sort((a,b)=>out[b]!.last.createdAt.compareTo(out[a]!.last.createdAt));
  return {for(final k in keys)k:out[k]!};
}

bool _readByMe(SarcadeMessage m,CarScreenInput i)=>i.acks.any((a)=>a.messageId==m.id&&a.actorId==i.me&&const {'read','accepted','rejected'}.contains(a.status));

/// Messages of a conversation not read yet by this terminal.
List<SarcadeMessage> carUnread(List<SarcadeMessage> conversation,CarScreenInput i)=>
  [for(final m in conversation)if(m.senderId!=i.me&&!_readByMe(m,i))m];

/// Who a dictated answer goes to (lot 1b choice): the other person of a
/// direct chat, else the last sender of the channel; null when only I wrote.
String? carReplyTarget(String key,List<SarcadeMessage> conversation,String me){
  final peer=peerOf(key);
  if(peer!=null)return peer;
  for(final m in conversation.reversed){if(m.senderId!=me)return m.senderId;}
  return null;
}

String _conversationTitle(String key,CarScreenInput i){
  final peer=peerOf(key);
  if(peer!=null)return peer;
  final g=groupOf(key);
  if(g!=null)return i.groups[g]?.name??S.t('car.channel');
  return S.t('car.allChannel');
}

String _who(SarcadeMessage m,String me)=>m.senderId==me?S.t('car.you'):m.senderId;
String _text(SarcadeMessage m)=>m.body.trim().isEmpty?S.t('car.photo'):m.body.trim().replaceAll(RegExp(r'\s+'),' ');

Map<String,Object?> _conversation(String key,List<SarcadeMessage> c,CarScreenInput i){
  final last=c.last, peer=peerOf(key), g=groupOf(key);
  final target=carReplyTarget(key,c,i.me);
  final shown=c.length>carConversationMessages?c.sublist(c.length-carConversationMessages):c;
  final spoken=c.length>carSpokenMessages?c.sublist(c.length-carSpokenMessages):c;
  return {
    'id':key,
    'title':_conversationTitle(key,i),
    'text':'${_who(last,i.me)} : ${_text(last)}',
    'prio':last.priority,'prioLabel':_prioLabel(last.priority),
    'unread':carUnread(c,i).length,
    'icon':peer!=null?chosenIcon(i.devices,deviceId:peer):'channel',
    'color':peer!=null?operatorColor(peer):(g!=null?(i.groups[g]?.color??_allColor):_allColor),
    'body':[for(final m in shown)_join([_hm(m.createdAt),_prioLabel(m.priority),'${_who(m,i.me)} : ${_text(m)}'])].join('\n'),
    'speak':[for(final m in spoken)S.t('car.speak',{'prio':priorityRaised(m.priority)?'${S.t(priorityKey(m.priority))}. ':'','who':_who(m,i.me),'text':_text(m).replaceFirst(RegExp(r'[.!?…]+$'),'')})].join(' '),
    'canReply':target!=null,
    'replyTo':target??'',
  };
}

/// Orders addressed to this terminal: in progress first, then the recent
/// answers (same 30 min as the map); never the cancelled ones.
List<MoveOrder> carOrders(CarScreenInput i){
  final mine=i.orders.where((o)=>o.targetId==i.me&&o.status!='cancelled'&&(o.open||moveOrderOnMap(o,i.now))).toList()
    ..sort((a,b){
      if(a.open!=b.open)return a.open?-1:1;
      return '${b.json['updated_at']}'.compareTo('${a.json['updated_at']}');
    });
  return mine;
}

Map<String,Object?> _order(MoveOrder o,CarScreenInput i)=>{
  'id':o.id,'title':o.label,'status':o.status,
  'text':_join([o.createdBy,S.t('order.status.${o.status}'),carAway(i.here,o.destination)]),
  'note':o.note,
  'lat':o.destination.latitude,'lon':o.destination.longitude,
  'color':moveOrderColor(o.status).toARGB32(),
};

/// Designated points (all, the nearest first), then the high points and
/// relays near the phone (the ADRASEC module gives them, else none).
List<Map<String,Object?>> carPoints(CarScreenInput i){
  final here=i.here;
  double dist(double lat,double lon)=>here==null?double.infinity:distanceM(here,LatLng(lat,lon));
  final pois=[...i.pois.where((p)=>!p.deleted&&p.eventId==i.eventId)]..sort((a,b)=>dist(a.lat,a.lon).compareTo(dist(b.lat,b.lon)));
  final out=<Map<String,Object?>>[
    for(final p in pois){
      'id':p.id,'kind':'poi','icon':p.icon??'pin','color':poiColor(p),
      'title':(p.label??'').trim().isEmpty?poiIconLabel(p.icon):p.label!.trim(),
      'text':carAway(here,LatLng(p.lat,p.lon)),
      'lat':p.lat,'lon':p.lon,
    },
  ];
  if(here!=null){
    final near=[...i.references.where((r)=>dist(r.lat,r.lon)<=carReferenceRadiusM)]
      ..sort((a,b)=>dist(a.lat,a.lon).compareTo(dist(b.lat,b.lon)));
    final refs=[...near.where((r)=>!r.relay).take(carReferencesPerKind),...near.where((r)=>r.relay).take(carReferencesPerKind)]
      ..sort((a,b)=>dist(a.lat,a.lon).compareTo(dist(b.lat,b.lon)));
    for(final r in refs){
      out.add({
        'id':r.id,'kind':r.relay?'relay':'high','icon':r.relay?'relay':'high','color':r.relay?_relayColor:_highPointColor,
        'title':r.name,
        'text':_join([carAway(here,LatLng(r.lat,r.lon)),r.relay?S.t('car.relay'):S.t('car.highPoint'),
          if(r.relay&&r.mhz!=null)'${r.mhz!.toStringAsFixed(4).replaceAll('.',',')} MHz',
          if(!r.relay&&r.altM!=null)'${r.altM!.round()} m']),
        'lat':r.lat,'lon':r.lon,
      });
    }
  }
  return out.take(carMaxItems).toList();
}

/// Other operators of the event (SARCADE terminals, not the APRS stations),
/// the nearest first.
List<Map<String,Object?>> carTeam(CarScreenInput i){
  final here=i.here;
  double dist(SarcadePosition p)=>here==null?double.infinity:distanceM(here,LatLng(p.lat,p.lon));
  final others=i.positions.where((p)=>!p.isAprs&&p.deviceId!=i.me&&p.eventId==i.eventId).toList()
    ..sort((a,b){final c=dist(a).compareTo(dist(b));return c!=0?c:a.label.toLowerCase().compareTo(b.label.toLowerCase());});
  return [
    for(final p in others.take(carMaxItems)){
      'id':p.deviceId,'title':p.label,
      'icon':chosenIcon(i.devices,deviceId:p.deviceId),'color':operatorColor(p.deviceId),
      'text':_join([carAway(here,LatLng(p.lat,p.lon)),S.t('car.seen',{'age':ageLabel(p.time.toUtc(),i.now.toUtc())})]),
      'lat':p.lat,'lon':p.lon,
    },
  ];
}

/// Texts of the car screen (`car.*`), sent with the data.
Map<String,String> carLabels()=>{
  for(final t in const ['messages','orders','points','team'])'tab.$t':S.t('car.tab.$t'),
  for(final t in const ['messages','orders','points','team'])'empty.$t':S.t('car.empty.$t'),
  for(final k in const ['sos','sosTitle','sosAsk','sosSend','sosSent','sosOn','sosEnd','sosEnded','cancel','navigate','navigateFailed',
    'accept','refuse','arrived','read','reply','replyTo','listening','dictationFailed','retry','send','sent','stale','sections',
    'gone','note','order'])k:S.t('car.$k'),
};

/// Everything the car shows, as written to the plugin.
Map<String,Object?> carSnapshot(CarScreenInput i){
  final conversations=carConversations(i);
  return {
    'v':1,
    'at':i.now.millisecondsSinceEpoch,
    'lang':S.lang,
    'distress':i.inDistress,
    'labels':carLabels(),
    'messages':[for(final e in conversations.entries.take(carMaxItems))_conversation(e.key,e.value,i)],
    'orders':[for(final o in carOrders(i).take(carMaxItems))_order(o,i)],
    'points':carPoints(i),
    'team':carTeam(i),
  };
}

// --- Actions of the driver ----------------------------------------------------

/// One action done in the car (see CarData.post of the plugin).
class CarAction {
  final String type;
  final Map<String,dynamic> data;
  const CarAction(this.type,this.data);
  String get id=>'${data['id']??''}';
  String get status=>'${data['status']??''}';
  String get conversation=>'${data['conversation']??''}';
  String get text=>'${data['text']??''}'.trim();
}

/// Actions read from the plugin (JSON list); damaged entries are skipped.
List<CarAction> parseCarActions(Object? raw){
  final out=<CarAction>[];
  if(raw is! List)return out;
  for(final a in raw){
    if(a is! Map)continue;
    final type=a['type'];
    if(type is! String||type.isEmpty)continue;
    out.add(CarAction(type,Map<String,dynamic>.from(a)));
  }
  return out;
}

/// What an action may change, given by the map page (same objects as on
/// the phone).
class CarScreenActions {
  /// Answer to a move order (accepted, refused, arrived).
  final Future<void> Function(MoveOrder order,String status) order;
  /// Acknowledgement « read » of a message, cached and queued.
  final Future<void> Function(SarcadeAck ack,SarcadeMessage message) ack;
  /// A new message, cached and queued.
  final Future<void> Function(SarcadeMessage message) send;
  final Future<void> Function() sos, sosEnd;
  const CarScreenActions({required this.order,required this.ack,required this.send,required this.sos,required this.sosEnd});
}

/// Answers allowed from the car, as on the phone banner.
bool carOrderAnswerAllowed(String from,String to)=>switch(to){
  'accepted'||'refused'=>from=='sent',
  'arrived'=>from=='accepted',
  _=>false,
};

/// Applies [a]; data changed since the car showed it make it do nothing
/// (order already answered, conversation gone, distress already sent).
Future<void> applyCarAction(CarAction a,CarScreenInput i,CarScreenActions act,{Uuid uuid=const Uuid()}) async {
  switch(a.type){
    case 'order':
      final o=i.orders.where((x)=>x.id==a.id&&x.targetId==i.me).firstOrNull;
      if(o!=null&&carOrderAnswerAllowed(o.status,a.status))await act.order(o,a.status);
    case 'read':
      final c=carConversations(i)[a.conversation];
      if(c==null)return;
      for(final m in carUnread(c,i)){
        await act.ack(SarcadeAck(id:uuid.v4(),eventId:i.eventId,messageId:m.id,actorId:i.me,status:'read',time:i.now.toUtc()),m);
      }
    case 'reply':
      final c=carConversations(i)[a.conversation];
      if(c==null||a.text.isEmpty)return;
      final to=carReplyTarget(a.conversation,c,i.me);
      if(to==null)return;
      final answered=c.lastWhere((m)=>m.senderId==to,orElse:()=>c.last);
      await act.send(carReply(id:uuid.v4(),eventId:i.eventId,me:i.me,sender:to,messageId:answered.id,text:a.text,now:i.now));
    case 'sos':
      if(!i.inDistress)await act.sos();
    case 'sosEnd':
      if(i.inDistress)await act.sosEnd();
  }
}
