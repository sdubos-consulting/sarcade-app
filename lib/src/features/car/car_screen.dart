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

import 'dart:async';
import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/strings.dart';
import '../../models/comm_group.dart';
import '../../models/message.dart';
import '../../models/poi.dart';
import '../../models/position.dart';
import '../../ui/operator_color.dart';
import '../map/drawing/geometry.dart' show bearingDeg, distanceM;
import '../map/operator_icons.dart' show baseCallsign, chosenIcon;
import '../messages/conversations.dart';
import '../orders/move_orders.dart';
import '../poi/poi_icons.dart' show poiIconLabel;
import '../poi/poi_sheet.dart' show poiColor;
import 'car_field.dart';
import 'car_remotes.dart';
import 'car_weather.dart' show carWeatherKey;
import 'car_messaging.dart' show carReply;

/// Messages of a conversation kept for the car (text and reading aloud).
const carConversationMessages=5;
/// Messages read aloud by « Lire ».
const carSpokenMessages=3;
/// Conversations, points, operators sent to the car (the car shows fewer).
const carMaxItems=30;
/// High points: the nearest ones, within this distance (lot 20, card
/// « Android Auto, onglet Points : retirer les relais radio… »: no relay,
/// up to 10 high points within 50 km).
const carReferenceRadiusM=50000.0;
const carHighPointsMax=10;

const _highPointColor=0xFF6D4C41, _allColor=0xFF1E88E5;

/// High point or relay of the radio reference (ADRASEC module), given by
/// the map page: the Core does not import the module. The car only shows
/// the high points (lot 20).
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
  /// What the car sends for the field (lot 24: status…), null in the tests
  /// that do not need it.
  final CarField? field;
  /// Settings of the event (`settings` of the heartbeat, lot 24).
  final Map<String,dynamic> settings;
  const CarScreenInput({required this.me,required this.eventId,this.messages=const [],this.groups=const {},this.acks=const [],
    this.orders=const [],this.pois=const [],this.references=const [],this.positions=const [],this.devices=const {},
    this.here,this.inDistress=false,required this.now,this.field,this.settings=const {}});
}

/// Distance shown in the car (lot 20, card « Android Auto : l'écran
/// clignote… », choice 1): by 50 m under 1 km, by 0,5 km beyond, so that a
/// small move of the GPS does not change the text (nor redraw the screen).
String carDistance(double m){
  if(m<975)return '${((m/50).round()*50).clamp(50,950)} m';
  final km=(m/500).round()/2;
  return km==km.truncateToDouble()?'${km.toInt()} km':'${km.toStringAsFixed(1).replaceAll('.',',')} km';
}

/// « 4,5 km au nord-ouest », empty without position; [short]: « 4,5 km
/// NO », for the Points tab (lot 20, card « Android Auto, onglet Points :
/// boutons ronds gris vides… », choice 3: the line no longer cut).
String carAway(LatLng? from,LatLng to,{bool short=false}){
  if(from==null)return '';
  final d=distanceM(from,to);
  if(d<20)return S.t('car.here');
  const dirs=['n','ne','e','se','s','sw','w','nw'];
  final dir=dirs[((bearingDeg(from,to)+22.5)%360~/45)%8];
  return S.t('car.away',{'d':carDistance(d),'dir':S.t(short?'car.dirShort.$dir':'car.dir.$dir')});
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

/// True when [target] is this terminal, or another terminal of the same
/// person: same callsign (without its SSID) in Paramètres › Profil (lot 20,
/// card « Android Auto : ordres de déplacement peu utilisables… », choice
/// 2: the order on every terminal of the person, phone and car).
bool carSamePerson(String target,String me,Map<String,Map<String,dynamic>> devices){
  if(target==me)return true;
  final mine=baseCallsign('${devices[me]?['callsign']??''}');
  return mine.isNotEmpty&&baseCallsign('${devices[target]?['callsign']??''}')==mine;
}

/// Orders addressed to this terminal or to another terminal of the same
/// person: in progress first, then the recent answers (same 30 min as the
/// map); never the cancelled ones.
List<MoveOrder> carOrders(CarScreenInput i){
  final mine=i.orders.where((o)=>carSamePerson(o.targetId,i.me,i.devices)&&o.status!='cancelled'&&(o.open||moveOrderOnMap(o,i.now))).toList()
    ..sort((a,b){
      if(a.open!=b.open)return a.open?-1:1;
      return '${b.json['updated_at']}'.compareTo('${a.json['updated_at']}');
    });
  return mine;
}

Map<String,Object?> _order(MoveOrder o,CarScreenInput i)=>{
  'id':o.id,'title':o.label,'status':o.status,
  // Alert of a new order (lot 20): « P2 », then « Ordre de déplacement · PCO · 3 km NO ».
  'from':o.createdBy,'away':carAway(i.here,o.destination,short:true),
  'text':_join([o.createdBy,S.t('order.status.${o.status}'),carAway(i.here,o.destination)]),
  'note':o.note,
  'lat':o.destination.latitude,'lon':o.destination.longitude,
  'color':moveOrderColor(o.status).toARGB32(),
  // Lot 24 (card « Android Auto : arrivée détectée près du point d'un
  // ordre », choice 1): within 100 m of the point of an accepted order.
  if(carNearArrival(o,i))'near':true,
  // Lot 24: key of its weather (« weather » of the data).
  'wkey':carWeatherKey(o.destination.latitude,o.destination.longitude),
};

/// Distance to the point of an accepted order under which the car asks
/// « Vous êtes arrivé à … Signaler l'arrivée ? » (lot 24).
const carArrivalRadiusM=100.0;

/// True within [carArrivalRadiusM] of the point of an accepted order of mine.
bool carNearArrival(MoveOrder o,CarScreenInput i)=>
  o.status=='accepted'&&i.here!=null&&distanceM(i.here!,o.destination)<=carArrivalRadiusM;

/// Designated points of the event (all, the nearest first), then the
/// nearest high points with their altitude, up to 10 within 50 km (the
/// ADRASEC module gives them, else none). Never a relay: not a place to
/// drive to (lot 20).
List<Map<String,Object?>> carPoints(CarScreenInput i){
  final here=i.here;
  double dist(double lat,double lon)=>here==null?double.infinity:distanceM(here,LatLng(lat,lon));
  final pois=[...i.pois.where((p)=>!p.deleted&&p.eventId==i.eventId)]..sort((a,b)=>dist(a.lat,a.lon).compareTo(dist(b.lat,b.lon)));
  final out=<Map<String,Object?>>[
    for(final p in pois){
      'id':p.id,'kind':'poi','icon':p.icon??'pin','color':poiColor(p),
      'title':(p.label??'').trim().isEmpty?poiIconLabel(p.icon):p.label!.trim(),
      'text':carAway(here,LatLng(p.lat,p.lon),short:true),
      'lat':p.lat,'lon':p.lon,
      // Card of the point (lot 24): type, distance and direction, author.
      'type':poiIconLabel(p.icon),'away':carAway(here,LatLng(p.lat,p.lon)),
      if((p.createdBy??'').trim().isNotEmpty)'by':S.t('car.createdBy',{'who':p.createdBy!.trim()}),
      'wkey':carWeatherKey(p.lat,p.lon),
    },
  ];
  if(here!=null){
    final high=[...i.references.where((r)=>!r.relay&&dist(r.lat,r.lon)<=carReferenceRadiusM)]
      ..sort((a,b)=>dist(a.lat,a.lon).compareTo(dist(b.lat,b.lon)));
    for(final r in high.take(carHighPointsMax)){
      out.add({
        'id':r.id,'kind':'high','icon':'high','color':_highPointColor,
        'title':r.name,
        'text':_join([carAway(here,LatLng(r.lat,r.lon),short:true),S.t('car.highPoint'),if(r.altM!=null)'${r.altM!.round()} m']),
        'lat':r.lat,'lon':r.lon,
        'type':S.t('car.highPoint'),'away':carAway(here,LatLng(r.lat,r.lon)),
        if(r.altM!=null)'alt':S.t('car.altitude',{'m':r.altM!.round()}),
        'wkey':carWeatherKey(r.lat,r.lon),
      });
    }
  }
  return out.take(carMaxItems).toList();
}

/// Operators seen longer ago are not in the Équipe tab (lot 23, card
/// « Android Auto : SOS dans la barre du haut, opérateurs anciens
/// masqués… », choice 2).
const carTeamMaxAge=Duration(hours:24);

/// Other operators of the event (SARCADE terminals, not the APRS stations)
/// seen within 24 h, the nearest first.
List<Map<String,Object?>> carTeam(CarScreenInput i){
  final here=i.here;
  double dist(SarcadePosition p)=>here==null?double.infinity:distanceM(here,LatLng(p.lat,p.lon));
  final others=i.positions.where((p)=>!p.isAprs&&p.deviceId!=i.me&&p.eventId==i.eventId&&i.now.difference(p.time)<carTeamMaxAge).toList()
    ..sort((a,b){final c=dist(a).compareTo(dist(b));return c!=0?c:a.label.toLowerCase().compareTo(b.label.toLowerCase());});
  return [
    for(final p in others.take(carMaxItems)){
      'id':p.deviceId,'title':p.label,
      'icon':chosenIcon(i.devices,deviceId:p.deviceId),'color':operatorColor(p.deviceId),
      'text':_join([carAway(here,LatLng(p.lat,p.lon)),carSeen(p.time,i.now)]),
      // No position, no « Naviguer » (lot 23, choice 4).
      if(p.lat.isFinite&&p.lon.isFinite)...{'lat':p.lat,'lon':p.lon},
      ...carTeammateCard(p,i),
    },
  ];
}

/// Lot 24 (card « Android Auto, onglet Équipe : fiche d'un opérateur avec
/// actions », choice 2): what the card of an operator shows besides his
/// name: role, distance and direction, age of the position, battery when
/// known, last message received from him.
Map<String,Object?> carTeammateCard(SarcadePosition p,CarScreenInput i){
  final here=i.here, battery=i.devices[p.deviceId]?['battery_pct'];
  final last=carLastMessageFrom(p.deviceId,i);
  return {
    'role':carRole(p.deviceId,i),
    'away':p.lat.isFinite&&p.lon.isFinite?carAway(here,LatLng(p.lat,p.lon)):'',
    'seen':carSeen(p.time,i.now),
    if(battery is num)'battery':S.t('car.battery',{'pct':battery.round()}),
    if(last!=null)'last':_join([_hm(last.createdAt),_prioLabel(last.priority),_text(last)]),
    // Lot 24 (card « statut en un appui », choice 2): his status.
    if(carStatuses.contains(i.devices[p.deviceId]?['operator_status']))'status':S.t('car.status.${i.devices[p.deviceId]!['operator_status']}'),
  };
}

/// « PCO », the teams he is a member of, his callsign; empty when nothing
/// is known (the server keeps no other role of an operator).
String carRole(String id,CarScreenInput i){
  final teams=[for(final g in i.groups.values)if(g.kind=='team'&&!g.archived&&g.members.contains(id))g.name]..sort();
  final callsign='${i.devices[id]?['callsign']??''}'.trim();
  return _join([if(isPco(id))'PCO',...teams,if(callsign.isNotEmpty&&callsign!=id)callsign]);
}

/// Last message sent by [id] that this terminal sees, null when none.
SarcadeMessage? carLastMessageFrom(String id,CarScreenInput i){
  SarcadeMessage? last;
  for(final m in i.messages){
    if(m.eventId!=i.eventId||m.deleted||m.senderId!=id||!addressedTo(m.recipientIds,i.me,i.groups))continue;
    if(last==null||m.createdAt.isAfter(last.createdAt))last=m;
  }
  return last;
}

/// Age of the position of an operator in the car (lot 23, card « Android
/// Auto, onglet Équipe : naviguer vers un opérateur », choice 3): by 5 min
/// up to 15 min, so that the text (and the screen) does not change at
/// every write (lot 20); beyond, the time of the position, « position de
/// 20 h 05 », which no longer changes.
String carSeen(DateTime time,DateTime now){
  final d=now.difference(time);
  if(d<const Duration(minutes:5))return S.t('car.seenRecent');
  if(d<=const Duration(minutes:15))return S.t('car.seen',{'age':'${d.inMinutes~/5*5}\u00A0min'});
  final l=time.toLocal();
  return S.t('car.positionAt',{'h':'${l.hour}','m':l.minute.toString().padLeft(2,'0')});
}

/// Texts of the car screen (`car.*`), sent with the data.
Map<String,String> carLabels()=>{
  for(final t in const ['messages','orders','points','team'])'tab.$t':S.t('car.tab.$t'),
  for(final t in const ['messages','orders','points','team'])'empty.$t':S.t('car.empty.$t'),
  for(final k in const ['sos','sosTitle','sosAsk','sosSend','sosSent','sosOn','sosEnd','sosEnded','cancel','navigate','navigateCar','navigateCarShort','navigateFailed',
    'accept','refuse','arrived','read','reply','replyTo','listening','dictationFailed','retry','send','sent','stale','sections',
    'gone','note','order','go','view','orderAlert',
    // Lot 24: card of an operator.
    'operator','write','writeTo','lastMessage','noPosition',
    // Lot 24: cards of a point and of an order.
    'point','onSite','writePco','pcoTitle',
    // Lot 24: status in one touch, arrival detected.
    'myStatus','noStatus','statusSent','statusCurrent','arrivalTitle','arrivalAsk','yes','later',
    // Lot 24: quick messages.
    'quick',
    // Lot 24: « Signal entendu ici » (SATER).
    'heard','heardHelp','heardSent','heardCancelled',
    // Lot 24: remotes of relays.
    'remotes','remoteOn','remoteOff','remoteParked','remoteSent','remoteTitle'])k:S.t('car.$k'),
  for(final st in carStatuses)'status.$st':S.t('car.status.$st'),
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
    // Lot 24: my status (first row of the Équipe tab).
    'me':{'status':i.field?.myStatus(i.devices[i.me])},
    // Lot 24 (card « Signal entendu ici »): button shown during a SATER
    // event only; usable with a position.
    if(carSater(i.settings))'sater':{'ready':i.here!=null},
    // Lot 24: remotes declared on this device, the last text to read aloud
    // (answer of a box), within a minute.
    if(i.field!=null)'remotes':carRemotes(i.field!.remotes.remotes),
    if(i.field?.said!=null&&i.now.toUtc().difference(i.field!.said!.at)<const Duration(minutes:1))
      'say':{'id':i.field!.said!.id,'text':i.field!.said!.text},
    // Lot 24: weather and vigilance at the destinations fetched.
    if(i.field!=null)'weather':i.field!.weather.cards(i.now),
    // Lot 24: quick messages of the event.
    'quick':[for(final q in carQuickMessages(i.settings))
      {'text':q.text,'priority':q.priority,'prioLabel':_prioLabel(q.priority)}],
  };
}

/// What must reach the car at once (lot 20, card « Android Auto : l'écran
/// clignote… », choice 3): a new message, a new or answered order, a
/// distress, the language. Distances and ages are not in it: they wait
/// for the next write (at most every 15 s, see car_screen_channel.dart).
String carUrgentKey(Map<String,Object?> snapshot){
  List<Object?> list(String k)=>snapshot[k] is List?snapshot[k] as List:const [];
  return jsonEncode({
    'distress':snapshot['distress'],'lang':snapshot['lang'],'labels':snapshot['labels'],
    'messages':[for(final m in list('messages'))if(m is Map)[m['id'],m['body'],m['unread'],m['prio']]],
    'orders':[for(final o in list('orders'))if(o is Map)[o['id'],o['status'],o['title'],o['note'],o['near']]],
    'me':snapshot['me'],'say':snapshot['say'],
  });
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
  /// Operator a dictated message goes to (« Écrire », lot 24).
  String get to=>'${data['to']??''}'.trim();
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
      final o=carOrders(i).where((x)=>x.id==a.id).firstOrNull;
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
    case 'write':
      // « Écrire » of the card of an operator (lot 24): a direct message.
      if(a.to.isEmpty||a.to==i.me||a.text.isEmpty)return;
      await act.send(carDirectMessage(id:uuid.v4(),eventId:i.eventId,me:i.me,to:a.to,text:a.text,now:i.now));
    case 'writePco':
      // « Écrire au PCO » of the card of an order (lot 24).
      if(a.text.isEmpty)return;
      await act.send(carPcoMessage(id:uuid.v4(),i:i,text:a.text));
    case 'onSite':
      // « Je suis sur place » of the card of a point (lot 24): to the PCO,
      // with my position.
      final p=carPoints(i).where((x)=>x['id']==a.id).firstOrNull;
      if(p==null)return;
      await act.send(carPcoMessage(id:uuid.v4(),i:i,text:carOnSiteText('${p['title']}',i.here)));
    case 'status':
      // Status in one touch (lot 24); empty: no status.
      final st=a.status.isEmpty?null:a.status;
      if(st==null||carStatuses.contains(st))await i.field?.setStatus(st);
    case 'arrival':
      // « Oui » to « Vous êtes arrivé à … » (lot 24, card « arrivée
      // détectée », choice 3): the order arrived, my status « Sur place ».
      final o=carOrders(i).where((x)=>x.id==a.id).firstOrNull;
      if(o==null||!carOrderAnswerAllowed(o.status,'arrived'))return;
      await act.order(o,'arrived');
      await i.field?.setStatus('sur_place');
    case 'quick':
      // Quick message in one touch (lot 24): in a conversation, to whom
      // « Répondre » answers; in the card of an order, to the PCO.
      final q=carQuickOf(a.data);
      if(q==null)return;
      if(a.conversation.isNotEmpty){
        final c=carConversations(i)[a.conversation];
        if(c==null)return;
        final to=carReplyTarget(a.conversation,c,i.me);
        if(to==null)return;
        await act.send(carDirectMessage(id:uuid.v4(),eventId:i.eventId,me:i.me,to:to,text:q.text,now:i.now,priority:q.priority));
      }else{
        await act.send(carPcoMessage(id:uuid.v4(),i:i,text:q.text,priority:q.priority));
      }
    case 'heard':
      // « Signal entendu ici » (lot 24): position, heading, time; nothing
      // to type. Sent even if the PCO turned the setting off meanwhile:
      // a signal heard is never lost (server rule).
      final here=i.here, f=i.field;
      if(here==null||f==null)return;
      final mine=i.positions.where((p)=>p.deviceId==i.me&&!p.isAprs).fold<SarcadePosition?>(null,(best,p)=>best==null||p.time.isAfter(best.time)?p:best);
      final heardAt=a.data['at'] is num?DateTime.fromMillisecondsSinceEpoch((a.data['at'] as num).toInt(),isUtc:true):i.now;
      await f.sendListening(id:a.id,at:here,heardAt:heardAt,headingDeg:mine?.headingDeg,speedMps:mine?.speedMps,accuracyM:mine?.accuracyM);
    case 'heardCancel':
      await i.field?.cancelListening(a.id);
    case 'go':
      // « Y aller » towards the point of an order (lot 24, card « heure
      // d'arrivée estimée »): its ETA is followed and sent to the PCO.
      if(carOrders(i).any((o)=>o.id==a.id))i.field?.followEta(a.id);
    case 'remote':
      // Remote of relays (lot 24): confirmed in the car (and stopped when
      // Android Auto tells the speed).
      final relay=a.data['relay'], on=a.data['on'];
      if(relay is! num||on is! bool)return;
      await i.field?.remotes.command(a.id,relay.toInt(),on,now:i.now);
    case 'weather':
      // Card of a point or an order opened (lot 24): its forecast, fetched
      // without waiting (the car redraws the card when it comes).
      final lat=a.data['lat'], lon=a.data['lon'];
      if(lat is num&&lon is num)unawaited(i.field?.weather.want(lat.toDouble(),lon.toDouble(),i.now));
    case 'sos':
      if(!i.inDistress)await act.sos();
    case 'sosEnd':
      if(i.inDistress)await act.sosEnd();
  }
}

/// A message dictated in the car to one operator (« Écrire », lot 24):
/// routine, direct, as a message written on the phone to that person.
SarcadeMessage carDirectMessage({required String id,required String eventId,required String me,required String to,
    required String text,required DateTime now,String priority='routine'})=>SarcadeMessage(
  id:id,eventId:eventId,senderId:me,recipientIds:['user:$to'],priority:priority,body:text.trim(),createdAt:now.toUtc());

/// Who « Écrire au PCO » and « Je suis sur place » go to (lot 24): the PCO
/// channel of the event, else the PCO terminals known, else everyone.
List<String> carPcoRecipients(CarScreenInput i){
  final channel=i.groups.values.where((g)=>g.kind=='default'&&g.name=='PCO'&&!g.archived).firstOrNull;
  if(channel!=null)return [channel.recipientId];
  final pco={for(final id in [...i.devices.keys,for(final p in i.positions)if(!p.isAprs)p.deviceId])if(id!=i.me&&isPco(id))id}.toList()..sort();
  return [for(final id in pco)'user:$id'];
}

/// A message dictated or sent from the car to the PCO (lot 24), routine.
SarcadeMessage carPcoMessage({required String id,required CarScreenInput i,required String text,String priority='routine'})=>SarcadeMessage(
  id:id,eventId:i.eventId,senderId:i.me,recipientIds:carPcoRecipients(i),priority:priority,body:text.trim(),createdAt:i.now.toUtc());

/// « Je suis sur place : P2 (48.81910, 1.92100) ».
String carOnSiteText(String point,LatLng? here)=>here==null
  ?S.t('car.onSiteNoPos',{'point':point})
  :S.t('car.onSiteBody',{'point':point,'pos':'${here.latitude.toStringAsFixed(5)}, ${here.longitude.toStringAsFixed(5)}'});

/// A quick message of the car (lot 24, card « Android Auto : messages
/// types en un appui »).
typedef CarQuick=({String text,String priority});

/// Quick messages at most (setting `car_quick_messages`, server lot 24).
const carQuickMax=4;

/// « Bien reçu », « J'arrive », « Besoin d'aide » (urgent, not a
/// distress), « Retard » when the PCO set nothing (choices 1 and 3).
List<CarQuick> carQuickDefaults()=>[
  (text:S.t('car.quick.received'),priority:'routine'),(text:S.t('car.quick.coming'),priority:'routine'),
  (text:S.t('car.quick.help'),priority:'urgent'),(text:S.t('car.quick.late'),priority:'routine'),
];

/// One quick message read from the settings or an action of the car; null
/// when damaged (1 to 40 characters, routine or urgent).
CarQuick? carQuickOf(Object? j){
  if(j is! Map)return null;
  final text='${j['text']??''}'.trim(), priority='${j['priority']??'routine'}';
  if(text.isEmpty||text.length>40||!const {'routine','urgent'}.contains(priority))return null;
  return (text:text,priority:priority);
}

/// Quick messages of the event (choice 2: set by the PCO in the settings
/// of the event, 4 at most), else the defaults.
List<CarQuick> carQuickMessages(Map<String,dynamic> settings){
  final raw=settings['car_quick_messages'];
  if(raw is! List)return carQuickDefaults();
  final list=[for(final j in raw)?carQuickOf(j)].take(carQuickMax).toList();
  return list.isEmpty?carQuickDefaults():list;
}

/// SATER event (setting `sater`, server lot 24): the car shows « Signal
/// entendu ici ».
bool carSater(Map<String,dynamic> settings)=>settings['sater']==true;

/// Every few seconds while the car shows SARCADE (lot 24): the estimated
/// time of arrival of the order followed since « Y aller ».
Future<void> carFieldTick(CarScreenInput i) async {
  final f=i.field;
  if(f==null)return;
  // Lot 24: answers of the boxes of the remotes, read aloud.
  f.remotes.check();
  // Lot 24: vigilance at the destination of the accepted orders.
  unawaited(f.weather.watch([for(final o in carOrders(i))if(o.status=='accepted')
    (id:o.id,lat:o.destination.latitude,lon:o.destination.longitude)],i.now));
  final id=f.etaOrder;
  final o=id==null?null:i.orders.where((x)=>x.id==id).firstOrNull;
  // Order gone: stop; orders not read yet: wait.
  final status=o?.status??(id!=null&&i.orders.isEmpty?'unknown':null);
  await f.etaTick(status:status,destination:o?.destination,here:i.here);
}
