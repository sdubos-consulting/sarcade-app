import 'package:flutter/foundation.dart';
import '../access/access_session.dart' show accessOrigin;
import '../models/comm_group.dart' as roles;
import '../services/sarcade_api.dart';
import 'account_api.dart';
import 'device_account.dart';
import 'sign_in_dialog.dart' show enrolmentLabel, thisPlatform;

/// Transition period (docs/directory-v0.1.md of the server): until its end
/// the devices keep the rights of before, nothing changes on screen.
class TransitionState {
  final bool active; final DateTime? until; final bool pcoByName;
  /// `legacy` during the transition, `core` after.
  final String anonymousRights;
  const TransitionState({this.active=true,this.until,this.pcoByName=true,this.anonymousRights='legacy'});

  factory TransitionState.fromJson(Object? j){
    if(j is! Map)return const TransitionState();
    return TransitionState(active:j['active']!=false,until:DateTime.tryParse('${j['until']??''}'),
      pcoByName:j['pco_by_name']!=false,anonymousRights:'${j['anonymous_rights']??'legacy'}');
  }
}

/// Rights of this device read on `/me` (lot 26): groups, administration
/// rights, usable modules, transition. The server stays the judge of every
/// call; the application only hides what is not allowed.
class MyRights {
  final String? email, via;
  final List<Map<String,dynamic>> groups, adminRights, moduleRights;
  final List<String> modules;
  /// The server said which modules are usable (older servers do not).
  final bool modulesKnown;
  final bool isServerAdmin, canAdminister;
  final int rightsVersion;
  final TransitionState transition;
  /// Administrators (lot 28): deadlines at 30 days or less, and the worst
  /// colour (`orange`, `red`, `expired`); red dot on Paramètres.
  final int deadlineAlerts;
  final String? deadlineWorst;
  const MyRights({this.email,this.via,this.groups=const [],this.adminRights=const [],this.moduleRights=const [],this.modules=const [],
    this.modulesKnown=false,this.isServerAdmin=false,this.canAdminister=false,this.rightsVersion=0,this.transition=const TransitionState(),
    this.deadlineAlerts=0,this.deadlineWorst});

  static List<Map<String,dynamic>> _maps(Object? v)=>[for(final x in (v as List?)??const [])if(x is Map)Map<String,dynamic>.from(x)];

  factory MyRights.fromMe(Map<String,dynamic> me)=>MyRights(
    email:me['email'] as String?,via:me['via'] as String?,
    groups:_maps(me['groups']),adminRights:_maps(me['admin_rights']),moduleRights:_maps(me['module_rights']),
    modules:[for(final m in (me['modules'] as List?)??const [])'$m'],modulesKnown:me['modules'] is List,
    isServerAdmin:me['is_server_admin']==true,canAdminister:me['can_administer']==true,
    rightsVersion:(me['rights_version'] as num?)?.toInt()??0,
    transition:TransitionState.fromJson(me['transition']),
    deadlineAlerts:((me['deadlines'] as Map?)?['alerts'] as num?)?.toInt()??0,
    deadlineWorst:(me['deadlines'] as Map?)?['worst'] as String?);

  /// Server of lot 26 (directory, transition).
  bool get directory=>modulesKnown;

  /// Menus of [module] shown: always during the transition (nothing changes
  /// for the person) and with an older server; afterwards only the modules
  /// of the account (habilitation and licence of the organisation).
  bool allows(String module)=>!modulesKnown||transition.active||modules.contains(module);

  /// Organiser of events somewhere (event creation, « Accès »).
  bool get organizes=>isServerAdmin||adminRights.any((r)=>r['right']=='event_organizer'||r['right']=='group_admin');
}

/// Rights of the server of the open map, for every screen.
class RightsState extends ChangeNotifier {
  RightsState();
  static final instance=RightsState();

  String? _server; MyRights? _rights;
  /// Rights of [server], null when not read (offline at start, older server).
  MyRights? of(String server)=>_server!=null&&_server==accessOrigin(server)?_rights:null;
  MyRights? get current=>_rights;

  /// Answer of `/me` for [server]; null (older server, not read) keeps the
  /// screens as before.
  void apply(String server,Map<String,dynamic>? me){
    final origin=accessOrigin(server);
    final next=me==null?null:MyRights.fromMe(me);
    if(next==null&&_server==origin&&_rights!=null)return; // offline: the last rights stay
    _server=origin; _rights=next;
    roles.pcoByName=next?.transition.pcoByName??true;
    notifyListeners();
  }

  /// See [MyRights.allows]; true while unknown.
  bool allows(String module)=>_rights?.allows(module)??true;
  bool get canAdminister=>_rights?.canAdminister??false;
}

final _accessTried=<String>{};

/// Reads `/me` (start, reconnection, `rights.changed`, `transition.changed`,
/// `device.revoked`); a person checked by Cloudflare Access without a
/// device token is enrolled once, without code (`POST /auth/access/enroll`).
Future<Map<String,dynamic>?> refreshRights(SarcadeApi api,{required String deviceId,AccountManager? account,RightsState? state,
    AccountApi? accountApi}) async {
  final a=account??AccountManager.instance, s=state??RightsState.instance;
  var me=await api.me();
  if(me!=null&&me['via']=='access'&&a.sessionFor(api.baseUrl)==null&&_accessTried.add(accessOrigin(api.baseUrl))){
    final enrol=accountApi??AccountApi(api.baseUrl);
    try{
      final session=DeviceSession.fromEnrolment(await enrol.accessEnroll(deviceId:deviceId,
        label:enrolmentLabel(deviceId,thisPlatform),platform:thisPlatform));
      if(session!=null){await a.save(api.baseUrl,session);me=await api.me()??me;}
    }catch(e){
      debugPrint('SARCADE enrolment by Cloudflare Access refused: $e');
    }finally{if(accountApi==null)enrol.close();}
  }
  s.apply(api.baseUrl,me);
  return me;
}
