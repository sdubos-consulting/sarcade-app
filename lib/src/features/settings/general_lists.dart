/// Lists opened from Paramètres › Général (card « Paramètres › Général :
/// onglet compact », validated on 5 Nov 2026, choices 2 and 3): the
/// remembered servers (choose, add, rename, forget) and the events of the
/// server (state in a pill, « Créer un événement » on top, pulled down to
/// refresh). Each returns what was chosen; Général asks the confirmation
/// and applies it.
library;

import 'package:flutter/material.dart';

import '../../config/saved_servers.dart';
import '../../l10n/strings.dart';
import '../../ui/menu_entry.dart';
import '../../ui/setting_line.dart';
import '../events/event_choice.dart' show eventName;

/// Value returned by [ServerListPage] for « Ajouter un serveur ».
const addServerChoice='\u0000add-server';

class ServerListPage extends StatefulWidget {
  final List<SavedServer> servers;
  final String current;
  /// Rename or forget: the new list.
  final Future<List<SavedServer>?> Function(SavedServer) rename, remove;
  final bool Function(SavedServer) canRemove;
  final String Function(SavedServer) label;
  const ServerListPage({super.key,required this.servers,required this.current,required this.rename,required this.remove,required this.canRemove,required this.label});
  @override State<ServerListPage> createState()=>_ServerListPageState();
}

class _ServerListPageState extends State<ServerListPage> {
  late List<SavedServer> _servers=widget.servers;

  @override Widget build(BuildContext context){
    final t=Theme.of(context); final s=t.colorScheme;
    final current=serverKey(widget.current);
    final known=_servers.any((x)=>serverKey(x.url)==current);
    return Scaffold(
      appBar:AppBar(title:Text(S.t('servers.saved'))),
      body:ListView(padding:const EdgeInsets.symmetric(horizontal:16),children:[
        ListTile(key:const ValueKey('server-add'),contentPadding:EdgeInsets.zero,
          leading:Icon(Icons.add,color:s.primary),title:Text(S.t('servers.add'),style:TextStyle(color:s.primary)),
          onTap:()=>Navigator.pop(context,addServerChoice)),
        const Divider(height:1),
        if(!known&&widget.current.isNotEmpty)ListTile(contentPadding:EdgeInsets.zero,
          leading:Icon(Icons.check,color:s.primary),title:Text(defaultLabel(widget.current)),subtitle:Text(S.t('servers.newHelp')),
          onTap:()=>Navigator.pop(context)),
        for(final x in _servers)ListTile(key:ValueKey('server-${x.url}'),contentPadding:EdgeInsets.zero,
          leading:serverKey(x.url)==current?Icon(Icons.check,color:s.primary):const SizedBox(width:24),
          title:Text(widget.label(x)),
          subtitle:x.label.toLowerCase().contains(x.shortAddress.toLowerCase())?null:Text(x.shortAddress),
          onTap:()=>Navigator.pop(context,x.url),
          trailing:PopupMenuButton<String>(tooltip:S.t('common.more'),icon:const Icon(Icons.more_vert),
            onSelected:(v) async {
              final list=v=='rename'?await widget.rename(x):await widget.remove(x);
              if(list!=null&&mounted)setState(()=>_servers=list);
            },
            itemBuilder:(c)=>[
              PopupMenuItem(value:'rename',child:menuEntry(c,icon:Icons.edit_outlined,color:s.primary,title:S.t('servers.rename'))),
              if(widget.canRemove(x))PopupMenuItem(value:'remove',child:menuEntry(c,icon:Icons.delete_outline,color:s.error,title:S.t('servers.remove'))),
            ])),
      ]),
    );
  }
}

/// « Brouillon », « Actif », « Clos » in a pill of its colour.
Widget eventStatePill(Object? status){
  final text=S.t('eventState.$status');
  final shown=text.isEmpty?text:text[0].toUpperCase()+text.substring(1);
  final color=switch('$status'){'active'=>Colors.green.shade700,'closed'=>Colors.grey.shade600,_=>Colors.orange.shade800};
  return SettingPill(shown,key:ValueKey('event-state-$status'),color:color);
}

class EventListPage extends StatefulWidget {
  final List<Map<String,dynamic>> events;
  final String current;
  /// Fresh list (pulled down or the refresh button), with a note when it
  /// could not be read (offline, error).
  final Future<(List<Map<String,dynamic>>,String?)> Function() reload;
  final String? note;
  /// « Créer un événement » (PCO): the id of the new event.
  final Future<String?> Function()? create;
  const EventListPage({super.key,required this.events,required this.current,required this.reload,this.note,this.create});
  @override State<EventListPage> createState()=>_EventListPageState();
}

class _EventListPageState extends State<EventListPage> {
  late List<Map<String,dynamic>> _events=widget.events;
  late String? _note=widget.note;
  bool _loading=false;

  Future<void> _refresh() async {
    setState(()=>_loading=true);
    try{
      final (list,note)=await widget.reload();
      if(mounted)setState((){_events=list;_note=note;});
    }finally{
      if(mounted)setState(()=>_loading=false);
    }
  }

  static String _date(Object? v){
    final t=DateTime.tryParse('${v??''}')?.toLocal();
    if(t==null)return '';
    String two(int x)=>x.toString().padLeft(2,'0');
    return '${two(t.day)}/${two(t.month)}';
  }

  @override Widget build(BuildContext context){
    final t=Theme.of(context); final s=t.colorScheme;
    final ids=_events.map((e)=>'${e['id']}').toSet();
    return Scaffold(
      appBar:AppBar(title:Text(S.t('settings.eventRow')),actions:[
        _loading
          ?const Padding(padding:EdgeInsets.all(14),child:SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)))
          :IconButton(key:const ValueKey('events-refresh'),tooltip:S.t('settings.eventsRefresh'),onPressed:_refresh,icon:const Icon(Icons.refresh)),
      ]),
      body:RefreshIndicator(onRefresh:_refresh,child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.symmetric(horizontal:16),children:[
        if(widget.create!=null)...[
          ListTile(key:const ValueKey('event-new'),contentPadding:EdgeInsets.zero,
            leading:Icon(Icons.add,color:s.primary),title:Text(S.t('general.createEvent'),style:TextStyle(color:s.primary)),
            onTap:() async {
              final id=await widget.create!();
              if(id!=null&&context.mounted)Navigator.pop(context,id);
            }),
          const Divider(height:1),
        ],
        Padding(padding:const EdgeInsets.fromLTRB(0,8,0,4),child:Text(_note??S.t('general.pullToRefresh'),
          style:t.textTheme.bodySmall?.copyWith(color:_note!=null?Colors.deepOrange:s.onSurfaceVariant))),
        if(_events.isEmpty&&_note==null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(S.t('settings.eventsEmpty'))),
        if(widget.current.isNotEmpty&&!ids.contains(widget.current))ListTile(contentPadding:EdgeInsets.zero,
          leading:Icon(Icons.check,color:s.primary),title:Text(S.t('settings.eventUnlisted',{'id':widget.current})),
          onTap:()=>Navigator.pop(context)),
        for(final e in _events)ListTile(key:ValueKey('event-item-${e['id']}'),contentPadding:EdgeInsets.zero,
          leading:'${e['id']}'==widget.current?Icon(Icons.check,color:s.primary):const SizedBox(width:24),
          title:Text(eventName(e)),
          subtitle:_date(e['created_at']).isEmpty?null:Text(_date(e['created_at'])),
          trailing:eventStatePill(e['status']),
          onTap:()=>Navigator.pop(context,'${e['id']}')),
      ])),
    );
  }
}
