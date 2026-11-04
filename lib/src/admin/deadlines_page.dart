import 'dart:async';
import 'package:flutter/material.dart';
import '../features/settings/diagnostics_levels.dart' show diagDay;
import '../l10n/strings.dart';
import 'admin_api.dart';
import 'admin_errors.dart';

/// « Échéances » typed by the administrator (lot 28, card « Diagnostic
/// administrateur : Échéances », point 3): name, date, link to the renewal
/// page, note; never the secret itself. The server detects the others.
class DeadlinesPage extends StatefulWidget {
  final AdminApi api;
  const DeadlinesPage({super.key,required this.api});
  @override State<DeadlinesPage> createState()=>_DeadlinesPageState();
}

class _DeadlinesPageState extends State<DeadlinesPage> {
  List<Map<String,dynamic>>? _items; String? _error; bool _saving=false, _dirty=false;

  @override void initState(){super.initState();unawaited(_load());}

  Future<void> _load() async {
    try{
      final d=await widget.api.deadlines();
      if(mounted)setState((){_items=[for(final x in (d['manual'] as List?)??const [])if(x is Map)Map<String,dynamic>.from(x)];_error=null;});
    }catch(e){if(mounted)setState(()=>_error=adminErrorText(e));}
  }

  Future<void> _save() async {
    final items=_items; if(items==null)return;
    setState(()=>_saving=true);
    final m=ScaffoldMessenger.of(context);
    try{
      final d=await widget.api.saveDeadlines(items);
      if(!mounted)return;
      setState((){_items=[for(final x in (d['manual'] as List?)??const [])if(x is Map)Map<String,dynamic>.from(x)];_dirty=false;});
      m.showSnackBar(SnackBar(content:Text(S.t('deadline.saved'))));
    }catch(e){
      m.showSnackBar(SnackBar(content:Text(adminErrorText(e))));
    }finally{
      if(mounted)setState(()=>_saving=false);
    }
  }

  Future<void> _edit([int? index]) async {
    final current=index==null?const <String,dynamic>{}:_items![index];
    final edited=await showDialog<Map<String,dynamic>>(context:context,builder:(_)=>DeadlineDialog(initial:current));
    if(edited==null||!mounted)return;
    setState((){
      final list=[...?_items];
      if(index==null){list.add(edited);}else{list[index]={...current,...edited};}
      _items=list;_dirty=true;
    });
  }

  void _remove(int index)=>setState((){_items=[...?_items]..removeAt(index);_dirty=true;});

  @override
  Widget build(BuildContext context){
    final t=Theme.of(context);
    final items=_items;
    return Scaffold(
      appBar:AppBar(title:Text(S.t('deadline.manualTitle'))),
      floatingActionButton:items==null?null:FloatingActionButton.extended(key:const ValueKey('deadline-add'),onPressed:()=>_edit(),
        icon:const Icon(Icons.add),label:Text(S.t('deadline.add'))),
      bottomNavigationBar:SafeArea(child:Padding(padding:const EdgeInsets.all(12),child:FilledButton(key:const ValueKey('deadline-save'),
        onPressed:_dirty&&!_saving?_save:null,child:Text(S.t('common.save'))))),
      body:_error!=null?Center(child:Padding(padding:const EdgeInsets.all(24),child:Text(_error!)))
        :items==null?const Center(child:CircularProgressIndicator())
        :ListView(padding:const EdgeInsets.fromLTRB(16,8,16,96),children:[
          Text(S.t('deadline.noSecret'),style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant)),
          for(var i=0;i<items.length;i++)ListTile(key:ValueKey('deadline-item-$i'),contentPadding:EdgeInsets.zero,
            title:Text('${items[i]['name']??''}'),
            subtitle:Text([items[i]['date']==null?S.t('deadline.noDate'):diagDay(items[i]['date']),
              if('${items[i]['note']??''}'.isNotEmpty)'${items[i]['note']}'].join(' · ')),
            onTap:()=>_edit(i),
            trailing:IconButton(tooltip:S.t('deadline.remove'),icon:const Icon(Icons.delete_outline),onPressed:()=>_remove(i))),
        ]),
    );
  }
}

/// One deadline: name, date (or none), renewal link, note.
class DeadlineDialog extends StatefulWidget {
  final Map<String,dynamic> initial;
  const DeadlineDialog({super.key,this.initial=const {}});
  @override State<DeadlineDialog> createState()=>_DeadlineDialogState();
}

class _DeadlineDialogState extends State<DeadlineDialog> {
  late final _name=TextEditingController(text:'${widget.initial['name']??''}');
  late final _url=TextEditingController(text:'${widget.initial['url']??''}');
  late final _note=TextEditingController(text:'${widget.initial['note']??''}');
  late DateTime? _date=DateTime.tryParse('${widget.initial['date']??''}');

  @override void dispose(){_name.dispose();_url.dispose();_note.dispose();super.dispose();}

  Future<void> _pick() async {
    final now=DateTime.now();
    final d=await showDatePicker(context:context,firstDate:DateTime(now.year-1),lastDate:DateTime(now.year+10),initialDate:_date??now);
    if(d!=null&&mounted)setState(()=>_date=d);
  }

  String _iso(DateTime d)=>'${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context)=>AlertDialog(scrollable:true,
    title:Text(S.t(widget.initial.isEmpty?'deadline.add':'deadline.editOne')),
    content:SizedBox(width:420,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      TextField(key:const ValueKey('deadline-name'),controller:_name,autofocus:widget.initial.isEmpty,decoration:InputDecoration(labelText:S.t('deadline.name'))),
      const SizedBox(height:12),
      Wrap(spacing:8,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
        Text(_date==null?S.t('deadline.noDate'):diagDay(_iso(_date!))),
        OutlinedButton.icon(key:const ValueKey('deadline-pick'),onPressed:_pick,icon:const Icon(Icons.event_outlined),label:Text(S.t('deadline.pickDate'))),
        if(_date!=null)TextButton(onPressed:()=>setState(()=>_date=null),child:Text(S.t('deadline.clearDate'))),
      ]),
      const SizedBox(height:12),
      TextField(key:const ValueKey('deadline-url'),controller:_url,keyboardType:TextInputType.url,autocorrect:false,
        decoration:InputDecoration(labelText:S.t('deadline.url'),hintText:'https://')),
      const SizedBox(height:12),
      TextField(key:const ValueKey('deadline-note'),controller:_note,decoration:InputDecoration(labelText:S.t('deadline.note'),helperText:S.t('deadline.noSecret'),helperMaxLines:2)),
    ])),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(context),child:Text(S.t('common.cancel'))),
      FilledButton(key:const ValueKey('deadline-ok'),onPressed:(){
        final name=_name.text.trim();
        if(name.isEmpty)return;
        Navigator.pop(context,<String,dynamic>{'name':name,'date':_date==null?null:_iso(_date!),
          'url':_url.text.trim().isEmpty?null:_url.text.trim(),'note':_note.text.trim().isEmpty?null:_note.text.trim()});
      },child:Text(S.t('common.ok'))),
    ]);
}
