import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import 'admin_errors.dart';

/// Colour of a group (`#RRGGBB`), grey when unknown.
Color groupColor(Object? hex){
  final h='${hex??''}'.replaceAll('#','');
  final v=int.tryParse(h.length==6?'FF$h':h,radix:16);
  return v==null?const Color(0xFF78909C):Color(v);
}
/// `#RRGGBB` of an ARGB colour.
String groupHex(int argb)=>'#${(argb&0xFFFFFF).toRadixString(16).padLeft(6,'0').toUpperCase()}';

/// « 31/12/2026 », local date; empty when unknown.
String adminDate(Object? v){
  final t=v is DateTime?v.toLocal():DateTime.tryParse('${v??''}')?.toLocal();
  if(t==null)return '';
  String two(int x)=>x.toString().padLeft(2,'0');
  return '${two(t.day)}/${two(t.month)}/${t.year}';
}

/// The refusal in a window: a cycle or the last administrator need to be
/// read, not glimpsed.
Future<void> showAdminError(BuildContext context,Object e,{String Function(String right)? rightLabel})=>showDialog<void>(context:context,
  builder:(c)=>AlertDialog(key:const ValueKey('admin-error'),title:Text(S.t('admin.refused')),
    content:Text(adminErrorText(e,rightLabel:rightLabel)),
    actions:[FilledButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.ok')))]));

Future<bool> confirmAdmin(BuildContext context,String title,{String? body,String? action})async=>await showDialog<bool>(context:context,
  builder:(c)=>AlertDialog(title:Text(title),content:body==null?null:Text(body),actions:[
    TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
    FilledButton(key:const ValueKey('admin-confirm'),onPressed:()=>Navigator.pop(c,true),child:Text(action??S.t('common.ok'))),
  ]))==true;

/// End date chosen in a calendar: the end of that day, local time; null
/// when cancelled.
Future<DateTime?> pickEndDate(BuildContext context,{DateTime? initial}) async {
  final now=DateTime.now();
  final d=await showDatePicker(context:context,firstDate:now,lastDate:DateTime(now.year+5),
    initialDate:initial!=null&&initial.isAfter(now)?initial.toLocal():now.add(const Duration(days:30)));
  return d==null?null:DateTime(d.year,d.month,d.day,23,59);
}

/// Title of a block of a page of the console.
class AdminHeading extends StatelessWidget {
  final String text; final List<Widget> actions;
  const AdminHeading(this.text,{super.key,this.actions=const []});
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(top:20,bottom:4),child:Row(children:[
    Expanded(child:Text(text,style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w600))),
    ...actions,
  ]));
}

/// Page of the console: width kept readable on a computer.
class AdminScaffold extends StatelessWidget {
  final String title; final Widget body; final List<Widget>? actions; final Widget? floating;
  const AdminScaffold({super.key,required this.title,required this.body,this.actions,this.floating});
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(title),actions:actions),
    floatingActionButton:floating,
    body:SafeArea(child:body));
}

/// Grey line under a title.
class AdminHint extends StatelessWidget {
  final String text; final Color? color;
  const AdminHint(this.text,{super.key,this.color});
  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    return Text(text,style:t.textTheme.bodySmall?.copyWith(color:color??t.colorScheme.onSurfaceVariant));
  }
}
