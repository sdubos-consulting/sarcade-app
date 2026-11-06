import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/conversations.dart';
import 'package:sarcade_app/src/features/ptt/ptt.dart';
import 'package:sarcade_app/src/features/ptt/ptt_bar.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  setUp(()=>S.setLanguage('fr'));
  tearDown((){final p=Ptt.instance;p.available=false;p.channels=const [];p.channel=null;p.state=PttState.off;p.speakers=const [];p.canTalk=false;});

  test('the voice channel of a conversation',(){
    expect(pttChannelOf(allKey),pttGeneral);
    expect(pttChannelOf(groupKey('equipe2')),'equipe2');
    expect(pttChannelOf(directKey('TEL-02')),isNull);
  });
  test('channels read from the server',(){
    final c=parsePttChannels({'available':true,'channels':[{'id':'general','name':'Général','can_talk':true},{'id':'pco','name':'PCO','can_talk':false}]});
    expect(c.map((x)=>x.id),['general','pco']);
    expect(c.last.canTalk,isFalse);
  });
  testWidgets('no headset while the server has no LiveKit',(t) async {
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:PttHeaderButton(channel:pttGeneral,name:'TEL-01'))));
    expect(find.byKey(const ValueKey('ptt-header')),findsNothing);
    Ptt.instance..available=true..channels=[(id:pttGeneral,name:'Général',canTalk:true)];
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:PttHeaderButton(channel:pttGeneral,name:'TEL-01',key:ValueKey(2)))));
    expect(find.byKey(const ValueKey('ptt-header')),findsOneWidget);
  });
  testWidgets('who talks, and the button to hold',(t) async {
    Ptt.instance..channel=pttGeneral..state=PttState.listening..canTalk=true..speakers=['TEL-02'];
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:PttBar(channel:pttGeneral))));
    expect(find.text('TEL-02 parle'),findsOneWidget);
    expect(find.byKey(const ValueKey('ptt-talk')),findsOneWidget);
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:PttBar(channel:'autre'))));
    expect(find.byKey(const ValueKey('ptt-bar')),findsNothing);
  });
  testWidgets('listen only: no button',(t) async {
    Ptt.instance..channel='pco'..state=PttState.listening..canTalk=false;
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:PttBar(channel:'pco'))));
    expect(find.text('Écoute seule dans ce canal'),findsOneWidget);
    expect(find.byKey(const ValueKey('ptt-talk')),findsNothing);
  });
}
