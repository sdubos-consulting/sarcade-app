/// The MeshCore transport of the remotes (lot 21): a command is a private
/// message to the box's companion (private messages of lot 17), its answer
/// a private message of that companion.
library;

import '../meshcore/meshcore_chat.dart';
import '../meshcore/meshcore_link.dart';
import '../meshcore/meshcore_protocol.dart';
import 'remote.dart';

/// A private message seen as a command: refused, or acknowledged by the
/// node (read again while the answer is awaited).
class MeshCoreRemoteDelivery implements RemoteDelivery {
  final MeshCoreChatMessage message;
  const MeshCoreRemoteDelivery(this.message);
  @override bool get failed=>message.state==MeshCoreMsgState.failed;
  @override bool get delivered=>message.state==MeshCoreMsgState.delivered;
}

/// MeshCore as a [RemoteLink]; [send] and [ready] replaced in the tests.
RemoteLink meshCoreRemoteLink({Future<MeshCoreChatMessage> Function(String key,String name,String text)? send,bool Function()? ready})=>RemoteLink(
  ready:ready??(()=>MeshCoreLink.instance.state==MeshCoreState.connected),
  send:(r,text) async => MeshCoreRemoteDelivery(send!=null?await send(r.target,r.targetName,text):await MeshCoreChats.instance.write(r.target,r.targetName,text)));

/// Called once the MeshCore private messages are wired: the remotes kept
/// on this device are read, MeshCore carries their commands and brings
/// back the answers of the boxes.
void wireMeshCoreRemotes({required String? Function(String key) load,required Future<void> Function(String key,String? value) save}){
  final remotes=Remotes.instance, chats=MeshCoreChats.instance;
  remotes.attach(load:load,save:save);
  remotes.links[RemoteTransport.meshcore]??=meshCoreRemoteLink();
  chats.onIncoming??=(prefix,text,at)=>remotes.onIncoming(RemoteTransport.meshcore,prefix,text,now:at);
}

/// Name of a MeshCore box: the companion's name, else its key prefix.
String meshCoreRemoteTargetName(Remote r)=>r.targetName.isEmpty?meshCorePrefix(r.target):r.targetName;
