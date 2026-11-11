/// Windows: « Mise à jour » box of Paramètres › À propos (card « Windows :
/// menu Mise à jour (état de la version, téléchargement, mise à jour en un
/// clic) », lot 25).
///
/// Source: the SARCADE server first (`GET /api/v0.1/clients/latest`, the
/// Windows package placed by the administrator or the installer of its page
/// Téléchargements, with its SHA-256), then the server of the NAS
/// ([defaultServerUrl], same request: installer built on the i9 and served
/// by its page Téléchargements), and as a last resort the latest major
/// release of GitHub (`releases/latest`, `sarcade-windows-version.json`
/// written by tool/publish-github.ps1 of sarcade-server). Never the
/// `windows-dev` pre-release any more (card « GitHub de nouveau actif
/// (10 novembre 2026) », choice 2: GitHub only carries the validated major
/// releases). Checked at start, then every 6 hours; never a window imposed, only a
/// dot on Paramètres and on À propos. « Mettre à jour » downloads the
/// installer, checks its fingerprint and starts a silent install (Inno
/// Setup) that closes SARCADE and starts it again. Portable copies (zip)
/// show the state and a link only.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/app_config.dart' show defaultServerUrl;
import '../../config/version.dart';
import '../../models/message.dart';
import '../../platform/platform_services.dart';
import '../../services/sarcade_api.dart';
import '../../services/sha256.dart';
import '../map/sos_alert.dart' show openDistress;

/// Latest major release of GitHub (10 Nov 2026): last resort only.
const githubLatestPageUrl='https://github.com/sdubos-consulting/sarcade-app/releases/latest';
const _githubLatestDownload='$githubLatestPageUrl/download';
const githubLatestManifestUrl='$_githubLatestDownload/sarcade-windows-version.json';
const githubLatestInstallerUrl='$_githubLatestDownload/sarcade-windows-setup.exe';
/// Path of the Windows package on the SARCADE server.
const serverWindowsPackagePath='/api/v0.1/clients/windows/package';
const windowsUpdatePeriod=Duration(hours:6);

/// Silent install by the Inno Setup installer (tool/windows_installer.iss):
/// progress window only, no question, SARCADE closed if still open, no
/// restart of Windows; `/relaunch=1` starts SARCADE again at the end.
const windowsInstallerArguments=['/SILENT','/SUPPRESSMSGBOXES','/NORESTART','/CLOSEAPPLICATIONS','/relaunch=1'];

enum WindowsUpdateSource{server,github}

/// Last Windows version published, with its installer.
class WindowsRelease {
  /// « 0.1.0+960 ».
  final String version;
  /// « main@abc1234 » when known (GitHub).
  final String? build;
  /// Lower-case hexadecimal SHA-256 of the installer, null when unknown.
  final String? sha256;
  final int? size;
  /// Address of the installer.
  final String url;
  final WindowsUpdateSource source;
  /// Base address of the SARCADE server that offered it (session server or
  /// server of the NAS), null for GitHub.
  final String? serverUrl;
  const WindowsRelease({required this.version,this.build,this.sha256,this.size,required this.url,required this.source,this.serverUrl});
}

final _hex64=RegExp(r'^[0-9a-f]{64}$');
String? _sha(Object? v){
  final s=v is String?v.trim().toLowerCase():'';
  return _hex64.hasMatch(s)?s:null;
}
String _trimSlash(String s)=>s.endsWith('/')?s.substring(0,s.length-1):s;

/// Windows package of `GET /clients/latest`, or null.
WindowsRelease? releaseFromServer(Object? latest,String baseUrl){
  if(latest is! Map)return null;
  final w=latest['windows'];
  if(w is! Map||w['version'] is! String||(w['version'] as String).trim().isEmpty)return null;
  final url=w['url'] is String?(w['url'] as String):serverWindowsPackagePath;
  final build=w['build'];
  return WindowsRelease(version:(w['version'] as String).trim(),build:build is String&&build.trim().isNotEmpty?build.trim():null,
    sha256:_sha(w['sha256']),size:(w['size'] as num?)?.toInt(),
    url:url.startsWith('http')?url:'${_trimSlash(baseUrl)}${url.startsWith('/')?url:'/$url'}',source:WindowsUpdateSource.server,
    serverUrl:_trimSlash(baseUrl));
}

/// Content of `sarcade-windows-version.json` of the latest major release of
/// GitHub, or null.
WindowsRelease? releaseFromGithub(Object? manifest){
  if(manifest is! Map||manifest['version'] is! String||(manifest['version'] as String).trim().isEmpty)return null;
  final build=manifest['build'];
  return WindowsRelease(version:(manifest['version'] as String).trim(),build:build is String&&build.trim().isNotEmpty?build.trim():null,
    sha256:_sha(manifest['sha256']),size:(manifest['size'] as num?)?.toInt(),url:githubLatestInstallerUrl,source:WindowsUpdateSource.github);
}

({List<int> core,int? number}) _parseVersion(String v){
  final s=v.trim().replaceFirst(RegExp('^[vV]'),'');
  final plus=s.indexOf('+');
  final corePart=(plus<0?s:s.substring(0,plus)).split('-').first;
  final core=[for(final p in corePart.split('.'))int.tryParse(RegExp(r'^\d*').stringMatch(p)??'')??0];
  while(core.length<3){core.add(0);}
  return (core:core,number:plus<0?null:int.tryParse(s.substring(plus+1)));
}

/// Newer than the running SARCADE ([version] « 0.1.0 », [buildNumber]
/// « 956 », [build] « main@f61ab82 »): version, then build number; when the
/// build number of this copy is unknown (ARM64 build), a different commit.
/// A local build (neither number nor commit) never offers an update.
bool isNewerRelease(WindowsRelease r,{required String version,required String buildNumber,required String build}){
  if(build.isEmpty&&buildNumber.isEmpty)return false;
  final a=_parseVersion(r.version), b=_parseVersion(version);
  for(var i=0;i<3;i++){
    if(a.core[i]!=b.core[i])return a.core[i]>b.core[i];
  }
  final mine=int.tryParse(buildNumber);
  if(a.number!=null&&mine!=null)return a.number!>mine;
  final theirs=r.build??'';
  final ours=build.replaceFirst(RegExp(r'-arm64$'),'').trim();
  return theirs.isNotEmpty&&ours.isNotEmpty&&theirs!=ours;
}

/// What makes « Mettre à jour » ask for a confirmation first.
class UpdateGuard {
  final bool sos, mission;
  const UpdateGuard({this.sos=false,this.mission=false});
  bool get blocks=>sos||mission;
}

/// Same rule as the server (sarcade.updates.policy.event_is_active): the
/// followed event is not closed and this device was in contact with the
/// server in the last 24 hours.
bool missionActive({required bool eventEnded,DateTime? lastContact,required DateTime now})=>
  !eventEnded&&lastContact!=null&&now.difference(lastContact)<const Duration(hours:24);

/// SOS in progress (one of this device or of another operator, not closed
/// by its « Fin de détresse ») or active mission.
UpdateGuard updateGuardFor({required Iterable<SarcadeMessage> messages,required bool eventEnded,DateTime? lastContact,required DateTime now})=>
  UpdateGuard(sos:openDistress(messages,'').isNotEmpty,mission:missionActive(eventEnded:eventEnded,lastContact:lastContact,now:now));

enum WindowsUpdateState{idle,checking,upToDate,available,unknown,downloading,verifying,installing,failed}

Future<Object?> _serverLatest(String baseUrl) async {
  final api=SarcadeApi(baseUrl:baseUrl);
  try{return await api.clientsLatest().timeout(const Duration(seconds:10));}finally{api.close();}
}

Future<Object?> _githubManifest() async {
  final r=await http.get(Uri.parse(githubLatestManifestUrl)).timeout(const Duration(seconds:20));
  if(r.statusCode!=200)throw SarcadeHttpException('windows_manifest',r.statusCode);
  return jsonDecode(utf8.decode(r.bodyBytes));
}

Future<List<int>> _downloadInstaller(WindowsRelease r,String? baseUrl) async {
  final server=r.serverUrl??baseUrl;
  if(r.source==WindowsUpdateSource.server&&server!=null){
    // Through the client of the server: Cloudflare Access session included.
    final api=SarcadeApi(baseUrl:server);
    try{
      final base=_trimSlash(server);
      return await api.download(r.url.startsWith(base)?r.url.substring(base.length):r.url).timeout(const Duration(minutes:15));
    }finally{api.close();}
  }
  final res=await http.get(Uri.parse(r.url)).timeout(const Duration(minutes:15));
  if(res.statusCode!=200)throw SarcadeHttpException('windows_installer',res.statusCode);
  return res.bodyBytes;
}

/// State of the Windows updates, one for the application.
class WindowsUpdates extends ChangeNotifier {
  WindowsUpdates({bool? supported,bool? installed,Future<Object?> Function(String baseUrl)? fetchServer,
      Future<Object?> Function()? fetchGithub,Future<List<int>> Function(WindowsRelease release,String? baseUrl)? download,
      Future<String> Function(String name,List<int> bytes)? save,Future<bool> Function(String path,List<String> arguments)? start,
      void Function()? quit,this.quitDelay=const Duration(seconds:1),this.version=appVersion,this.buildNumber=appBuildNumber,this.build=appBuild,
      this.nasUrl=defaultServerUrl})
    :supported=supported??windowsUpdateSupported(),installed=installed??windowsInstalledCopy(),
     _fetchServer=fetchServer??_serverLatest,_fetchGithub=fetchGithub??_githubManifest,_download=download??_downloadInstaller,
     _save=save??((name,bytes)=>saveFile(name,bytes,temporary:true)),_start=start??startWindowsInstaller,_quit=quit??quitApp;

  static final instance=WindowsUpdates();

  /// Windows only; elsewhere nothing is checked nor shown.
  final bool supported;
  /// Installed by the installer; false for the portable copy (zip).
  final bool installed;
  final String version, buildNumber, build;
  /// Server of the NAS, asked when the server of the session has nothing.
  final String nasUrl;
  final Duration quitDelay;
  final Future<Object?> Function(String baseUrl) _fetchServer;
  final Future<Object?> Function() _fetchGithub;
  final Future<List<int>> Function(WindowsRelease release,String? baseUrl) _download;
  final Future<String> Function(String name,List<int> bytes) _save;
  final Future<bool> Function(String path,List<String> arguments) _start;
  final void Function() _quit;

  WindowsUpdateState state=WindowsUpdateState.idle;
  WindowsRelease? latest;
  DateTime? checkedAt;
  /// Key of strings.dart of the last failure of « Mettre à jour ».
  String? failure;
  /// SOS and mission of the map page (attach).
  UpdateGuard Function()? guard;
  String? _baseUrl;
  Timer? _timer;

  /// A newer version is published: dot on Paramètres and on À propos.
  bool get available=>latest!=null&&isNewerRelease(latest!,version:version,buildNumber:buildNumber,build:build);
  bool get busy=>const {WindowsUpdateState.checking,WindowsUpdateState.downloading,WindowsUpdateState.verifying,WindowsUpdateState.installing}.contains(state);
  UpdateGuard get currentGuard=>guard?.call()??const UpdateGuard();

  /// Server of the session (map page); checks at once, then every 6 hours.
  void attach(String baseUrl,{UpdateGuard Function()? guard}){
    if(!supported)return;
    if(guard!=null)this.guard=guard;
    final changed=_baseUrl!=baseUrl;
    _baseUrl=baseUrl;
    _timer??=Timer.periodic(windowsUpdatePeriod,(_)=>unawaited(check()));
    if(changed)unawaited(check());
  }

  void _set(WindowsUpdateState s){state=s;notifyListeners();}

  Future<void>? _checking;

  /// Server of the session first, then the server of the NAS, then the
  /// latest major release of GitHub. A check already running is shared.
  Future<void> check(){
    if(!supported)return Future<void>.value();
    final running=_checking;
    if(running!=null)return running;
    if(busy)return Future<void>.value();
    final f=_check().whenComplete(()=>_checking=null);
    _checking=f;
    return f;
  }

  Future<void> _check() async {
    failure=null;
    _set(WindowsUpdateState.checking);
    WindowsRelease? found;
    final base=_baseUrl;
    if(base!=null&&base.isNotEmpty){
      try{found=releaseFromServer(await _fetchServer(base),base);}catch(_){/* NAS then */}
    }
    final nas=nasUrl.trim();
    if(found==null&&nas.isNotEmpty&&_trimSlash(nas)!=_trimSlash((base??'').trim())){
      try{found=releaseFromServer(await _fetchServer(nas),nas);}catch(_){/* GitHub then */}
    }
    if(found==null){
      try{found=releaseFromGithub(await _fetchGithub());}catch(_){/* unknown */}
    }
    checkedAt=DateTime.now();
    if(found!=null)latest=found;
    _set(found==null?WindowsUpdateState.unknown:available?WindowsUpdateState.available:WindowsUpdateState.upToDate);
  }

  void _fail(String key){failure=key;_set(WindowsUpdateState.failed);}

  /// Download, fingerprint, silent install; SARCADE then quits (the
  /// installer starts it again). The confirmation asked during a SOS or a
  /// mission is the business of the caller ([currentGuard]).
  Future<void> install() async {
    final r=latest;
    if(!supported||!installed||busy||r==null||!available)return;
    if(r.sha256==null){_fail('update.win.noHash');return;}
    failure=null;
    _set(WindowsUpdateState.downloading);
    try{
      final bytes=await _download(r,_baseUrl);
      _set(WindowsUpdateState.verifying);
      final hash=bytes.length>1<<20?await compute(sha256Hex,bytes):sha256Hex(bytes);
      if(hash!=r.sha256){
        writeStartupLog('mise à jour : empreinte différente pour ${r.version}, installation annulée');
        _fail('update.win.badHash');
        return;
      }
      final path=await _save('sarcade-windows-setup-${r.version.replaceAll(RegExp(r'[^0-9A-Za-z.]'),'-')}.exe',bytes);
      _set(WindowsUpdateState.installing);
      if(!await _start(path,windowsInstallerArguments)){_fail('update.win.failed');return;}
      writeStartupLog('mise à jour : installeur ${r.version} lancé, SARCADE se ferme');
      await Future<void>.delayed(quitDelay);
      _quit();
    }catch(_){
      _fail('update.win.failed');
    }
  }

  /// Link of « Télécharger »: the installer, or the page Téléchargements of
  /// the server for a portable copy (zip) (card « Téléchargements servis par
  /// le serveur SARCADE »), that of the NAS without a server, the latest
  /// major release of GitHub when only GitHub answered (10 Nov 2026).
  String get downloadUrl{
    final r=latest;
    if(installed&&r!=null)return r.url;
    if(r!=null&&r.source==WindowsUpdateSource.server&&r.serverUrl!=null)return '${r.serverUrl}/telechargements';
    if(r!=null&&r.source==WindowsUpdateSource.github)return githubLatestPageUrl;
    final base=_baseUrl;
    if(base!=null&&base.trim().isNotEmpty)return '${_trimSlash(base.trim())}/telechargements';
    return '${_trimSlash(nasUrl.trim())}/telechargements';
  }

  @override void dispose(){_timer?.cancel();super.dispose();}
}

/// Dot on the Paramètres button of the rail and on the À propos tab.
bool windowsUpdateAlert()=>WindowsUpdates.instance.supported&&WindowsUpdates.instance.available;

/// Map page: server of the session and what blocks an update (SOS in
/// progress, active mission).
void attachWindowsUpdates({required String baseUrl,required UpdateGuard Function() guard})=>
  WindowsUpdates.instance.attach(baseUrl,guard:guard);
