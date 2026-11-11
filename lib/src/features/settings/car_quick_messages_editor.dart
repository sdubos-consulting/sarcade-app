/// Paramètres › Événement › Messages de la voiture (card « Android Auto :
/// messages types en un appui », lot 24, 3 Nov 2026, choice 2): 1 to 4
/// messages sent in one touch from the car, each with its priority
/// (« Routine » or « Urgent », never distress), set by the PCO; « Rétablir
/// les messages par défaut » sends `null` (default list of the server).
/// Setting `car_quick_messages`, distinct from `quick_messages` (phone).
library;

import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../ui/link_status.dart';

const maxCarQuickMessages=4;
const carQuickMessageMaxLength=40;

typedef CarQuickMessage=({String text,String priority});

/// Default list of the server (texts as stored by the server).
const defaultCarQuickMessages=<CarQuickMessage>[
  (text:'Bien reçu',priority:'routine'),(text:'J\'arrive',priority:'routine'),
  (text:'Besoin d\'aide',priority:'urgent'),(text:'Retard',priority:'routine'),
];

/// From `settings.car_quick_messages` (a plain text is a routine message);
/// the default list when absent or unreadable (older server).
List<CarQuickMessage> carQuickMessagesOf(Map<String,dynamic>? settings){
  final v=settings?['car_quick_messages'];
  if(v is! List)return defaultCarQuickMessages;
  final out=<CarQuickMessage>[
    for(final x in v)
      if(x is String)(text:x,priority:'routine')
      else if(x is Map&&x['text'] is String)(text:x['text'] as String,priority:x['priority']=='urgent'?'urgent':'routine'),
  ];
  return out.isEmpty?defaultCarQuickMessages:out;
}

/// Spaces reduced, as the server stores them.
String cleanCarText(String t)=>t.split(RegExp(r'\s+')).where((w)=>w.isNotEmpty).join(' ');

/// Null when the list can be saved, else the key of the problem: empty
/// text, too long, the same text twice, or too many.
String? carQuickMessagesProblem(List<CarQuickMessage> list){
  if(list.isEmpty||list.length>maxCarQuickMessages)return 'eventSettings.quickCar.count';
  final seen=<String>{};
  for(final m in list){
    final t=cleanCarText(m.text);
    if(t.isEmpty)return 'eventSettings.quickCar.empty';
    if(t.length>carQuickMessageMaxLength)return 'eventSettings.quickCar.tooLong';
    if(!seen.add(t.toLowerCase()))return 'eventSettings.quickCar.twice';
  }
  return null;
}

/// Body of PATCH …/settings for the list.
List<Map<String,String>> carQuickMessagesJson(List<CarQuickMessage> list)=>[for(final m in list){'text':cleanCarText(m.text),'priority':m.priority}];

/// What the editor gives back: a list to save, or the default list.
typedef CarQuickMessagesResult=({List<CarQuickMessage>? messages,bool reset});

class CarQuickMessagesEditor extends StatefulWidget {
  final List<CarQuickMessage> initial;
  const CarQuickMessagesEditor({super.key,required this.initial});
  @override State<CarQuickMessagesEditor> createState()=>_CarQuickMessagesEditorState();
}

class _CarQuickMessagesEditorState extends State<CarQuickMessagesEditor> {
  late final List<(TextEditingController,String)> _rows=[for(final m in widget.initial.take(maxCarQuickMessages))(TextEditingController(text:m.text),m.priority)];

  @override void dispose(){for(final r in _rows){r.$1.dispose();}super.dispose();}

  List<CarQuickMessage> get _list=>[for(final r in _rows)(text:r.$1.text,priority:r.$2)];

  void _add(){if(_rows.length<maxCarQuickMessages)setState(()=>_rows.add((TextEditingController(),'routine')));}
  void _remove(int i){final r=_rows.removeAt(i);setState((){});WidgetsBinding.instance.addPostFrameCallback((_)=>r.$1.dispose());}
  void _priority(int i,bool urgent)=>setState(()=>_rows[i]=(_rows[i].$1,urgent?'urgent':'routine'));

  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    final problem=carQuickMessagesProblem(_list);
    return Scaffold(
      appBar:LinkedAppBar(title:Text(S.t('eventSettings.quickCar.title')),actions:[
        TextButton(key:const ValueKey('car-quick-save'),onPressed:problem!=null?null:()=>Navigator.pop<CarQuickMessagesResult>(context,(messages:_list,reset:false)),
          child:Text(S.t('common.save'))),
      ]),
      body:ListView(padding:const EdgeInsets.only(bottom:16),children:[
        Padding(padding:const EdgeInsets.fromLTRB(16,12,16,8),child:Text(S.t('eventSettings.quickCar.intro'),style:t.textTheme.bodyMedium)),
        for(var i=0;i<_rows.length;i++)ListTile(key:ValueKey('car-quick-$i'),
          title:TextField(controller:_rows[i].$1,maxLength:carQuickMessageMaxLength,textCapitalization:TextCapitalization.sentences,
            onChanged:(_)=>setState((){}),decoration:InputDecoration(isDense:true,hintText:S.t('eventSettings.quickCar.hint'))),
          subtitle:Row(children:[
            FilterChip(key:ValueKey('car-quick-urgent-$i'),label:Text(S.t('eventSettings.quickCar.urgent')),selected:_rows[i].$2=='urgent',
              visualDensity:VisualDensity.compact,onSelected:(v)=>_priority(i,v)),
          ]),
          trailing:IconButton(tooltip:S.t('common.delete'),icon:const Icon(Icons.delete_outline),onPressed:_rows.length<=1?null:()=>_remove(i))),
        if(problem!=null&&_rows.isNotEmpty)Padding(padding:const EdgeInsets.fromLTRB(16,4,16,0),
          child:Text(S.t(problem),key:const ValueKey('car-quick-problem'),style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.error))),
        Padding(padding:const EdgeInsets.fromLTRB(16,12,16,0),child:Wrap(spacing:12,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
          FilledButton.icon(key:const ValueKey('car-quick-add'),onPressed:_rows.length>=maxCarQuickMessages?null:_add,icon:const Icon(Icons.add),label:Text(S.t('eventSettings.quickCar.add'))),
          Text(S.t('eventSettings.quickCar.countOf',{'n':_rows.length,'max':maxCarQuickMessages}),style:t.textTheme.bodySmall),
        ])),
        Padding(padding:const EdgeInsets.fromLTRB(16,12,16,0),child:Align(alignment:Alignment.centerLeft,child:OutlinedButton(key:const ValueKey('car-quick-reset'),
          onPressed:()=>Navigator.pop<CarQuickMessagesResult>(context,(messages:null,reset:true)),child:Text(S.t('eventSettings.quickCar.reset'))))),
      ]),
    );
  }
}
