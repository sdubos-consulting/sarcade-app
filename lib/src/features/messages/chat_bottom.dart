/// Opening of a conversation on its last message (lot 19, card « Messages :
/// ouvrir une conversation sur le dernier message », 1 Nov 2026): a
/// conversation always opens at the bottom, even when everything is unread
/// (new device); the « N non lus » separator stays in the list and a small
/// floating button « ↑ N non lus » goes up to it; messages arriving while
/// the list is being built keep it at the bottom. Shared by Messages and the
/// MeshCore threads.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

/// Within this distance of the end, the last message counts as in view.
const chatBottomSlack=120.0;

/// The last message is in view (or the list is not laid out yet).
bool chatAtBottom(ScrollController c)=>!c.hasClients||c.position.pixels>=c.position.maxScrollExtent-chatBottomSlack;

/// Jumps to the last message. Heights of the items not built yet are
/// estimated: repeat while the end moves.
void chatJumpToBottom(ScrollController c,{required bool Function() alive,int attempt=0}){
  if(!alive()||!c.hasClients)return;
  final max=c.position.maxScrollExtent;
  if(c.position.pixels!=max)c.jumpTo(max);
  if(attempt>=12)return;
  WidgetsBinding.instance.addPostFrameCallback((_){
    if(alive()&&c.hasClients&&c.position.maxScrollExtent!=max)chatJumpToBottom(c,alive:alive,attempt:attempt+1);
  });
}

/// Keeps the list at the bottom when its length changes (items measured,
/// messages arriving, keyboard opening) while [stick] says it is there.
class StickToBottom extends StatelessWidget {
  final ScrollController controller;
  final bool Function() stick;
  final Widget child;
  const StickToBottom({super.key,required this.controller,required this.stick,required this.child});
  @override Widget build(BuildContext context)=>NotificationListener<ScrollMetricsNotification>(
    onNotification:(n){
      if(n.depth==0&&controller.hasClients&&stick()){
        final p=controller.position;
        if(p.pixels<p.maxScrollExtent)controller.jumpTo(p.maxScrollExtent);
      }
      return false;
    },
    child:child);
}

/// The widget of [key] is at least partly visible in its list (built items
/// of the cache area, outside the screen, do not count).
bool chatKeyInView(GlobalKey key){
  final ctx=key.currentContext; if(ctx==null)return false;
  final box=ctx.findRenderObject();
  final scrollable=Scrollable.maybeOf(ctx);
  final view=scrollable?.context.findRenderObject();
  if(box is! RenderBox||view is! RenderBox||!box.attached||!box.hasSize||!view.hasSize)return false;
  final top=box.localToGlobal(Offset.zero,ancestor:view).dy;
  return top+box.size.height>0&&top<view.size.height;
}

/// Watches the « N non lus » separator: seen once it was on screen. Looked
/// at after the layout of the next frame (during a jump, the positions of
/// the items are still the old ones).
class SeparatorWatch {
  final GlobalKey key=GlobalKey();
  bool seen=false;
  bool _pending=false;
  /// [alive] the screen is still there; [changed] rebuilds it.
  void check({required bool Function() alive,required VoidCallback changed}){
    if(seen||_pending)return;
    _pending=true;
    WidgetsBinding.instance.addPostFrameCallback((_){
      _pending=false;
      if(!seen&&alive()&&chatKeyInView(key)){seen=true;changed();}
    });
  }
}

/// Goes up to the widget of [key], item [index] of [count]: about there
/// first (the list is built lazily), then exactly.
Future<void> chatScrollToKey(ScrollController c,GlobalKey key,int index,int count,{required bool Function() alive}) async {
  for(var attempt=0;attempt<6;attempt++){
    final ctx=key.currentContext;
    if(ctx!=null&&ctx.mounted){
      await Scrollable.ensureVisible(ctx,alignment:0.05,duration:const Duration(milliseconds:250));
      return;
    }
    if(!alive()||!c.hasClients)return;
    final max=c.position.maxScrollExtent;
    c.jumpTo((max*index/(count<2?1:count-1)).clamp(0.0,max));
    await WidgetsBinding.instance.endOfFrame;
  }
}

/// MeshCore thread: index of the first unread message, the [unread] last
/// messages received ([mine] false), or null when nothing is unread.
int? firstUnreadReceived(List<bool> mine,int unread){
  if(unread<=0)return null;
  var left=unread;
  for(var i=mine.length-1;i>=0;i--){
    if(mine[i])continue;
    left--;
    if(left==0)return i;
  }
  return mine.contains(false)?mine.indexOf(false):null;
}

/// Small floating button « ↑ N non lus », top of the conversation.
class UnreadUpButton extends StatelessWidget {
  final int count;
  final VoidCallback onPressed;
  const UnreadUpButton({super.key,required this.count,required this.onPressed});
  @override Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    return Material(color:s.primary,elevation:3,borderRadius:BorderRadius.circular(18),
      child:InkWell(key:const ValueKey('unread-up'),borderRadius:BorderRadius.circular(18),onTap:onPressed,
        child:Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:7),child:Row(mainAxisSize:MainAxisSize.min,children:[
          Icon(Icons.arrow_upward,size:16,color:s.onPrimary),
          const SizedBox(width:4),
          Text(S.t('messages.unreadUp',{'n':count}),style:TextStyle(color:s.onPrimary,fontSize:13,fontWeight:FontWeight.w600)),
        ]))));
  }
}
