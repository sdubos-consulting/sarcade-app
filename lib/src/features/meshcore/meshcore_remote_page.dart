/// Screens of the remote control of relays (lot 19, card « MeshCore :
/// télécommande de relais », mock-up « meshcore-telecommande-maurepas »
/// validated on 1 Nov 2026, 22 h 07): the list in Outils › MeshCore, the
/// declaration (PCO), and the remote itself: per relay « Allumer » /
/// « Éteindre », a confirmation recalling the code, the answer of the box
/// (« confirmé par le boîtier » or « pas de confirmation » and
/// « Renvoyer »), the last confirmed state marked « supposé », and the
/// logbook lines.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/comm_group.dart' show isPco, myActorId;
import '../../ui/link_status.dart';
import '../../ui/overlay_page.dart';
import 'meshcore_link.dart';
import 'meshcore_page.dart' show meshCoreAge;
import 'meshcore_protocol.dart';
import 'meshcore_remote.dart';

/// Declaring or changing a remote: the PCO only; using it: every operator.
bool meshCoreRemoteCanDeclare([String? actor])=>isPco(actor??myActorId??'');

String _hm(DateTime t){String two(int v)=>v.toString().padLeft(2,'0');return '${two(t.hour)}:${two(t.minute)}';}

/// Word of the chip of a relay: « Allumé », « Éteint », « Inconnu »,
/// « En attente », « Pas de confirmation », « Échec ».
String meshCoreRelayChip(MeshCoreRelayState s)=>switch(s.status){
  MeshCoreRelayStatus.waiting=>S.t('remote.chip.waiting'),
  MeshCoreRelayStatus.noConfirmation=>S.t('remote.chip.noConfirmation'),
  MeshCoreRelayStatus.failed=>S.t('remote.chip.failed'),
  _=>S.t(s.on==null?'remote.chip.unknown':s.on!?'remote.chip.on':'remote.chip.off'),
};

/// « Allumer » / « Éteindre ».
String meshCoreRelayVerb(bool on)=>S.t(on?'remote.on':'remote.off');

/// Lines under the name of a relay.
List<String> meshCoreRelayDetail(MeshCoreRelayState s){
  final cmd=s.command==null?'':meshCoreRelayVerb(s.command!), at=s.sentAt==null?'':_hm(s.sentAt!);
  final last=s.on==null||s.confirmedAt==null?null:S.t(s.on!?'remote.lastOn':'remote.lastOff',{'time':_hm(s.confirmedAt!)});
  return switch(s.status){
    MeshCoreRelayStatus.waiting=>[S.t('remote.detail.waiting',{'cmd':cmd,'time':at}),?last],
    MeshCoreRelayStatus.noConfirmation=>[[S.t('remote.detail.sent',{'cmd':cmd,'time':at}),if(s.delivered)S.t('mesh.msg.delivered'),
      S.t('remote.detail.noAnswer')].join(' · '),?last],
    MeshCoreRelayStatus.failed=>[S.t('remote.detail.failed',{'cmd':cmd}),?last],
    _=>s.on==null||s.confirmedAt==null?[S.t('remote.detail.none')]:[
      S.t('remote.detail.confirmed',{'time':_hm(s.confirmedAt!)}),if((s.reply??'').isNotEmpty)s.reply!],
  };
}

Color meshCoreRelayChipColor(MeshCoreRelayState s)=>switch(s.status){
  MeshCoreRelayStatus.waiting=>Colors.blue.shade700,
  MeshCoreRelayStatus.noConfirmation=>Colors.orange.shade800,
  MeshCoreRelayStatus.failed=>Colors.red.shade700,
  _=>s.on==true?Colors.green.shade700:Colors.blueGrey,
};

Future<void> openMeshCoreRemotes(BuildContext context)=>showOverlayPage<void>(context,(_)=>const MeshCoreRemotesPage());
Future<void> openMeshCoreRemote(BuildContext context,MeshCoreRemote r)=>showOverlayPage<void>(context,(_)=>MeshCoreRemotePage(remoteId:r.id));
Future<void> editMeshCoreRemote(BuildContext context,{MeshCoreRemote? remote})=>showOverlayPage<void>(context,(_)=>MeshCoreRemoteEditPage(remote:remote));

/// « Allumer Relais 1 ? Message 1111# envoyé au boîtier par MeshCore.
/// Réponse attendue en moins de 30 s. »
Future<bool> confirmMeshCoreCommand(BuildContext context,MeshCoreRelay relay,bool on) async {
  final code=on?relay.onCode:relay.offCode;
  final parts=S.t('remote.confirm.body').split('{code}');
  final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
    title:Text(S.t(on?'remote.confirm.on':'remote.confirm.off',{'relay':relay.name})),
    content:Text.rich(TextSpan(children:[
      TextSpan(text:parts.first),
      TextSpan(text:code,style:const TextStyle(fontFamily:'monospace',fontWeight:FontWeight.w700)),
      if(parts.length>1)TextSpan(text:parts.sublist(1).join(code)),
    ]),key:const ValueKey('remote-confirm-body')),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
      FilledButton(key:const ValueKey('remote-confirm-send'),onPressed:()=>Navigator.pop(c,true),child:Text(meshCoreRelayVerb(on))),
    ]));
  return ok==true;
}

/// Card of Outils › MeshCore: the remotes of relays.
class MeshCoreRemotesTile extends StatelessWidget {
  const MeshCoreRemotesTile({super.key});
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:Listenable.merge([MeshCoreRemotes.instance,MeshCoreLink.instance]),builder:(context,_){
    final all=MeshCoreRemotes.instance.remotes;
    if(!MeshCoreLink.instance.remembered&&all.isEmpty)return const SizedBox.shrink();
    return Card(key:const ValueKey('remote-tile'),child:ListTile(leading:const Icon(Icons.settings_remote),
      title:Text(S.t('remote.title')),
      subtitle:Text(all.isEmpty?S.t('remote.none'):all.map((r)=>r.name).join(' · '),maxLines:2,overflow:TextOverflow.ellipsis),
      trailing:const Icon(Icons.chevron_right),
      onTap:()=>unawaited(all.length==1?openMeshCoreRemote(context,all.single):openMeshCoreRemotes(context))));
  });
}

/// List of the remotes, « Déclarer une télécommande » for the PCO.
class MeshCoreRemotesPage extends StatelessWidget {
  const MeshCoreRemotesPage({super.key});
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:MeshCoreRemotes.instance,builder:(context,_){
    final all=MeshCoreRemotes.instance.remotes, pco=meshCoreRemoteCanDeclare(), t=Theme.of(context);
    return Scaffold(appBar:LinkedAppBar(title:Text(S.t('remote.title'))),
      body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:760),child:ListView(padding:const EdgeInsets.all(16),children:[
        if(all.isEmpty)Padding(padding:const EdgeInsets.all(4),child:Text(S.t('remote.none'))),
        for(final r in all)Card(child:ListTile(key:ValueKey('remote-${r.id}'),leading:const Icon(Icons.settings_remote),
          title:Text(r.name),subtitle:Text([r.nodeName.isEmpty?meshCorePrefix(r.nodeKey):r.nodeName,S.t('remote.relays',{'n':r.relays.length})].join(' · ')),
          trailing:pco?IconButton(tooltip:S.t('remote.edit'),onPressed:()=>unawaited(editMeshCoreRemote(context,remote:r)),icon:const Icon(Icons.edit_outlined)):null,
          onTap:()=>unawaited(openMeshCoreRemote(context,r)))),
        const SizedBox(height:12),
        if(pco)Align(alignment:Alignment.centerLeft,child:FilledButton.icon(key:const ValueKey('remote-declare'),
          onPressed:()=>unawaited(editMeshCoreRemote(context)),icon:const Icon(Icons.add),label:Text(S.t('remote.declare'))))
        else Text(S.t('remote.pcoOnly'),style:t.textTheme.bodySmall),
        Padding(padding:const EdgeInsets.only(top:12),child:Text(S.t('remote.local'),style:t.textTheme.bodySmall)),
      ]))));
  });
}

/// The remote (mock-up): one card per relay, the logbook lines below.
class MeshCoreRemotePage extends StatelessWidget {
  final String remoteId;
  const MeshCoreRemotePage({super.key,required this.remoteId});

  Future<void> _send(BuildContext context,MeshCoreRemote r,int i,bool on) async {
    if(!await confirmMeshCoreCommand(context,r.relays[i],on))return;
    await MeshCoreRemotes.instance.command(r,i,on);
  }

  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:Listenable.merge([MeshCoreRemotes.instance,MeshCoreLink.instance]),builder:(context,_){
    final remotes=MeshCoreRemotes.instance, link=MeshCoreLink.instance, t=Theme.of(context);
    final r=remotes.byId(remoteId);
    if(r==null)return Scaffold(appBar:LinkedAppBar(title:Text(S.t('remote.title'))),body:Center(child:Text(S.t('remote.gone'))));
    final states=remotes.states(r), now=DateTime.now();
    final heard=link.contactOf(r.nodeKey)?.lastAdvert;
    final connected=link.state==MeshCoreState.connected;
    final banner=connected?[S.t('remote.moduleOn'),if(heard!=null)S.t('remote.heard',{'age':meshCoreAge(heard,now)})].join(' · ')
      :S.t('mesh.chat.noModule');
    final small=t.textTheme.bodySmall;
    final logLines=remotes.logOf(r.id).take(20).toList();
    return Scaffold(
      appBar:LinkedAppBar(title:Text(r.name),actions:[
        if(meshCoreRemoteCanDeclare())IconButton(tooltip:S.t('remote.edit'),onPressed:()=>unawaited(editMeshCoreRemote(context,remote:r)),icon:const Icon(Icons.edit_outlined)),
      ]),
      body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:560),child:ListView(padding:const EdgeInsets.all(16),children:[
        Text(S.t('remote.subtitle',{'node':r.nodeName.isEmpty?meshCorePrefix(r.nodeKey):r.nodeName}),style:t.textTheme.titleSmall),
        const SizedBox(height:10),
        Container(key:const ValueKey('remote-banner'),padding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
          decoration:BoxDecoration(color:(connected?Colors.green:Colors.orange).withValues(alpha:0.15),borderRadius:BorderRadius.circular(12)),
          child:Row(children:[
            Icon(Icons.circle,size:10,color:connected?Colors.green.shade600:Colors.orange.shade800),const SizedBox(width:10),
            Expanded(child:Text(banner)),
          ])),
        for(var i=0;i<r.relays.length;i++)Card(key:ValueKey('remote-relay-$i'),margin:const EdgeInsets.only(top:12),child:Padding(padding:const EdgeInsets.all(14),
          child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            Row(children:[
              Expanded(child:Text(r.relays[i].name,style:t.textTheme.titleMedium)),
              Container(key:ValueKey('remote-chip-$i'),padding:const EdgeInsets.symmetric(horizontal:10,vertical:3),
                decoration:BoxDecoration(color:meshCoreRelayChipColor(states[i]).withValues(alpha:0.15),borderRadius:BorderRadius.circular(20)),
                child:Text(meshCoreRelayChip(states[i]),style:TextStyle(color:meshCoreRelayChipColor(states[i]),fontWeight:FontWeight.w600))),
            ]),
            const SizedBox(height:4),
            for(final line in meshCoreRelayDetail(states[i]))Text(line,style:small),
            const SizedBox(height:10),
            Row(children:[
              Expanded(child:FilledButton(key:ValueKey('remote-on-$i'),style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(48),
                backgroundColor:states[i].on==true&&states[i].status==MeshCoreRelayStatus.confirmed?Colors.green.shade700:null),
                onPressed:states[i].status==MeshCoreRelayStatus.waiting?null:()=>unawaited(_send(context,r,i,true)),child:Text(S.t('remote.on')))),
              const SizedBox(width:10),
              Expanded(child:FilledButton.tonal(key:ValueKey('remote-off-$i'),style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(48)),
                onPressed:states[i].status==MeshCoreRelayStatus.waiting?null:()=>unawaited(_send(context,r,i,false)),child:Text(S.t('remote.off')))),
            ]),
            if((states[i].status==MeshCoreRelayStatus.noConfirmation||states[i].status==MeshCoreRelayStatus.failed)&&states[i].command!=null)
              Padding(padding:const EdgeInsets.only(top:6),child:Center(child:TextButton.icon(key:ValueKey('remote-resend-$i'),
                style:TextButton.styleFrom(foregroundColor:Colors.orange.shade800),
                onPressed:()=>unawaited(_send(context,r,i,states[i].command!)),icon:const Icon(Icons.refresh),
                label:Text(S.t('remote.resend',{'cmd':meshCoreRelayVerb(states[i].command!)}))))),
          ]))),
        Padding(padding:const EdgeInsets.fromLTRB(4,12,4,0),child:Text(S.t('remote.restartNote'),style:small)),
        Card(key:const ValueKey('remote-log'),margin:const EdgeInsets.only(top:16),child:Padding(padding:const EdgeInsets.all(14),child:Column(
          crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            Text(S.t('remote.logbook'),style:t.textTheme.titleSmall),
            const SizedBox(height:4),
            if(logLines.isEmpty)Text(S.t('remote.logEmpty'),style:small),
            for(final e in logLines)Padding(padding:const EdgeInsets.only(top:2),
              child:Text([_hm(e.at),if(e.actor.isNotEmpty)e.actor,e.text].join(' · '))),
            Padding(padding:const EdgeInsets.only(top:6),child:Text(S.t('remote.logLocal'),style:small)),
          ]))),
      ]))));
  });
}

/// Declaration of a remote (PCO): name, the box's companion chosen among
/// the nodes, 1 to 4 relays, their names and codes (filled in by
/// themselves, editable).
class MeshCoreRemoteEditPage extends StatefulWidget {
  final MeshCoreRemote? remote;
  const MeshCoreRemoteEditPage({super.key,this.remote});
  @override State<MeshCoreRemoteEditPage> createState()=>_MeshCoreRemoteEditPageState();
}

class _RelayFields {
  final TextEditingController name, on, off;
  _RelayFields(MeshCoreRelay r):name=TextEditingController(text:r.name),on=TextEditingController(text:r.onCode),off=TextEditingController(text:r.offCode);
  void dispose(){name.dispose();on.dispose();off.dispose();}
}

class _MeshCoreRemoteEditPageState extends State<MeshCoreRemoteEditPage> {
  late final TextEditingController _name;
  String? _node;
  final List<_RelayFields> _relays=[];
  String? _error;

  @override void initState(){
    super.initState();
    final r=widget.remote;
    // The first box declared is the one of Maurepas (1 Nov 2026, 22 h 07).
    _name=TextEditingController(text:r?.name??(MeshCoreRemotes.instance.remotes.isEmpty?S.t('remote.firstName'):''));
    _node=r?.nodeKey;
    for(final x in r?.relays??[MeshCoreRelay.numbered(1)]){_relays.add(_RelayFields(x));}
  }

  @override void dispose(){_name.dispose();for(final f in _relays){f.dispose();}super.dispose();}

  void _count(int n){
    setState((){
      while(_relays.length<n){_relays.add(_RelayFields(MeshCoreRelay.numbered(_relays.length+1)));}
      while(_relays.length>n){_relays.removeLast().dispose();}
    });
  }

  Future<void> _save() async {
    final name=_name.text.trim(), node=_node;
    final codes=[for(final f in _relays)...[f.on.text.trim(),f.off.text.trim()]];
    String? error;
    if(name.isEmpty){error=S.t('remote.error.name');}
    else if(node==null){error=S.t('remote.error.node');}
    else if(_relays.any((f)=>f.name.text.trim().isEmpty)||codes.any((c)=>!meshCoreTextFits(c))){error=S.t('remote.error.codes');}
    if(error!=null){setState(()=>_error=error);return;}
    final remotes=MeshCoreRemotes.instance;
    final contact=MeshCoreLink.instance.contactOf(node!);
    final r=MeshCoreRemote(id:widget.remote?.id??remotes.newId(DateTime.now()),name:name,nodeKey:contact?.key??node,
      nodeName:contact?.name??widget.remote?.nodeName??'',
      relays:[for(final f in _relays)MeshCoreRelay(name:f.name.text.trim(),onCode:f.on.text.trim(),offCode:f.off.text.trim())]);
    final nav=Navigator.of(context);
    await remotes.put(r);
    if(mounted)nav.pop();
  }

  Future<void> _delete() async {
    final r=widget.remote; if(r==null)return;
    final nav=Navigator.of(context);
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(S.t('remote.deleteAsk',{'name':r.name})),actions:[
      TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
      FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('common.delete'))),
    ]));
    if(ok!=true)return;
    await MeshCoreRemotes.instance.remove(r.id);
    if(mounted)nav.pop();
  }

  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    if(!meshCoreRemoteCanDeclare()){
      return Scaffold(appBar:LinkedAppBar(title:Text(S.t('remote.declare'))),body:Center(child:Text(S.t('remote.pcoOnly'))));
    }
    final companions=MeshCoreLink.instance.contacts.where((c)=>c.kind=='companion').toList();
    final keys={for(final c in companions)c.key:c.name.isEmpty?c.shortKey:c.name};
    if(_node!=null&&!keys.keys.any((k)=>meshCorePrefix(k)==meshCorePrefix(_node!))){
      keys[_node!]=widget.remote?.nodeName.isNotEmpty==true?widget.remote!.nodeName:meshCorePrefix(_node!);
    }
    final selected=_node==null?null:keys.keys.firstWhere((k)=>meshCorePrefix(k)==meshCorePrefix(_node!));
    return Scaffold(
      appBar:LinkedAppBar(title:Text(widget.remote==null?S.t('remote.declare'):S.t('remote.edit')),actions:[
        if(widget.remote!=null)IconButton(tooltip:S.t('common.delete'),onPressed:()=>unawaited(_delete()),icon:const Icon(Icons.delete_outline)),
      ]),
      body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:640),child:ListView(padding:const EdgeInsets.all(16),children:[
        TextField(key:const ValueKey('remote-name'),controller:_name,decoration:InputDecoration(labelText:S.t('remote.name'),
          hintText:S.t('remote.firstName'),border:const OutlineInputBorder())),
        const SizedBox(height:14),
        if(keys.isEmpty)Text(S.t('remote.noCompanion'),style:TextStyle(color:t.colorScheme.error))
        else DropdownButtonFormField<String>(key:const ValueKey('remote-node'),initialValue:selected,isExpanded:true,
          decoration:InputDecoration(labelText:S.t('remote.node'),border:const OutlineInputBorder()),
          items:[for(final e in keys.entries)DropdownMenuItem(value:e.key,child:Text(e.value,overflow:TextOverflow.ellipsis))],
          onChanged:(v)=>setState(()=>_node=v)),
        const SizedBox(height:14),
        Text(S.t('remote.count'),style:t.textTheme.titleSmall),
        const SizedBox(height:6),
        SegmentedButton<int>(key:const ValueKey('remote-count'),segments:[for(var n=1;n<=meshCoreRemoteMaxRelays;n++)ButtonSegment(value:n,label:Text('$n'))],
          selected:{_relays.length},onSelectionChanged:(s)=>_count(s.first)),
        for(var i=0;i<_relays.length;i++)Card(margin:const EdgeInsets.only(top:12),child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
          TextField(key:ValueKey('remote-relay-name-$i'),controller:_relays[i].name,decoration:InputDecoration(labelText:S.t('remote.relayName'),border:const OutlineInputBorder())),
          const SizedBox(height:8),
          Row(children:[
            Expanded(child:TextField(key:ValueKey('remote-code-on-$i'),controller:_relays[i].on,decoration:InputDecoration(labelText:S.t('remote.codeOn'),border:const OutlineInputBorder()))),
            const SizedBox(width:8),
            Expanded(child:TextField(key:ValueKey('remote-code-off-$i'),controller:_relays[i].off,decoration:InputDecoration(labelText:S.t('remote.codeOff'),border:const OutlineInputBorder()))),
          ]),
        ]))),
        Padding(padding:const EdgeInsets.only(top:8),child:Text(S.t('remote.codesHelp'),style:t.textTheme.bodySmall)),
        if(_error!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(_error!,key:const ValueKey('remote-error'),style:TextStyle(color:t.colorScheme.error))),
        const SizedBox(height:16),
        Align(alignment:Alignment.centerRight,child:FilledButton.icon(key:const ValueKey('remote-save'),onPressed:()=>unawaited(_save()),
          icon:const Icon(Icons.check),label:Text(S.t('common.save')))),
      ]))));
  }
}
