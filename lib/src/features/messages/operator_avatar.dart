/// Round avatar with initials (« Messages, avatar rond avec initiales »,
/// 30 Oct 2026): 2 or 3 letters on the operator colour, shared by the
/// bubbles, the conversation list and Équipes.
library;

import 'package:flutter/material.dart';

import '../profile/profile_photo.dart';
import 'conversations.dart';

/// The photo of the operator when he has one (lot 29, group 7), else the
/// initials.
Widget operatorAvatar(String id,{String? label,double radius=15,bool stale=false})=>ValueListenableBuilder<Map>(
  valueListenable:ProfilePhotos.instance,builder:(c,photos,_){
    final photo=ProfilePhotos.instance.of(id);
    if(photo!=null){
      return Opacity(opacity:stale?0.45:1,child:CircleAvatar(radius:radius,backgroundColor:Color(authorColor(id)),backgroundImage:MemoryImage(photo)));
    }
    return _initials(id,label:label,radius:radius,stale:stale);
  });

Widget _initials(String id,{String? label,required double radius,required bool stale}){
  final letters=avatarInitials(label==null||label.trim().isEmpty?id:label);
  return CircleAvatar(radius:radius,backgroundColor:Color(authorColor(id)).withValues(alpha:stale?0.45:1),foregroundColor:Colors.white,
    child:Text(letters,style:TextStyle(fontSize:letters.length>2?radius*0.58:radius*0.72,fontWeight:FontWeight.w700)));
}
