import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import 'account_api.dart';
import 'device_account.dart';
import 'my_devices_page.dart';
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

/// Above the map: the server refused the token of this device (revoked,
/// unknown), « Se connecter » offered. [onChanged] runs when the token of
/// the server comes or goes (real-time channel and rights read again).
class AccountBanner extends StatefulWidget {
  final String server, deviceId; final VoidCallback? onChanged;
  final AccountManager? account;
  const AccountBanner({super.key,required this.server,required this.deviceId,this.onChanged,this.account});
  @override State<AccountBanner> createState()=>_AccountBannerState();
}

class _AccountBannerState extends State<AccountBanner> {
  AccountManager get _account=>widget.account??AccountManager.instance;
  late String? _token=_account.sessionFor(widget.server)?.token;

  @override void initState(){super.initState();_account.addListener(_changed);}
  @override void dispose(){_account.removeListener(_changed);super.dispose();}

  void _changed(){
    final now=_account.sessionFor(widget.server)?.token;
    if(now!=_token){_token=now;widget.onChanged?.call();}
    if(mounted)setState((){});
  }

  @override
  Widget build(BuildContext context){
    final refused=_account.refusedFor(widget.server);
    if(refused==null||_token!=null)return const SizedBox.shrink();
    final t=Theme.of(context);
    return Material(key:const ValueKey('auth-banner'),color:t.colorScheme.tertiaryContainer,child:Padding(
      padding:const EdgeInsets.symmetric(horizontal:12,vertical:4),
      child:Row(children:[
        Icon(Icons.no_accounts_outlined,size:18,color:t.colorScheme.onTertiaryContainer),
        const SizedBox(width:8),
        Expanded(child:Text(S.t('auth.refused.$refused'),style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onTertiaryContainer))),
        TextButton(onPressed:()=>_account.clearRefused(widget.server),child:Text(S.t('auth.later'))),
        FilledButton(key:const ValueKey('auth-banner-signin'),
          onPressed:()=>unawaited(showSignInDialog(context,server:widget.server,deviceId:widget.deviceId,account:_account)),
          child:Text(S.t('auth.signIn'))),
      ])));
  }
}
