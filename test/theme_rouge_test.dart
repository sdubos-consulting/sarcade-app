// Card « Thème Rouge pour la nuit (vision nocturne) » (validated on 9 Nov
// 2026): a fourth choice Rouge, everything in red on black, back to the
// previous theme in one gesture (long press on the link pill).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/link_weather_pill.dart';
import 'package:sarcade_app/src/features/settings/theme_choice.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/ui/theme.dart';

void main(){
  setUp((){S.setLanguage('fr');redMode.value=false;themeMode.value=ThemeMode.light;});

  test('the filter keeps no green nor blue: no white nor blue pixel',(){
    for(final i in [5,6,7,8,9,10,11,12,13,14]){expect(redVisionMatrix[i],0,reason:'index $i');}
    // White becomes red, a little dimmed.
    final white=redVisionMatrix[0]+redVisionMatrix[1]+redVisionMatrix[2];
    expect(white,closeTo(0.9,0.001));
    expect(redVision(true,const SizedBox()),isA<ColorFiltered>());
    expect(redVision(false,const SizedBox()),isA<SizedBox>());
  });

  testWidgets('Rouge is a fourth choice; it keeps the theme below; Nuit turns it off',(t) async {
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:ThemeChoice())));
    for(final l in ['Jour','Nuit','Auto','Rouge']){expect(find.text(l),findsOneWidget,reason:l);}
    await t.tap(find.text('Rouge'));await t.pump();
    expect(redMode.value,isTrue);
    expect(themeMode.value,ThemeMode.light,reason:'the previous theme is kept');
    await t.tap(find.text('Nuit'));await t.pump();
    expect(redMode.value,isFalse);
    expect(themeMode.value,ThemeMode.dark);
  });

  testWidgets('long press on the link dot: red mode on, then back',(t) async {
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Center(child:LinkWeatherPill(dot:Colors.green,linkTooltip:'Serveur',
      onLinks:(){},onWeather:(){},onLinksLong:toggleRedMode)))));
    await t.longPress(find.byKey(const ValueKey('link-dot')));await t.pump();
    expect(redMode.value,isTrue);
    await t.longPress(find.byKey(const ValueKey('link-dot')));await t.pump();
    expect(redMode.value,isFalse);
    expect(themeMode.value,ThemeMode.light);
  });

  testWidgets('iPhone: the four choices on one line; large text: icon above the word',(t) async {
    t.view.physicalSize=const Size(390,300);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:ThemeChoice())));
    final ys={for(final l in ['Jour','Nuit','Auto','Rouge'])t.getCenter(find.text(l)).dy};
    expect(ys,hasLength(1),reason:'one line');
    await t.pumpWidget(const MaterialApp(home:MediaQuery(data:MediaQueryData(size:Size(390,300),textScaler:TextScaler.linear(1.6)),
      child:Scaffold(body:ThemeChoice()))));
    final icons={for(final l in ['Jour','Nuit','Auto','Rouge'])t.getCenter(find.text(l)).dy};
    expect(icons,hasLength(1),reason:'still one line');
    expect(t.takeException(),isNull);
  });
}
