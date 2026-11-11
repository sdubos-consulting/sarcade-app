/// Phone: a tab of the bottom bar touched again (card « Menu du bas :
/// toucher Messages plusieurs fois ne doit jamais revenir à la carte »,
/// validated on 5 Nov 2026, 18 h 24). Messages: a conversation open comes
/// back to the list, the list goes back to its top; Équipes and Outils go
/// back to their top. Only « Carte » shows the map.
library;

import 'package:flutter/widgets.dart';

import '../messages/messages_nav.dart';

/// Messages touched while shown: back to the list, or the list to its top.
/// Never closes Messages.
void messagesTouchedAgain(MessagesNavigator nav,{required VoidCallback toTop}){
  if(!nav.backToList())toTop();
}

/// Brings every vertical list under [context] back to its top (the lists of
/// a tab; the horizontal ones, chips or pages, are left as they are).
void scrollTabToTop(BuildContext? context){
  if(context==null)return;
  void visit(Element e){
    if(e is StatefulElement){
      final s=e.state;
      if(s is ScrollableState&&s.axisDirection==AxisDirection.down){
        final p=s.position;
        if(p.hasContentDimensions&&p.pixels>p.minScrollExtent){
          p.animateTo(p.minScrollExtent,duration:const Duration(milliseconds:300),curve:Curves.easeOut);
        }
      }
    }
    e.visitChildren(visit);
  }
  context.visitChildElements(visit);
}
