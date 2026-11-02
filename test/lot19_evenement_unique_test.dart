// Lot 19, card « Événement choisi automatiquement quand le serveur n'en a
// qu'un » (1 Nov 2026): one, several, no open event; the followed event
// deleted (404); a choice by hand kept while the server knows it.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/features/events/event_choice.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';

Map<String,dynamic> ev(String id,String name,String status)=>{'id':id,'name':name,'status':status,'created_at':'2026-11-01T20:00:00Z',
  'ended_at':status=='closed'?'2026-11-01T21:00:00Z':null};

/// Server with [all] events; the list hides the closed ones unless asked;
/// [down]: no answer.
SarcadeApi serverWith(List<Map<String,dynamic>> all,{bool down=false,List<Map<String,dynamic>>? created}){
  return SarcadeApi(baseUrl:'http://nas:8000',client:MockClient((r) async {
    if(down)throw http.ClientException('offline');
    if(r.method=='POST'&&r.url.path=='/api/v0.1/events'){
      final b=jsonDecode(r.body) as Map;
      final e=ev('evt-new','${b['name']}','draft');
      created?.add(e);
      return http.Response(jsonEncode(e),201);
    }
    if(r.url.path=='/api/v0.1/events'){
      final closed=r.url.queryParameters['include_closed']=='true';
      return http.Response(jsonEncode([for(final e in all)if(closed||e['status']!='closed')e]),200);
    }
    return http.Response('{}',404);
  }));
}

void main(){
  setUp(()=>S.setLanguage('fr'));

  group('rules',(){
    final a=ev('a','Test NAS 1','draft'), b=ev('b','Exercice','active'), c=ev('c','Ancien','closed');

    test('open events: draft or active, the active ones first',(){
      expect(openEvents([a,b,c]).map((e)=>e['id']),['b','a']);
    });

    test('one, several, none',(){
      expect(pickEvent(open:[a],current:'x',known:false,manual:false),EventPick.auto);
      expect(pickEvent(open:[b,a],current:'x',known:false,manual:false),EventPick.choose);
      expect(pickEvent(open:const [],current:'x',known:false,manual:false),EventPick.none);
    });

    test('the followed event open: kept, even with others',(){
      expect(pickEvent(open:[b,a],current:'a',known:true,manual:false),EventPick.keep);
      expect(pickEvent(open:[a],current:'a',known:true,manual:false),EventPick.keep);
    });

    test('a choice by hand is kept while the server knows it',(){
      expect(pickEvent(open:[a],current:'c',known:true,manual:true),EventPick.keep);
      expect(pickEvent(open:[a],current:'c',known:true,manual:false),EventPick.auto,reason:'not by hand: replaced');
      expect(pickEvent(open:[a],current:'c',known:false,manual:true),EventPick.auto,reason:'deleted: replaced');
    });

    test('Paramètres: the only open event of a server',(){
      expect(singleOpenEvent([a],'')!['id'],'a');
      expect(singleOpenEvent([a],'evt-demo')!['id'],'a');
      expect(singleOpenEvent([a,b],''),isNull);
      expect(singleOpenEvent([a,b],'b'),isNull);
      expect(singleOpenEvent([b],'b'),isNull,reason:'already followed');
    });

    test('texts in French and English',(){
      expect(S.t('events.followed',{'name':'Test NAS 1'}),'Événement suivi : Test NAS 1');
      expect(S.t('events.noneOpen'),'Aucun événement ouvert');
      S.setLanguage('en');
      expect(S.t('events.followed',{'name':'Test NAS 1'}),'Event followed: Test NAS 1');
    });
  });

  group('at start and on a 404',(){
    late BuildContext ctx;
    Future<void> app(WidgetTester t)=>t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(c){ctx=c;return const SizedBox();}))));
    // The message « Événement suivi » goes away by itself.
    Future<void> settle(WidgetTester t) async {await t.pumpAndSettle();await t.pump(const Duration(seconds:6));await t.pumpAndSettle();}

    testWidgets('one open event: followed at once, « Événement suivi : … »',(t) async {
      await app(t);
      final followed=<(String,bool)>[];
      final pick=await checkFollowedEvent(api:serverWith([ev('a','Test NAS 1','draft'),ev('c','Ancien','closed')]),current:'evt-demo',deviceId:'TEL-01',
        manual:false,context:()=>ctx,follow:(e,{required manual}) async=>followed.add(('${e['id']}',manual)));
      await t.pump(); await t.pump();
      expect(pick,EventPick.auto);
      expect(followed,[('a',false)]);
      expect(find.text('Événement suivi : Test NAS 1'),findsOneWidget);
      await settle(t);
    });

    testWidgets('several: the list, the active one first; the choice is by hand',(t) async {
      await app(t);
      final followed=<(String,bool)>[];
      final done=checkFollowedEvent(api:serverWith([ev('a','Brouillon','draft'),ev('b','En cours','active')]),current:'evt-demo',deviceId:'TEL-01',
        manual:false,context:()=>ctx,follow:(e,{required manual}) async=>followed.add(('${e['id']}',manual)));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('event-choice')),findsOneWidget);
      final first=t.getTopLeft(find.byKey(const ValueKey('event-choice-b'))).dy, second=t.getTopLeft(find.byKey(const ValueKey('event-choice-a'))).dy;
      expect(first,lessThan(second),reason:'active first');
      await t.tap(find.byKey(const ValueKey('event-choice-a')));
      await t.pumpAndSettle();
      expect(await done,EventPick.choose);
      expect(followed,[('a',true)]);
      await settle(t);
    });

    testWidgets('none: « Aucun événement ouvert », « Créer » for the PCO only',(t) async {
      await app(t);
      final created=<Map<String,dynamic>>[], followed=<(String,bool)>[];
      var done=checkFollowedEvent(api:serverWith(const []),current:'evt-demo',deviceId:'TEL-01',
        manual:false,context:()=>ctx,follow:(e,{required manual}) async=>followed.add(('${e['id']}',manual)));
      await t.pumpAndSettle();
      expect(find.text('Aucun événement ouvert'),findsOneWidget);
      expect(find.byKey(const ValueKey('event-none-create')),findsNothing);
      await t.tap(find.text('Fermer'));
      await t.pumpAndSettle();
      expect(await done,EventPick.none);
      expect(followed,isEmpty);

      done=checkFollowedEvent(api:serverWith(const [],created:created),current:'evt-demo',deviceId:'PCO',
        manual:false,context:()=>ctx,follow:(e,{required manual}) async=>followed.add(('${e['id']}',manual)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('event-none-create')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('event-new-name')),'Exercice du 2');
      await t.tap(find.byKey(const ValueKey('event-new-create')));
      await t.pumpAndSettle();
      expect(await done,EventPick.none);
      expect(created.single['name'],'Exercice du 2');
      expect(followed,[('evt-new',true)]);
      await settle(t);
    });

    testWidgets('followed event deleted (404): one open → switch, several → list',(t) async {
      await app(t);
      final followed=<(String,bool)>[];
      expect(await checkFollowedEvent(api:serverWith([ev('a','Test NAS 1','active')]),current:'gone',deviceId:'TEL-01',
        manual:true,unknown:true,context:()=>ctx,follow:(e,{required manual}) async=>followed.add(('${e['id']}',manual))),EventPick.auto);
      expect(followed,[('a',false)]);
      final done=checkFollowedEvent(api:serverWith([ev('a','A','active'),ev('b','B','draft')]),current:'gone',deviceId:'TEL-01',
        manual:true,unknown:true,context:()=>ctx,follow:(e,{required manual}) async {});
      await t.pumpAndSettle();
      expect(find.text('Événement suivi inconnu du serveur'),findsOneWidget);
      await t.tap(find.byKey(const ValueKey('event-choice-b')));
      await t.pumpAndSettle();
      expect(await done,EventPick.choose);
      await settle(t);
    });

    testWidgets('a closed event chosen by hand stays; without network nothing changes',(t) async {
      await app(t);
      var calls=0;
      Future<void> follow(Map<String,dynamic> e,{required bool manual}) async=>calls++;
      expect(await checkFollowedEvent(api:serverWith([ev('a','A','active'),ev('c','Ancien','closed')]),current:'c',deviceId:'TEL-01',
        manual:true,context:()=>ctx,follow:follow),EventPick.keep);
      expect(await checkFollowedEvent(api:serverWith(const [],down:true),current:'c',deviceId:'TEL-01',
        manual:false,context:()=>ctx,follow:follow),isNull);
      expect(calls,0);
    });
  });
}
