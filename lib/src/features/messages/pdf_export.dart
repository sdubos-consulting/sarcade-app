/// « Exporter en PDF » a conversation (lot 29, group 7): name of the
/// conversation, event, period, then each message with date, time, author,
/// priority, acknowledgements (Reçu, Lu, Accepté, Refusé) and photos as
/// thumbnails; changed messages are marked. The PCO only for the
/// conversations he is not a member of.
library;

import 'dart:typed_data';

import '../../l10n/strings.dart';
import '../../models/comm_group.dart';
import '../../models/message.dart';
import 'pdf_writer.dart';

/// Messages of the period: [from] included, [to] excluded (local days).
List<SarcadeMessage> inPeriod(List<SarcadeMessage> all,{DateTime? from,DateTime? to})=>[
  for(final m in all)
    if((from==null||!m.createdAt.toLocal().isBefore(from))&&(to==null||m.createdAt.toLocal().isBefore(to)))m];

/// Members and PCO: a conversation the person is not part of is the PCO's only.
bool canExport({required CommGroup? group,required String me,required bool pco}){
  if(pco)return true;
  if(group==null||group.kind=='all'||group.members.isEmpty)return true;
  return group.members.contains(me);
}

String _two(int v)=>v.toString().padLeft(2,'0');
String pdfDay(DateTime t){final l=t.toLocal();return '${_two(l.day)}/${_two(l.month)}/${l.year}';}
String pdfTime(DateTime t){final l=t.toLocal();return '${_two(l.hour)}:${_two(l.minute)}';}

/// Acknowledgements of the others, the best one per person.
String ackLine(SarcadeMessage m,List<SarcadeAck> acks){
  int rank(String s)=>switch(s){'received'=>0,'read'=>1,_=>2};
  final by=<String,SarcadeAck>{};
  for(final a in acks){
    if(a.actorId==m.senderId)continue;
    final b=by[a.actorId]; if(b==null||rank(a.status)>rank(b.status))by[a.actorId]=a;
  }
  if(by.isEmpty)return '';
  final keys=by.keys.toList()..sort();
  return S.t('messages.pdfAcks',{'list':[for(final k in keys)'$k ${S.t('ack.${by[k]!.status}')} ${pdfTime(by[k]!.time)}'].join(', ')});
}

List<PdfBlock> conversationBlocks({required String title,required String event,required String period,required List<SarcadeMessage> messages,
    required Map<String,List<SarcadeAck>> acks,required Uint8List? Function(String fileId) photo,required DateTime now}){
  final out=<PdfBlock>[
    PdfText(title,size:16,bold:true),
    PdfText(S.t('messages.pdfEvent',{'event':event}),size:10,gapBefore:4),
    PdfText(S.t('messages.pdfPeriod',{'period':period}),size:10),
    PdfText(S.t('messages.pdfMade',{'day':pdfDay(now),'time':pdfTime(now),'n':messages.length}),size:9,grey:110),
    const PdfRule(),
  ];
  String? day;
  for(final m in messages){
    final d=pdfDay(m.createdAt);
    if(d!=day){day=d;out.add(PdfText(d,size:11,bold:true,gapBefore:8));}
    final head=[pdfTime(m.createdAt),m.senderId,S.t('priority.${m.priority}').toUpperCase(),
      if(m.forwardedSender!=null)S.t('messages.forwardedFrom',{'who':m.forwardedSender,'at':m.forwardedAt==null?'':'${pdfDay(m.forwardedAt!)} ${pdfTime(m.forwardedAt!)}'}),
      if(m.edited)S.t('messages.edited')].join(' · ');
    out.add(PdfText(head,size:9,bold:true,gapBefore:6,grey:60));
    out.add(PdfText(m.deleted?S.t(m.deletedByPco?'messages.deletedByPco':'messages.deleted'):m.body,size:10));
    for(final a in m.attachments.where((a)=>a.isImage)){
      final b=photo(a.fileId);
      if(b!=null&&b.length>3&&b[0]==0xFF&&b[1]==0xD8){out.add(PdfImage(b,width:140));}
      else{out.add(PdfText(S.t('messages.pdfPhotoMissing',{'name':a.name}),size:9,grey:110));}
    }
    final acked=ackLine(m,acks[m.id]??const []);
    if(acked.isNotEmpty)out.add(PdfText(acked,size:8,grey:110));
  }
  if(messages.isEmpty)out.add(PdfText(S.t('messages.pdfEmpty'),size:10,gapBefore:8));
  return out;
}

Uint8List conversationPdf({required String title,required String event,required String period,required List<SarcadeMessage> messages,
    required Map<String,List<SarcadeAck>> acks,required Uint8List? Function(String fileId) photo,required DateTime now})=>
  buildPdf(conversationBlocks(title:title,event:event,period:period,messages:messages,acks:acks,photo:photo,now:now),
    footer:'SARCADE · $title · ${pdfDay(now)}');
