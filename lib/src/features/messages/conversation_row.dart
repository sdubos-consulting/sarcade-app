/// Line of the list of the conversations like WhatsApp (card « Messages :
/// ligne de conversation comme WhatsApp », lot 29.3) and its order (card
/// « Favoris : en haut de la liste au lieu d'un filtre », Messages part).
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

/// One conversation of any kind (SARCADE, MeshCore, Meshtastic).
typedef ConvEntry=({String favKey,String title,String preview,DateTime? at,int unread,bool fav,Widget avatar,VoidCallback onTap,Key key,bool selected});

/// Favourites first, then the ones with something unread, then the others;
/// in each block, the last message first.
List<ConvEntry> sortConversations(Iterable<ConvEntry> all){
  int block(ConvEntry e)=>e.fav?0:e.unread>0?1:2;
  final out=[...all];
  out.sort((a,b){
    final c=block(a).compareTo(block(b)); if(c!=0)return c;
    final ta=a.at, tb=b.at;
    if(ta==null&&tb==null)return a.title.compareTo(b.title);
    if(ta==null)return 1; if(tb==null)return -1;
    return tb.compareTo(ta);
  });
  return out;
}

/// « 14:05 » today, « hier », « mardi » in the last 7 days, then « 28/10 ».
String conversationTime(DateTime t,DateTime now){
  final l=t.toLocal(), n=now.toLocal();
  final day=DateTime(l.year,l.month,l.day), today=DateTime(n.year,n.month,n.day);
  final diff=today.difference(day).inDays;
  String two(int v)=>v.toString().padLeft(2,'0');
  if(diff<=0)return '${two(l.hour)}:${two(l.minute)}';
  if(diff==1)return S.t('messages.yesterday');
  if(diff<7)return S.t('weekday.long.${l.weekday}');
  return '${two(l.day)}/${two(l.month)}';
}

/// The line: avatar, name, preview on two lines; date and unread count in
/// SARCADE blue when there is something new, all in grey otherwise.
class ConversationRow extends StatelessWidget {
  final ConvEntry entry; final VoidCallback? onLongPress; final Widget? hoverStar; final DateTime? now;
  /// « Sourdine » (lot 29, group 7): crossed speaker after the name.
  final bool muted;
  /// A mention « @ » of me still unread (lot 29, group 7).
  final bool mention;
  const ConversationRow({super.key,required this.entry,this.onLongPress,this.hoverStar,this.now,this.muted=false,this.mention=false});
  @override Widget build(BuildContext context){
    final t=Theme.of(context); final s=t.colorScheme; final e=entry;
    final news=e.unread>0;
    return ListTile(key:e.key,selected:e.selected,selectedTileColor:s.primaryContainer.withValues(alpha:0.45),
      contentPadding:const EdgeInsets.symmetric(horizontal:12),
      leading:e.avatar,isThreeLine:e.preview.isNotEmpty,
      title:Row(children:[
        Expanded(child:Text(e.title,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontWeight:news?FontWeight.w700:FontWeight.w600))),
        if(muted)Padding(padding:const EdgeInsets.only(right:4),child:Icon(Icons.volume_off,key:const ValueKey('conv-muted'),size:16,color:s.onSurfaceVariant)),
        if(e.at!=null)Text(conversationTime(e.at!,now??DateTime.now()),style:TextStyle(fontSize:12,color:news?s.primary:s.onSurfaceVariant,fontWeight:news?FontWeight.w600:null)),
      ]),
      subtitle:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Expanded(child:Text(e.preview,maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(color:s.onSurfaceVariant))),
        if(e.fav)const Padding(padding:EdgeInsets.only(left:4,top:2),child:Icon(Icons.star,size:16,color:Color(0xFFF9A825)))
        else ?hoverStar,
        if(mention)Container(key:const ValueKey('conv-mention'),margin:const EdgeInsets.only(left:6,top:2),width:20,height:20,alignment:Alignment.center,
          decoration:BoxDecoration(color:s.primary,shape:BoxShape.circle),
          child:Text('@',style:TextStyle(color:s.onPrimary,fontSize:12,fontWeight:FontWeight.w800))),
        if(news)Container(margin:const EdgeInsets.only(left:6,top:2),padding:const EdgeInsets.symmetric(horizontal:7,vertical:2),
          decoration:BoxDecoration(color:s.primary,borderRadius:BorderRadius.circular(12)),
          child:Text('${e.unread}',style:TextStyle(color:s.onPrimary,fontSize:11,fontWeight:FontWeight.w700))),
      ]),
      onLongPress:onLongPress,onTap:e.onTap);
  }
}
