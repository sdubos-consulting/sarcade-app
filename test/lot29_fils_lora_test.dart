// Lot 29, card « Messages : les fils MeshCore et Meshtastic ignorent les
// filtres et les favoris » (5 Nov 2026, 17 h 02): the MeshCore threads follow
// the filter « Non lues », « Favoris » and the search of Messages.
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_chat.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_chat_page.dart';
import 'package:sarcade_app/src/features/meshcore/meshcore_protocol.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

const _key='a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
Uint8List _u32(int v)=>Uint8List(4)..buffer.asByteData().setUint32(0,v,Endian.little);
Uint8List _incoming(String text)=>Uint8List.fromList([0x10,30,0,0,0xa1,0xb2,0xc3,0xd4,0xe5,0xf6,2,0,..._u32(1793534400),...utf8.encode(text)]);

void main(){
  setUp((){S.setLanguage('fr');MeshCoreChats.instance.reset();});

  testWidgets('filters, search and favourites apply to the MeshCore threads',(t) async {
    final chats=MeshCoreChats.instance..autoExpire=false;
    chats.onReceived(readMeshCoreMessage(_incoming('Bien reçu'))!,nameOf:(_)=>'Alice');
    final prefix=meshCorePrefix(_key);
    Future<void> show(String filter,{String q='',Set<String> fav=const {}}) async {
      await t.pumpWidget(MaterialApp(home:Scaffold(body:MeshCoreThreadTiles(filter:filter,query:q,favourites:fav))));
    }
    await show('all'); expect(find.text('MeshCore · Alice'),findsOneWidget);
    await show('unread'); expect(find.text('MeshCore · Alice'),findsOneWidget,reason:'one unread');
    await show('fav'); expect(find.text('MeshCore · Alice'),findsNothing,reason:'not a favourite');
    await show('fav',fav:{MeshCoreThreadTiles.favouriteKey(prefix)});
    expect(find.text('MeshCore · Alice'),findsOneWidget);
    expect(find.byIcon(Icons.star),findsOneWidget);
    await show('all',q:'pco'); expect(find.text('MeshCore · Alice'),findsNothing,reason:'search');
    await show('all',q:'reçu'); expect(find.text('MeshCore · Alice'),findsOneWidget);
    chats.thread(_key)!.unread=0;
    await show('unread'); expect(find.text('MeshCore · Alice'),findsNothing,reason:'read');
  });
}
