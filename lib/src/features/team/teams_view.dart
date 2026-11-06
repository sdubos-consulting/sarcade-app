/// Équipes (lot 29.4, cards « écran plus dense », « Mon statut en une seule
/// pastille déroulante », « champ de recherche » and « Favoris en haut de la
/// liste »): search and highlighted text, pure code where possible.
library;

import 'package:flutter/material.dart';

/// The search finds the name, the callsign, the team and the status
/// (« sur place » finds all those on site); case and accents ignored.
bool teamMatches(String query,{required String name,String? callsign,String? team,String? status}){
  final q=foldText(query.trim());
  if(q.isEmpty)return true;
  return [name,callsign,team,status].any((v)=>v!=null&&foldText(v).contains(q));
}

/// Lower case without accents.
String foldText(String s){
  const from='àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ', to='aaaaaaceeeeiiiinooooouuuuyyoa';
  final b=StringBuffer();
  for(final r in s.toLowerCase().runes){final c=String.fromCharCode(r);final i=from.indexOf(c);b.write(i<0?c:to[i]);}
  return b.toString();
}

/// [text] with the found part in bold.
Widget highlighted(String text,String query,{TextStyle? style}){
  final q=foldText(query.trim());
  final i=q.isEmpty?-1:foldText(text).indexOf(q);
  if(i<0)return Text(text,style:style,maxLines:1,overflow:TextOverflow.ellipsis);
  return Text.rich(TextSpan(style:style,children:[
    TextSpan(text:text.substring(0,i)),
    TextSpan(text:text.substring(i,i+q.length),style:const TextStyle(fontWeight:FontWeight.w800,backgroundColor:Color(0x33FFC107))),
    TextSpan(text:text.substring(i+q.length)),
  ]),maxLines:1,overflow:TextOverflow.ellipsis);
}
