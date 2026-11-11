// Card « Messages : menu … plus soigné » (validated 5 Nov 2026): choice 3
// (same style for every « … » menu) and choice 4 (« Canaux ADRASEC » greyed
// with « Déjà ajoutés » once the channels of the model are there).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/groups/group_templates.dart';
import 'package:sarcade_app/src/ui/link_status.dart';
import 'package:sarcade_app/src/ui/menu_entry.dart';

void main(){
  test('same channel ids as the server (uuid5 of sarcade:<event>:group:<key>)',(){
    // Python: uuid.uuid5(uuid.NAMESPACE_URL, 'sarcade:ev1:group:pco')
    expect(defaultGroupId('ev1','pco'),'3b13b30c-f869-509b-a083-e434a8812c94');
  });

  test('ADRASEC model added only when its four channels are there',(){
    final ids=[for(final k in groupTemplates['adrasec']!)defaultGroupId('ev1',k)];
    expect(templateAdded('ev1','adrasec',const []),isFalse);
    expect(templateAdded('ev1','adrasec',ids.take(3)),isFalse);
    expect(templateAdded('ev1','adrasec',[...ids,'other']),isTrue);
    expect(templateAdded('ev2','adrasec',ids),isFalse,reason:'ids of another event');
    expect(templateAdded('ev1','unknown',ids),isFalse);
  });

  testWidgets('done entry: greyed icon and label',(t) async {
    late ThemeData theme;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(c){theme=Theme.of(c);
      return menuEntry(c,icon:Icons.shield_outlined,color:Colors.blue,title:'Canaux ADRASEC',detail:'Déjà ajoutés',done:true);}))));
    final grey=theme.colorScheme.onSurface.withValues(alpha:0.38);
    expect(t.widget<Icon>(find.byIcon(Icons.shield_outlined)).color,grey);
    expect(t.widget<Text>(find.text('Canaux ADRASEC')).style?.color,grey);
    expect(find.text('Déjà ajoutés'),findsOneWidget);
  });

  testWidgets('no colour given: the primary colour',(t) async {
    late ThemeData theme;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(c){theme=Theme.of(c);
      return menuEntry(c,icon:Icons.refresh,title:'Actualiser');}))));
    expect(t.widget<Icon>(find.byIcon(Icons.refresh)).color,theme.colorScheme.primary);
  });

  testWidgets('« ⋮ » of the title bars: entries with a round icon',(t) async {
    t.view.physicalSize=const Size(390,844); t.view.devicePixelRatio=1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home:Scaffold(appBar:LinkedAppBar(title:const Text('Écran'),linkStatus:false,secondary:[
      AppBarAction(icon:Icons.campaign_outlined,label:'Diffuser',onPressed:(){}),
      AppBarAction(icon:Icons.add,label:'Ajouter',onPressed:(){}),
      const AppBarAction(icon:Icons.block,label:'Indisponible',onPressed:null),
    ]))));
    await t.tap(find.byKey(const ValueKey('appbar-more'))); await t.pumpAndSettle();
    expect(find.byType(CircleAvatar),findsNWidgets(3));
    expect(find.text('Diffuser'),findsOneWidget);
  });
}
