import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/pdf_export.dart';
import 'package:sarcade_app/src/features/messages/pdf_writer.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/comm_group.dart';
import 'package:sarcade_app/src/models/message.dart';

SarcadeMessage _m(String id,DateTime at,{String body='Balise entendue',List<SarcadeAttachment> photos=const []})=>
  SarcadeMessage(id:id,eventId:'e1',senderId:'TEL-01',recipientIds:const [],priority:'urgent',body:body,createdAt:at,attachments:photos);

/// Every « N 0 obj » where the cross-reference table says.
void _checkXref(Uint8List pdf){
  final text=latin1.decode(pdf);
  expect(text.startsWith('%PDF-1.4'),isTrue);
  expect(text.trimRight().endsWith('%%EOF'),isTrue);
  final start=int.parse(RegExp(r'startxref\n(\d+)').firstMatch(text)!.group(1)!);
  expect(text.substring(start).startsWith('xref'),isTrue);
  final rows=RegExp(r'(\d{10}) 00000 n ').allMatches(text.substring(start)).toList();
  for(var i=0;i<rows.length;i++){
    final off=int.parse(rows[i].group(1)!);
    expect(text.substring(off).startsWith('${i+1} 0 obj'),isTrue,reason:'object ${i+1}');
  }
}

void main(){
  setUp(()=>S.setLanguage('fr'));
  test('French accents in WinAnsi, emojis as words',(){
    expect(winAnsi('Été'),[0xC9,0x74,0xE9]);
    expect(latin1.decode(winAnsi('🆘 Blessé')),'SOS Blessé');
    expect(winAnsi('’'),[0x92]);
  });
  test('long lines cut at the spaces',(){
    final lines=wrapText('mot '*80,10,200);
    expect(lines.length,greaterThan(3));
    for(final l in lines){expect(textWidth(l,10),lessThanOrEqualTo(200));}
  });
  test('a readable PDF: header, objects where the table says, several pages',(){
    final list=[for(var i=0;i<120;i++)_m('m$i',DateTime(2026,11,5,8,i%60))];
    final pdf=conversationPdf(title:'Tous',event:'Exercice',period:'Tout',messages:list,acks:const {},photo:(_)=>null,now:DateTime(2026,11,6,1));
    _checkXref(pdf);
    expect(RegExp(r'/Type /Page ').allMatches(latin1.decode(pdf)).length,greaterThan(1));
  });
  test('a JPEG photo as a thumbnail',(){
    // Smallest JPEG header with its SOF0: 16 × 8, 3 components.
    final jpeg=Uint8List.fromList([0xFF,0xD8,0xFF,0xC0,0x00,0x11,0x08,0x00,0x08,0x00,0x10,0x03,1,0x22,0,2,0x11,1,3,0x11,1,0xFF,0xD9]);
    expect(jpegSize(jpeg),(w:16,h:8,comps:3));
    final m=_m('m1',DateTime(2026,11,5,9),photos:const [SarcadeAttachment(fileId:'f1',name:'p.jpg',mimeType:'image/jpeg',sizeBytes:23)]);
    final pdf=conversationPdf(title:'Tous',event:'Exercice',period:'Tout',messages:[m],acks:const {},photo:(_)=>jpeg,now:DateTime(2026,11,6,1));
    _checkXref(pdf);
    expect(latin1.decode(pdf).contains('/Subtype /Image /Width 16 /Height 8'),isTrue);
  });
  test('acknowledgements and period',(){
    final m=_m('m1',DateTime(2026,11,5,9));
    final a=[SarcadeAck(id:'a1',eventId:'e1',messageId:'m1',actorId:'TEL-02',status:'received',time:DateTime(2026,11,5,9,1)),
      SarcadeAck(id:'a2',eventId:'e1',messageId:'m1',actorId:'TEL-02',status:'read',time:DateTime(2026,11,5,9,2))];
    expect(ackLine(m,a),contains('TEL-02'));
    expect(ackLine(m,a),contains('09:02'));
    final l=[_m('a',DateTime(2026,11,4,23)),_m('b',DateTime(2026,11,5,10))];
    expect(inPeriod(l,from:DateTime(2026,11,5),to:DateTime(2026,11,6)).map((m)=>m.id),['b']);
  });
  test('the PCO only for a conversation he is not part of',(){
    final g=CommGroup.fromJson({'id':'g1','event_id':'e1','name':'Logistique','kind':'channel','members':['TEL-03']});
    expect(canExport(group:g,me:'TEL-01',pco:false),isFalse);
    expect(canExport(group:g,me:'TEL-01',pco:true),isTrue);
    expect(canExport(group:g,me:'TEL-03',pco:false),isTrue);
    expect(canExport(group:null,me:'TEL-01',pco:false),isTrue);
  });
}
