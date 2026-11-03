import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import '../offline/local_store.dart';
import 'account_api.dart';
import 'device_account.dart';
import 'my_devices_page.dart';
import 'rights.dart';
import 'sign_in_dialog.dart';

/// Signs this device out: the server revokes its token, the device forgets
/// it even when the server cannot be reached.
Future<void> signOutDevice(String server,{AccountApi? api,AccountManager? account}) async {
  final a=api??AccountApi(server);
  try{await a.logout();}catch(_){/* forgotten here anyway */}
  finally{if(api==null)a.close();}
  await (account??AccountManager.instance).forget(server);
}

/// Paramètres › Profil › Compte (lot 26): « Se connecter », or the email
/// with « Mes appareils » and « Se déconnecter ».
class AccountSection extends StatelessWidget {
  final String server, deviceId;
  final Widget Function(String label,{String? help,required Widget child}) row;
  final AccountManager? account;
  const AccountSection({super.key,required this.server,required this.deviceId,required this.row,this.account});

  AccountManager get _account=>account??AccountManager.instance;

  Future<void> _signOut(BuildContext context,DeviceSession s) async {
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:Text(S.t('auth.signOutAsk',{'email':s.email})),
      content:Text(S.t('auth.signOutBody')),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
        FilledButton(key:const ValueKey('auth-signout-ok'),onPressed:()=>Navigator.pop(c,true),child:Text(S.t('auth.signOut'))),
      ]));
    if(ok==true)await signOutDevice(server,account:_account);
  }

  @override
  Widget build(BuildContext context)=>ListenableBuilder(listenable:_account,builder:(context,_){
    final s=_account.sessionFor(server);
    final refused=_account.refusedFor(server);
    if(s==null){
      return row(S.t('auth.account'),help:refused!=null?S.t('auth.refused.$refused'):S.t('auth.signInHelp'),child:Wrap(spacing:8,runSpacing:8,
        crossAxisAlignment:WrapCrossAlignment.center,children:[
          Text(S.t('auth.signedOut')),
          FilledButton.icon(key:const ValueKey('auth-signin'),icon:const Icon(Icons.login),label:Text(S.t('auth.signIn')),
            onPressed:()=>unawaited(showSignInDialog(context,server:server,deviceId:deviceId,account:_account))),
        ]));
    }
    return row(S.t('auth.account'),help:S.t('auth.signedAs',{'email':s.email}),child:Wrap(spacing:8,runSpacing:8,
      crossAxisAlignment:WrapCrossAlignment.center,children:[
        OutlinedButton.icon(key:const ValueKey('auth-devices'),icon:const Icon(Icons.devices_outlined),label:Text(S.t('auth.devices')),
          onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>MyDevicesPage(server:server,account:_account)))),
        OutlinedButton.icon(key:const ValueKey('auth-signout'),icon:const Icon(Icons.logout),label:Text(S.t('auth.signOut')),
          onPressed:()=>_signOut(context,s)),
      ]));
  });
}

/// Preference: when « Plus tard » was chosen on the invitation.
const signInLaterKey='auth.inviteLater';
/// The invitation comes back a week after « Plus tard ».
const signInLaterFor=Duration(days:7);

/// Invitation to sign in for a device without account on a server of lot
/// 26 (decision 6: « proposent Se connecter »), discreet: not again for a
/// week after « Plus tard ».
bool showsSignInInvite({required MyRights? rights,required bool signedIn,DateTime? later,required DateTime now})=>
  rights!=null&&rights.directory&&!signedIn&&(later==null||now.difference(later)>=signInLaterFor);

/// Above the map: the server refused the token of this device (revoked,
/// unknown), « Se connecter » offered. With [invite] (top of Paramètres),
/// also the discreet invitation of a device without account; not over the
/// map, whose layout it would move. [onChanged] runs when the token of the
/// server comes or goes (real-time channel and rights read again).
class AccountBanner extends StatefulWidget {
  final String server, deviceId; final VoidCallback? onChanged;
  final AccountManager? account; final RightsState? rights;
  /// Keeps « Plus tard » of the invitation.
  final LocalStore? store;
  final bool invite;
  const AccountBanner({super.key,required this.server,required this.deviceId,this.onChanged,this.account,this.rights,this.store,this.invite=false});
  @override State<AccountBanner> createState()=>_AccountBannerState();
}

class _AccountBannerState extends State<AccountBanner> {
  AccountManager get _account=>widget.account??AccountManager.instance;
  RightsState get _rights=>widget.rights??RightsState.instance;
  String? _token;
  DateTime? _later;

  @override void initState(){
    super.initState();
    _token=_account.sessionFor(widget.server)?.token;
    _later=DateTime.tryParse(widget.store?.preference(signInLaterKey)??'');
    _account.addListener(_changed);_rights.addListener(_rebuild);
  }
  @override void dispose(){_account.removeListener(_changed);_rights.removeListener(_rebuild);super.dispose();}
  void _rebuild(){if(mounted)setState((){});}

  void _notNow(){
    final now=DateTime.now();
    setState(()=>_later=now);
    unawaited(widget.store?.setPreference(signInLaterKey,now.toUtc().toIso8601String()));
  }

  void _changed(){
    final now=_account.sessionFor(widget.server)?.token;
    if(now!=_token){_token=now;widget.onChanged?.call();}
    if(mounted)setState((){});
  }

  @override
  Widget build(BuildContext context){
    final refused=_token==null?_account.refusedFor(widget.server):null;
    final rights=_rights.of(widget.server);
    final invite=widget.invite&&refused==null&&showsSignInInvite(rights:rights,signedIn:_token!=null,later:_later,now:DateTime.now());
    if(refused==null&&!invite)return const SizedBox.shrink();
    final t=Theme.of(context);
    final until=rights?.transition.until;
    final text=refused!=null?S.t('auth.refused.$refused')
      :rights!.transition.active?(until==null?S.t('auth.invite'):S.t('auth.inviteUntil',{'date':accountDate(until.toIso8601String()).split(' ').first}))
      :S.t('auth.inviteAfter');
    final color=refused!=null?t.colorScheme.tertiaryContainer:t.colorScheme.surfaceContainerHigh;
    final onColor=refused!=null?t.colorScheme.onTertiaryContainer:t.colorScheme.onSurfaceVariant;
    return Material(key:ValueKey(refused!=null?'auth-banner':'auth-invite'),color:color,child:Padding(
      padding:const EdgeInsets.symmetric(horizontal:12,vertical:4),
      child:Row(children:[
        Icon(refused!=null?Icons.no_accounts_outlined:Icons.account_circle_outlined,size:18,color:onColor),
        const SizedBox(width:8),
        Expanded(child:Text(text,style:t.textTheme.bodySmall?.copyWith(color:onColor))),
        TextButton(onPressed:refused!=null?()=>_account.clearRefused(widget.server):_notNow,child:Text(S.t('auth.later'))),
        FilledButton(key:const ValueKey('auth-banner-signin'),
          onPressed:()=>unawaited(showSignInDialog(context,server:widget.server,deviceId:widget.deviceId,account:_account)),
          child:Text(S.t('auth.signIn'))),
      ])));
  }
}
