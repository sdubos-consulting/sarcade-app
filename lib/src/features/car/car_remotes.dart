/// Remotes of relays from the car (lot 24, card « Android Auto :
/// télécommandes de relais depuis la voiture »): the remotes declared in
/// the application (Outils › Télécommandes, lot 21), unchanged, used from
/// the car:
/// 1. « Télécommandes » row at the bottom of the Points tab, list of the
///    remotes, card with Allumer / Éteindre for each relay;
/// 2. confirmation always (« Allumer Relais 1 de Maurepas ? »), and only
///    while the vehicle is stopped when Android Auto tells its speed (car
///    side, CarHardwareManager);
/// 3. the answer of the box read aloud;
/// 4. only the remotes declared in the application: nothing is declared
///    from the car.
library;

import '../../l10n/strings.dart';
import '../remotes/remote.dart';
import '../remotes/remotes_page.dart' show remoteRelayChip, remoteRelayDetail;

/// What the car shows of the remotes declared on this device.
List<Map<String,Object?>> carRemotes(Remotes remotes)=>[
  for(final r in remotes.remotes){
    'id':r.id,'title':r.name,
    'ready':remotes.ready(r),
    'text':[S.t('remote.relays',{'n':r.relays.length}),
      S.t(remotes.ready(r)?'car.remoteReady':'car.remoteDown',{'via':remoteTransportName(r.transport)})].join(' · '),
    'relays':[
      for(var k=0;k<r.relays.length;k++){
        'name':r.relays[k].name,
        'state':remoteRelayChip(remotes.states(r)[k]),
        'detail':remoteRelayDetail(remotes.states(r)[k],transport:r.transport).join(' · '),
        'on':remotes.states(r)[k].on,
        'ask.on':S.t('car.remoteAsk.on',{'relay':r.relays[k].name,'remote':r.name}),
        'ask.off':S.t('car.remoteAsk.off',{'relay':r.relays[k].name,'remote':r.name}),
      },
    ],
  },
];

/// Commands sent from the car, until the box answers (or not): then the
/// result is read aloud (choice 3).
class CarRemoteWatch {
  final Remotes remotes;
  /// Text to read aloud in the car.
  final void Function(String text) say;
  CarRemoteWatch(this.remotes,{required this.say});

  /// Commands awaited: remote, relay, time sent.
  final List<({String remote,int relay,DateTime sentAt})> _awaited=[];

  /// « Allumer » ([on]) or « Éteindre » relay [relay] of remote [id],
  /// confirmed in the car. False when the remote or the relay is unknown.
  Future<bool> command(String id,int relay,bool on,{DateTime? now}) async {
    final r=remotes.byId(id);
    if(r==null||relay<0||relay>=r.relays.length)return false;
    final at=now??DateTime.now();
    await remotes.command(r,relay,on,now:at);
    final sent=remotes.states(r)[relay].sentAt??at;
    _awaited.add((remote:id,relay:relay,sentAt:sent));
    check();
    return true;
  }

  /// Reads the states: a command answered, refused or not confirmed in
  /// 30 s gives the text read aloud.
  void check(){
    final done=<int>[];
    for(var k=0;k<_awaited.length;k++){
      final a=_awaited[k];
      final r=remotes.byId(a.remote);
      if(r==null||a.relay>=r.relays.length){done.add(k);continue;}
      final s=remotes.states(r)[a.relay];
      // A newer command replaced it: the newer one is awaited.
      if(s.sentAt!=a.sentAt){done.add(k);continue;}
      if(s.status==RemoteRelayStatus.waiting||s.status==RemoteRelayStatus.idle)continue;
      done.add(k);
      final log=remoteLogText(r.relays[a.relay].name,s.command??false,s.status);
      final reply=s.status==RemoteRelayStatus.confirmed&&(s.reply??'').isNotEmpty?S.t('car.remoteReply',{'text':s.reply}):'';
      say('${S.t('car.remoteSay',{'remote':r.name,'log':log})}$reply');
    }
    for(final k in done.reversed){_awaited.removeAt(k);}
  }
}
