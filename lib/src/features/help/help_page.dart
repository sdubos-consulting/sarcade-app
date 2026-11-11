/// Paramètres › Aide (card « Paramètres : menu « Aide » (aide du Core, et
/// une page d'aide par module actif) », validated on 10 Nov 2026, choices
/// 1 to 5 and 7; choice 6, a « ? » on each screen, comes later):
/// - the help of the Core, one topic per Markdown file of
///   ``assets/help/core`` (kept in the application: the help works offline);
/// - a search at the top, on the titles and the texts;
/// - at the bottom, « Modules »: one line per module on for the followed
///   event (same rule as the rest of the application, see [helpModules]),
///   each with its own topics, given by [AppModule.helpTopics] (the Core
///   does not import the code of a module).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../account/rights.dart' show RightsState;
import '../../l10n/strings.dart';
import '../../modules/registry.dart';
import '../../operations/event_settings.dart' show eventModules;
import '../../ui/setting_line.dart';
import '../../ui/theme.dart' show searchInputBorder;
import 'markdown_lite.dart';

const coreHelpFolder='assets/help/core';
/// Topics of the Core, in their order on the page.
const coreHelpTopics=['premiers-pas','carte','messages','equipes','outils','sos-alertes','hors-connexion','voiture','tv','questions'];

String helpAsset(String folder,String topic)=>'$folder/$topic.md';

/// Every help file the application declares (Core and modules).
List<String> allHelpAssets()=>[
  for(final t in coreHelpTopics)helpAsset(coreHelpFolder,t),
  for(final m in appModules)for(final t in m.helpTopics)helpAsset(m.helpFolder,t),
];

/// Modules on for the event (its settings) and allowed by the rights: a
/// module turned off has no help line.
List<AppModule> helpModules(Map<String,dynamic>? eventSettings,{bool Function(String id)? allows}){
  final on=eventModules(eventSettings);
  final ok=allows??RightsState.instance.allows;
  return [for(final m in appModules)if(m.helpTopics.isNotEmpty&&on.contains(m.id)&&ok(m.id))m];
}

/// One topic read from the bundle.
class HelpDoc {
  final String asset, topic, title, source;
  /// Module of the topic, null for the Core.
  final AppModule? module;
  HelpDoc({required this.asset,required this.topic,required this.source,this.module}):title=markdownTitle(source)??topic;
  late final String _plain=foldForSearch(markdownPlain(source));
  bool matches(String folded)=>foldForSearch(title).contains(folded)||_plain.contains(folded);
  /// A few words around the first match, for the list of results.
  String excerpt(String folded){
    final plain=markdownPlain(source).replaceAll('\n',' ');
    final i=foldForSearch(plain).indexOf(folded);
    if(i<0)return '';
    final from=(i-40).clamp(0,plain.length), to=(i+folded.length+60).clamp(0,plain.length);
    return '${from>0?'… ':''}${plain.substring(from,to).trim()}${to<plain.length?' …':''}';
  }
}

/// Lower case, without accents (« évènement » finds « Événement »). Same
/// length as [s] for the letters used in French, so an index still fits.
String foldForSearch(String s){
  const from='àâäáãçéèêëíìîïñóòôöõúùûüýÿœæ', to='aaaaaceeeeiiiinooooouuuuyy';
  final b=StringBuffer();
  for(final c in s.toLowerCase().split('')){
    final i=from.indexOf(c);
    b.write(i<0?c:i<to.length?to[i]:c=='œ'?'o':'a');
  }
  return b.toString();
}

/// Reads the topics of the Core and of [modules].
Future<List<HelpDoc>> loadHelp(List<AppModule> modules,{AssetBundle? bundle}) async {
  final b=bundle??rootBundle;
  Future<HelpDoc> one(String folder,String topic,AppModule? m) async {
    final asset=helpAsset(folder,topic);
    return HelpDoc(asset:asset,topic:topic,module:m,source:await b.loadString(asset,cache:false));
  }
  return [
    for(final t in coreHelpTopics)await one(coreHelpFolder,t,null),
    for(final m in modules)for(final t in m.helpTopics)await one(m.helpFolder,t,m),
  ];
}

/// Content of Paramètres › Aide (inside the scrolling page of Paramètres).
class HelpContent extends StatefulWidget {
  /// Settings of the followed event (its modules); null: as the rest of the
  /// application, ADRASEC when nothing is known.
  final Map<String,dynamic>? eventSettings;
  const HelpContent({super.key,this.eventSettings});
  @override State<HelpContent> createState()=>_HelpContentState();
}

class _HelpContentState extends State<HelpContent> {
  final _search=TextEditingController();
  late List<AppModule> _modules=helpModules(widget.eventSettings);
  List<HelpDoc>? _docs;
  bool _failed=false;

  @override void initState(){super.initState();_load();}

  @override void didUpdateWidget(HelpContent old){
    super.didUpdateWidget(old);
    final now=helpModules(widget.eventSettings);
    if(now.map((m)=>m.id).join(',')!=_modules.map((m)=>m.id).join(',')){_modules=now;_load();}
  }

  Future<void> _load() async {
    try{
      final docs=await loadHelp(_modules);
      if(mounted)setState((){_docs=docs;_failed=false;});
    }catch(_){
      if(mounted)setState(()=>_failed=true);
    }
  }

  @override void dispose(){_search.dispose();super.dispose();}

  void _open(HelpDoc d)=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>HelpTopicPage(doc:d)));

  void _openModule(AppModule m)=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>HelpModulePage(module:m,
    docs:[for(final d in _docs??const <HelpDoc>[])if(d.module?.id==m.id)d],open:_open)));

  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    final docs=_docs;
    final query=foldForSearch(_search.text.trim());
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.only(top:12,bottom:4),child:TextField(key:const ValueKey('help-search'),controller:_search,
        onChanged:(_)=>setState((){}),
        decoration:InputDecoration(isDense:true,prefixIcon:const Icon(Icons.search),hintText:S.t('help.search'),
          // Search field: pill of the theme, no outline (card « Saisie : zones
          // de saisie sur fond coloré, sans contour », 10 Nov 2026).
          border:searchInputBorder,
          suffixIcon:_search.text.isEmpty?null:IconButton(tooltip:S.t('help.clear'),icon:const Icon(Icons.close),onPressed:()=>setState(_search.clear))))),
      if(_failed)Padding(padding:const EdgeInsets.only(top:16),child:Text(S.t('help.unavailable')))
      // Read from the application in a moment: no spinner (it would turn
      // for nothing while the page is hidden behind the list).
      else if(docs==null)const SizedBox(height:48)
      else if(query.isNotEmpty)..._results(docs,query,t)
      else...[
        SettingsSectionTitle(S.t('help.core')),
        for(final d in docs)if(d.module==null)SettingLine(key:ValueKey('help-topic-${d.topic}'),title:d.title,onTap:()=>_open(d)),
        // Choice 3: the modules on for this event, none when all are off.
        if(_modules.isNotEmpty)...[
          SettingsSectionTitle(S.t('help.modules'),key:const ValueKey('help-modules')),
          for(final m in _modules)SettingLine(key:ValueKey('help-module-${m.id}'),title:S.t(m.labelKey),help:S.t(m.helpKey),onTap:()=>_openModule(m)),
        ],
      ],
    ]);
  }

  List<Widget> _results(List<HelpDoc> docs,String query,ThemeData t){
    final found=docs.where((d)=>d.matches(query)).toList();
    if(found.isEmpty)return [Padding(padding:const EdgeInsets.only(top:16),child:Text(S.t('help.noResult'),key:const ValueKey('help-no-result')))];
    return [for(final d in found)SettingLine(key:ValueKey('help-result-${d.asset}'),
      title:d.module==null?d.title:'${S.t(d.module!.labelKey)} · ${d.title}',help:d.excerpt(query),onTap:()=>_open(d))];
  }
}

/// Topics of one module.
class HelpModulePage extends StatelessWidget {
  final AppModule module; final List<HelpDoc> docs; final void Function(HelpDoc) open;
  const HelpModulePage({super.key,required this.module,required this.docs,required this.open});
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(S.t('help.moduleTitle',{'name':S.t(module.labelKey)}))),
    body:SafeArea(child:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,24),children:[
      for(final d in docs)SettingLine(key:ValueKey('help-topic-${d.topic}'),title:d.title,onTap:()=>open(d)),
    ])));
}

/// One topic, its title in the bar.
class HelpTopicPage extends StatelessWidget {
  final HelpDoc doc;
  const HelpTopicPage({super.key,required this.doc});
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(doc.title)),
    body:SafeArea(child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:760),
      child:ListView(key:ValueKey('help-page-${doc.topic}'),padding:const EdgeInsets.fromLTRB(20,12,20,32),children:[
        SelectionArea(child:MarkdownLite(doc.source,skipTitle:true)),
      ])))));
}
