import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/settings/windows_update.dart';
import 'package:sarcade_app/src/features/settings/windows_update_box.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/message.dart';
import 'package:sarcade_app/src/services/sha256.dart';

const _installer=[1,2,3,4,5];
final _sha=sha256Hex(_installer);

SarcadeMessage _msg(String sender,String body,int minute)=>SarcadeMessage(id:'$sender-$minute',eventId:'e1',senderId:sender,
  recipientIds:const [],priority:'immediate',body:body,createdAt:DateTime.utc(2026,11,3,12,minute));

WindowsUpdates _updates({Object? server,Object? github,bool serverFails=false,bool installed=true,List<int> bytes=_installer,
    List<List<String>>? started,List<String>? quits})=>WindowsUpdates(supported:true,installed:installed,
  version:'0.1.0',buildNumber:'956',build:'main@f61ab82',quitDelay:Duration.zero,
  fetchServer:(_) async {if(serverFails)throw Exception('down');return server;},
  fetchGithub:() async {if(github==null)throw Exception('no internet');return github;},
  download:(r,_) async=>bytes,
  save:(name,_) async=>'C:\\Temp\\$name',
  start:(path,args) async {started?.add([path,...args]);return true;},
  quit:()=>quits?.add('quit'));

void main(){
  group('SHA-256',(){
    test('standard vectors',(){
      expect(sha256Hex(const []),'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(sha256Hex(utf8.encode('abc')),'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(sha256Hex(utf8.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
      // One million bytes, and 56 bytes (padding on a second block).
      expect(sha256Hex(List.filled(1000000,0x61)),'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
      expect(sha256Hex(utf8.encode('a'*56)),'b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a');
    });
  });

  group('sources',(){
    test('server first: package of /clients/latest',(){
      final r=releaseFromServer({'windows':{'platform':'windows','version':'0.1.0+960','sha256':_sha.toUpperCase(),'size':5,
        'url':'/api/v0.1/clients/windows/package'}},'https://sarcade.example/')!;
      expect(r.version,'0.1.0+960');
      expect(r.sha256,_sha);
      expect(r.url,'https://sarcade.example/api/v0.1/clients/windows/package');
      expect(r.source,WindowsUpdateSource.server);
      expect(releaseFromServer({'apk':{'version':'0.1.0'}},'https://s'),isNull);
      expect(releaseFromServer(const {},'https://s'),isNull);
      expect(releaseFromServer({'windows':{'version':'0.1.0','sha256':'not-a-hash'}},'https://s')!.sha256,isNull);
    });
    test('GitHub manifest of windows-dev',(){
      final r=releaseFromGithub({'version':'0.1.0+960','build':'main@abc1234','sha256':_sha,'size':5})!;
      expect(r.build,'main@abc1234');
      expect(r.url,windowsDevInstallerUrl);
      expect(r.source,WindowsUpdateSource.github);
      expect(releaseFromGithub('<html>'),isNull);
    });
  });

  group('newer than the running copy',(){
    WindowsRelease rel(String v,{String? build})=>WindowsRelease(version:v,build:build,url:'u',source:WindowsUpdateSource.github);
    test('version, then build number',(){
      expect(isNewerRelease(rel('0.1.0+960'),version:'0.1.0',buildNumber:'956',build:'main@f61ab82'),isTrue);
      expect(isNewerRelease(rel('0.1.0+956'),version:'0.1.0',buildNumber:'956',build:'main@f61ab82'),isFalse);
      expect(isNewerRelease(rel('0.1.0+950'),version:'0.1.0',buildNumber:'956',build:'main@f61ab82'),isFalse);
      expect(isNewerRelease(rel('0.2.0'),version:'0.1.0',buildNumber:'956',build:'main@f61ab82'),isTrue);
      expect(isNewerRelease(rel('0.1.0'),version:'0.1.0',buildNumber:'956',build:'main@f61ab82'),isFalse);
    });
    test('ARM64 copy without build number: another commit',(){
      expect(isNewerRelease(rel('0.1.0+960',build:'main@abc1234'),version:'0.1.0',buildNumber:'',build:'main@f61ab82-arm64'),isTrue);
      expect(isNewerRelease(rel('0.1.0+960',build:'main@f61ab82'),version:'0.1.0',buildNumber:'',build:'main@f61ab82-arm64'),isFalse);
    });
    test('local build never offers an update',(){
      expect(isNewerRelease(rel('9.0.0'),version:'0.1.0',buildNumber:'',build:''),isFalse);
    });
  });

  group('SOS and mission',(){
    final now=DateTime.utc(2026,11,3,13);
    test('SOS of this device or of another one, until its end',(){
      expect(updateGuardFor(messages:[_msg('me','🆘 SOS',1)],eventEnded:true,now:now).sos,isTrue);
      expect(updateGuardFor(messages:[_msg('f4abc','🆘 SOS',1),_msg('f4abc','Fin de détresse',2)],eventEnded:true,now:now).sos,isFalse);
      expect(updateGuardFor(messages:const [],eventEnded:true,now:now).blocks,isFalse);
    });
    test('mission: event open and contact in the last 24 h (rule of the server)',(){
      expect(missionActive(eventEnded:false,lastContact:now.subtract(const Duration(hours:1)),now:now),isTrue);
      expect(missionActive(eventEnded:false,lastContact:now.subtract(const Duration(hours:25)),now:now),isFalse);
      expect(missionActive(eventEnded:true,lastContact:now,now:now),isFalse);
      expect(missionActive(eventEnded:false,now:now),isFalse);
    });
  });

  group('service',(){
    test('server first, GitHub when the server does not answer',() async {
      final a=_updates(server:{'windows':{'version':'0.1.0+960','sha256':_sha,'size':5}},github:{'version':'0.1.0+999','sha256':_sha});
      a.attach('https://s');
      await a.check();
      expect(a.latest!.source,WindowsUpdateSource.server);
      expect(a.state,WindowsUpdateState.available);
      expect(a.available,isTrue);
      final b=_updates(serverFails:true,github:{'version':'0.1.0+956','build':'main@f61ab82','sha256':_sha});
      b.attach('https://s');
      await b.check();
      expect(b.latest!.source,WindowsUpdateSource.github);
      expect(b.state,WindowsUpdateState.upToDate);
      final c=_updates(server:const {},github:{'version':'0.1.0+961','sha256':_sha});
      c.attach('https://s');
      await c.check();
      expect(c.latest!.source,WindowsUpdateSource.github,reason:'server without Windows package');
      final d=_updates(serverFails:true);
      d.attach('https://s');
      await d.check();
      expect(d.state,WindowsUpdateState.unknown);
      for(final u in [a,b,c,d]){u.dispose();}
    });

    test('install: fingerprint checked, silent install, SARCADE quits',() async {
      final started=<List<String>>[], quits=<String>[];
      final u=_updates(server:{'windows':{'version':'0.1.0+960','sha256':_sha}},started:started,quits:quits);
      u.attach('https://s');
      await u.check();
      await u.install();
      expect(started.single.first,startsWith('C:\\Temp\\sarcade-windows-setup-0.1.0-960'));
      expect(started.single.sublist(1),windowsInstallerArguments);
      expect(started.single,containsAll(['/SILENT','/CLOSEAPPLICATIONS','/relaunch=1']));
      expect(quits,['quit']);
      u.dispose();
    });

    test('install refused: other fingerprint, fingerprint unknown, portable copy',() async {
      final started=<List<String>>[], quits=<String>[];
      final bad=_updates(server:{'windows':{'version':'0.1.0+960','sha256':_sha}},bytes:const [9,9,9],started:started,quits:quits);
      bad.attach('https://s');
      await bad.check();
      await bad.install();
      expect(bad.state,WindowsUpdateState.failed);
      expect(bad.failure,'update.win.badHash');
      final none=_updates(server:{'windows':{'version':'0.1.0+960'}},started:started,quits:quits);
      none.attach('https://s');
      await none.check();
      await none.install();
      expect(none.failure,'update.win.noHash');
      final portable=_updates(server:{'windows':{'version':'0.1.0+960','sha256':_sha}},installed:false,started:started,quits:quits);
      portable.attach('https://s');
      await portable.check();
      await portable.install();
      expect(portable.downloadUrl,windowsDevPageUrl);
      expect(started,isEmpty);
      expect(quits,isEmpty);
      for(final u in [bad,none,portable]){u.dispose();}
    });

    test('nothing on other platforms',() async {
      final u=WindowsUpdates(supported:false,installed:false,fetchServer:(_) async=>throw StateError('not called'),
        fetchGithub:() async=>throw StateError('not called'));
      u.attach('https://s');
      await u.check();
      expect(u.state,WindowsUpdateState.idle);
      expect(windowsUpdateAlert(),isFalse);
      u.dispose();
    });
  });

  testWidgets('box: state, Mettre à jour, Télécharger; confirmation during a SOS',(tester) async {
    S.setLanguage('fr');
    final started=<List<String>>[];
    final u=_updates(server:{'windows':{'version':'0.1.0+960','sha256':_sha}},started:started);
    u.attach('https://s');
    await u.check();
    u.guard=()=>const UpdateGuard(sos:true);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:WindowsUpdateBox(updates:u))));
    expect(find.text('Nouvelle version disponible'),findsOneWidget);
    expect(find.textContaining('0.1.0+960'),findsOneWidget);
    expect(find.byKey(const ValueKey('update-download')),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('update-install')));
    await tester.pumpAndSettle();
    expect(find.text('Mettre à jour maintenant ?'),findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(started,isEmpty);
    u.dispose();
  });

  test('texts in French and English',(){
    for(final lang in ['fr','en']){
      S.setLanguage(lang);
      for(final k in ['update.win.title','update.win.installed','update.win.latest','update.win.available','update.win.upToDate',
          'update.win.unknown','update.win.install','update.win.download','update.win.portable','update.win.badHash',
          'update.win.noHash','update.win.confirmSos','update.win.confirmMission']){
        expect(S.t(k),isNot(k),reason:'$lang $k');
      }
    }
    S.setLanguage('fr');
  });
}
