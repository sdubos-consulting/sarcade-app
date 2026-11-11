import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import '../features/map/stations.dart' show platformLabel;
import 'account_api.dart';
import 'api_error.dart';
import 'device_account.dart';
import 'sign_in_dialog.dart' show authErrorText;

/// « 03/11/2026 14:05 », local time; empty when unknown.
String accountDate(Object? v){
  final t=DateTime.tryParse('${v??''}')?.toLocal();
  if(t==null)return '';
  String two(int x)=>x.toString().padLeft(2,'0');
  return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
}

/// « Mes appareils » (lot 26): the devices enrolled on my account, this one
/// first, each revocable.
class MyDevicesPage extends StatefulWidget {
  final String server; final AccountApi? api; final AccountManager? account;
  const MyDevicesPage({super.key,required this.server,this.api,this.account});
  @override State<MyDevicesPage> createState()=>_MyDevicesPageState();
}

class _MyDevicesPageState extends State<MyDevicesPage> {
  late final AccountApi _api=widget.api??AccountApi(widget.server);
  AccountManager get _account=>widget.account??AccountManager.instance;
  List<Map<String,dynamic>>? _devices; String? _error;

  @override void initState(){super.initState();_load();}
  @override void dispose(){if(widget.api==null)_api.close();super.dispose();}

  Future<void> _load() async {
    try{
      final list=await _api.myDevices();
      list.sort((a,b)=>a['current']==true?-1:b['current']==true?1:'${b['last_seen_at']??''}'.compareTo('${a['last_seen_at']??''}'));
      if(mounted)setState((){_devices=list;_error=null;});
    }catch(e){
      if(mounted)setState(()=>_error=authErrorText(e));
    }
  }

  Future<void> _revoke(Map<String,dynamic> d) async {
    final name='${d['label']??d['device_id']??''}';
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:Text(S.t('auth.revokeAsk',{'name':name})),
      content:Text(S.t('auth.revokeBody')),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
        FilledButton(key:const ValueKey('device-revoke-ok'),onPressed:()=>Navigator.pop(c,true),child:Text(S.t('auth.revoke'))),
      ]));
    if(ok!=true||!mounted)return;
    final m=ScaffoldMessenger.of(context);
    try{
      await _api.revokeMyDevice('${d['id']}');
      // This device: its token is no longer valid.
      if(d['current']==true)await _account.forget(widget.server);
      m.showSnackBar(SnackBar(content:Text(S.t('auth.revoked'))));
      if(d['current']==true){if(mounted)Navigator.of(context).maybePop();return;}
      await _load();
    }on ApiError catch(e){
      m.showSnackBar(SnackBar(content:Text(authErrorText(e))));
    }catch(_){
      m.showSnackBar(SnackBar(content:Text(S.t('auth.offline'))));
    }
  }

  @override
  Widget build(BuildContext context){
    final t=Theme.of(context);
    final list=_devices;
    return Scaffold(
      appBar:AppBar(title:Text(S.t('auth.devices'))),
      body:SafeArea(child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:720),child:_error!=null
        ? ListView(padding:const EdgeInsets.all(20),children:[Text(_error!,style:TextStyle(color:t.colorScheme.error)),
            const SizedBox(height:12),Align(alignment:Alignment.centerLeft,child:OutlinedButton(onPressed:_load,child:Text(S.t('common.retry'))))])
        : list==null?const Center(child:CircularProgressIndicator())
        : list.isEmpty?Center(child:Text(S.t('auth.devicesNone')))
        : ListView.separated(padding:const EdgeInsets.symmetric(vertical:8),itemCount:list.length,separatorBuilder:(_,_)=>const Divider(height:1),
            itemBuilder:(c,i){
              final d=list[i];
              final current=d['current']==true;
              final platform='${d['platform']??''}';
              return ListTile(key:ValueKey('my-device-${d['id']}'),
                leading:Icon(platform=='web'?Icons.public:platform=='windows'||platform=='linux'||platform=='macos'?Icons.computer:Icons.smartphone),
                title:Text([if('${d['label']??''}'.isNotEmpty)'${d['label']}'else '${d['device_id']??''}',if(current)S.t('auth.thisDevice')].join(' · ')),
                subtitle:Text([
                  if(platform.isNotEmpty)platformLabel(platform),
                  S.t('auth.method.${d['method']=='access'?'access':'email_code'}'),
                  if(accountDate(d['created_at']).isNotEmpty)S.t('auth.enrolled',{'date':accountDate(d['created_at'])}),
                  if(accountDate(d['last_seen_at']).isNotEmpty)S.t('auth.lastSeen',{'date':accountDate(d['last_seen_at'])}),
                ].join(' · ')),
                trailing:TextButton(key:ValueKey('my-device-revoke-${d['id']}'),onPressed:()=>_revoke(d),child:Text(S.t('auth.revoke'))),
              );
            })))),
    );
  }
}
