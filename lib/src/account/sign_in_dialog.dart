import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/strings.dart';
import '../operations/event_settings.dart' show platformName;
import '../features/map/stations.dart' show platformLabel;
import 'account_api.dart';
import 'api_error.dart';
import 'device_account.dart';

/// Platform of this device, as the server names it.
String get thisPlatform=>platformName(isWeb:kIsWeb,targetPlatform:defaultTargetPlatform.name);

/// Name of the enrolled device in « Mes appareils » (« TERRAIN-01 · Android »).
String enrolmentLabel(String deviceId,String platform)=>[if(deviceId.trim().isNotEmpty)deviceId.trim(),platformLabel(platform)].join(' · ');

/// « Se connecter » (lot 26): email, code received by email, then this
/// device is enrolled and keeps its token. True once connected.
Future<bool> showSignInDialog(BuildContext context,{required String server,required String deviceId,AccountApi? api,AccountManager? account}) async {
  final own=api==null;
  final a=api??AccountApi(server);
  try{
    final ok=await showDialog<bool>(context:context,builder:(_)=>SignInDialog(server:server,deviceId:deviceId,api:a,
      account:account??AccountManager.instance));
    return ok==true;
  }finally{
    if(own)a.close();
  }
}

/// Readable sentence of a refusal of the sign-in (contract of the server).
String authErrorText(Object e){
  if(e is! ApiError)return S.t('auth.offline');
  final wait=e.retryAfterS??60;
  return switch(e.code){
    'invalid_email'||'resend_too_soon'||'mail_failed'||'no_code'||'code_expired'||'too_many_attempts'||'account_disabled'||'access_email_required'=>
      S.t('auth.error.${e.code}',{'s':wait}),
    'too_many_codes'||'too_many_requests'=>S.t('auth.error.${e.code}',{'min':(wait/60).ceil()}),
    'invalid_code'=>S.t('auth.error.invalid_code',{'n':(e.data['attempts_left'] as num?)?.toInt()??0}),
    _=>S.t('auth.error.other',{'e':'HTTP ${e.status}${e.code.isEmpty?'':' · ${e.code}'}'}),
  };
}

class SignInDialog extends StatefulWidget {
  final String server, deviceId; final AccountApi api; final AccountManager account;
  const SignInDialog({super.key,required this.server,required this.deviceId,required this.api,required this.account});
  @override State<SignInDialog> createState()=>_SignInDialogState();
}

class _SignInDialogState extends State<SignInDialog> {
  final _email=TextEditingController(), _code=TextEditingController();
  /// Email checked by Cloudflare Access: enrolment without code.
  String? _accessEmail;
  bool _codeStep=false, _busy=false, _simulated=false;
  int _codeLength=6, _resendAfter=60, _wait=0;
  String? _error;
  Timer? _timer;

  @override void initState(){super.initState();unawaited(_prepare());}
  @override void dispose(){_timer?.cancel();_email.dispose();_code.dispose();super.dispose();}

  Future<void> _prepare() async {
    try{
      final s=await widget.api.state();
      _codeLength=(s['code_length'] as num?)?.toInt()??6;
      _resendAfter=(s['resend_after_s'] as num?)?.toInt()??60;
    }catch(_){/* defaults of the contract */}
    try{
      final me=await widget.api.me();
      final email='${me?['email']??''}';
      if(me?['via']=='access'&&email.isNotEmpty&&mounted)setState(()=>_accessEmail=email);
    }catch(_){/* no Access */}
  }

  void _countdown(int seconds){
    _timer?.cancel();
    setState(()=>_wait=seconds);
    _timer=Timer.periodic(const Duration(seconds:1),(t){
      if(!mounted){t.cancel();return;}
      setState(()=>_wait=_wait>0?_wait-1:0);
      if(_wait==0)t.cancel();
    });
  }

  Future<void> _run(Future<void> Function() step) async {
    if(_busy)return;
    setState((){_busy=true;_error=null;});
    try{await step();}
    catch(e){if(mounted)setState(()=>_error=authErrorText(e));}
    finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _request()=>_run(() async {
    final email=_email.text.trim();
    if(!email.contains('@')){setState(()=>_error=S.t('auth.error.invalid_email'));return;}
    try{
      final r=await widget.api.requestCode(email);
      if(!mounted)return;
      _codeLength=(r['code_length'] as num?)?.toInt()??_codeLength;
      setState((){_codeStep=true;_simulated=r['delivery']=='simulated';_code.clear();});
      _countdown((r['resend_after_s'] as num?)?.toInt()??_resendAfter);
    }on ApiError catch(e){
      // Too soon: the code already sent is still good.
      if(e.code=='resend_too_soon'&&mounted){setState(()=>_codeStep=true);_countdown(e.retryAfterS??_resendAfter);}
      rethrow;
    }
  });

  Future<void> _verify()=>_run(() async {
    final code=_code.text.trim();
    if(code.length!=_codeLength)return;
    final r=await widget.api.verifyCode(email:_email.text,code:code,deviceId:widget.deviceId,
      label:enrolmentLabel(widget.deviceId,thisPlatform),platform:thisPlatform);
    await _enrolled(r);
  });

  Future<void> _withAccess()=>_run(() async {
    final r=await widget.api.accessEnroll(deviceId:widget.deviceId,label:enrolmentLabel(widget.deviceId,thisPlatform),platform:thisPlatform);
    await _enrolled(r);
  });

  Future<void> _enrolled(Map<String,dynamic> r) async {
    final s=DeviceSession.fromEnrolment(r);
    if(s==null){setState(()=>_error=S.t('auth.error.other',{'e':'token'}));return;}
    await widget.account.save(widget.server,s);
    if(!mounted)return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content:Text(S.t('auth.connected',{'email':s.email}))));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context){
    final t=Theme.of(context);
    final children=<Widget>[
      if(!_codeStep)...[
        if(_accessEmail!=null)...[
          FilledButton.icon(key:const ValueKey('auth-access'),onPressed:_busy?null:_withAccess,icon:const Icon(Icons.verified_user_outlined),
            label:Text(S.t('auth.withAccess',{'email':_accessEmail}),overflow:TextOverflow.ellipsis)),
          Padding(padding:const EdgeInsets.only(top:4,bottom:12),child:Text(S.t('auth.withAccessHelp'),style:t.textTheme.bodySmall)),
        ],
        Text(S.t('auth.signInHelp'),style:t.textTheme.bodyMedium),
        const SizedBox(height:12),
        TextField(key:const ValueKey('auth-email'),controller:_email,autofocus:_accessEmail==null,keyboardType:TextInputType.emailAddress,
          autocorrect:false,textInputAction:TextInputAction.send,onSubmitted:(_)=>_request(),
          decoration:InputDecoration(labelText:S.t('auth.email'),hintText:'prenom.nom@adrasec78.fr')),
      ]else...[
        Text(S.t('auth.codeSent',{'email':_email.text.trim()}),style:t.textTheme.bodyMedium),
        if(_simulated)Padding(padding:const EdgeInsets.only(top:4),child:Text(S.t('auth.simulated'),key:const ValueKey('auth-simulated'),
          style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.tertiary))),
        const SizedBox(height:12),
        TextField(key:const ValueKey('auth-code'),controller:_code,autofocus:true,keyboardType:TextInputType.number,
          inputFormatters:[FilteringTextInputFormatter.digitsOnly,LengthLimitingTextInputFormatter(_codeLength)],
          autofillHints:const [AutofillHints.oneTimeCode],textInputAction:TextInputAction.done,
          style:t.textTheme.headlineSmall?.copyWith(letterSpacing:6),
          onChanged:(v){setState((){});if(v.trim().length==_codeLength)unawaited(_verify());},
          onSubmitted:(_)=>_verify(),
          decoration:InputDecoration(labelText:S.t('auth.code',{'n':_codeLength}),counterText:'')),
        const SizedBox(height:4),
        Wrap(spacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
          TextButton(key:const ValueKey('auth-resend'),onPressed:_busy||_wait>0?null:_request,
            child:Text(_wait>0?S.t('auth.resendIn',{'s':_wait}):S.t('auth.resend'))),
          TextButton(key:const ValueKey('auth-change-email'),onPressed:_busy?null:(){_timer?.cancel();setState((){_codeStep=false;_error=null;_wait=0;});},
            child:Text(S.t('auth.changeEmail'))),
        ]),
      ],
      if(_error!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(_error!,key:const ValueKey('auth-error'),style:TextStyle(color:t.colorScheme.error))),
      if(_busy)const Padding(padding:EdgeInsets.only(top:12),child:LinearProgressIndicator()),
    ];
    return AlertDialog(
      title:Text(S.t('auth.title')),
      content:SizedBox(width:420,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:children))),
      actions:[
        TextButton(onPressed:()=>Navigator.of(context).pop(false),child:Text(S.t('common.cancel'))),
        if(!_codeStep)FilledButton(key:const ValueKey('auth-request'),onPressed:_busy?null:_request,child:Text(S.t('auth.requestCode')))
        else FilledButton(key:const ValueKey('auth-verify'),onPressed:_busy||_code.text.trim().length!=_codeLength?null:_verify,child:Text(S.t('auth.verify'))),
      ],
    );
  }
}
