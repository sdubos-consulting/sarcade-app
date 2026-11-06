/// A small PDF writer for the export of a conversation (lot 29, group 7):
/// A4 pages, Helvetica in WinAnsi (French accents), JPEG thumbnails. No
/// dependency: text, a few bold lines and pictures are all it needs.
library;

import 'dart:convert';
import 'dart:typed_data';

const pdfPageW=595.0, pdfPageH=842.0, pdfMargin=40.0;

/// One piece of the document, laid out from top to bottom.
sealed class PdfBlock{const PdfBlock();}
class PdfText extends PdfBlock{
  final String text; final double size; final bool bold; final double gapBefore; final int grey;
  const PdfText(this.text,{this.size=10,this.bold=false,this.gapBefore=0,this.grey=0});
}
class PdfImage extends PdfBlock{
  final Uint8List jpeg; final double width;
  const PdfImage(this.jpeg,{this.width=120});
}
class PdfRule extends PdfBlock{const PdfRule();}

const _emoji={'🆘':'SOS','📍':'','✅':'[OK]','❌':'[X]','⚠️':'/!\\','📻':'','📡':'','🚗':'','🚶':'','👍':'(+1)','❤️':'<3','🙏':''};
const _cp1252={0x20AC:0x80,0x201A:0x82,0x0192:0x83,0x201E:0x84,0x2026:0x85,0x2020:0x86,0x2021:0x87,0x02C6:0x88,0x2030:0x89,
  0x0160:0x8A,0x2039:0x8B,0x0152:0x8C,0x017D:0x8E,0x2018:0x91,0x2019:0x92,0x201C:0x93,0x201D:0x94,0x2022:0x95,0x2013:0x96,
  0x2014:0x97,0x02DC:0x98,0x2122:0x99,0x0161:0x9A,0x203A:0x9B,0x0153:0x9C,0x017E:0x9E,0x0178:0x9F,0x202F:0xA0,0x00A0:0xA0};

/// Text in WinAnsi: the usual emojis as words, the rest « ? ».
List<int> winAnsi(String s){
  var t=s; _emoji.forEach((k,v){t=t.replaceAll(k,v);});
  final out=<int>[];
  for(final r in t.runes){
    if(r==0xFE0F||r==0x200D)continue;
    if(r<0x80||(r>=0xA0&&r<=0xFF)){out.add(r);continue;}
    out.add(_cp1252[r]??0x3F);
  }
  return out;
}

double _w(int c){
  if(' ilI.,;:\'|!jtfr()[]'.codeUnits.contains(c))return 0.30;
  if('mwMW@'.codeUnits.contains(c))return 0.85;
  if(c>=0x41&&c<=0x5A)return 0.68;
  if(c>=0x30&&c<=0x39)return 0.56;
  return 0.54;
}
double textWidth(List<int> b,double size)=>b.fold(0.0,(a,c)=>a+_w(c))*size;

/// Lines of at most [width] points, cut at spaces (a very long word is cut).
List<List<int>> wrapText(String text,double size,double width){
  final lines=<List<int>>[];
  for(final para in text.split('\n')){
    var line=<int>[];
    for(final word in para.split(' ')){
      var w=winAnsi(word);
      while(textWidth(w,size)>width){
        var n=w.length; while(n>1&&textWidth(w.sublist(0,n),size)>width){n--;}
        if(line.isNotEmpty){lines.add(line);line=<int>[];}
        lines.add(w.sublist(0,n)); w=w.sublist(n);
      }
      final cand=line.isEmpty?w:[...line,0x20,...w];
      if(textWidth(cand,size)>width&&line.isNotEmpty){lines.add(line);line=w;}else{line=cand;}
    }
    lines.add(line);
  }
  return lines;
}

/// Width and height of a JPEG and its components, or null.
({int w,int h,int comps})? jpegSize(Uint8List b){
  if(b.length<4||b[0]!=0xFF||b[1]!=0xD8)return null;
  var i=2;
  while(i+9<b.length){
    if(b[i]!=0xFF){i++;continue;}
    final m=b[i+1];
    if(m==0xD8||m==0x01||(m>=0xD0&&m<=0xD7)){i+=2;continue;}
    final len=(b[i+2]<<8)|b[i+3];
    if(m>=0xC0&&m<=0xCF&&m!=0xC4&&m!=0xC8&&m!=0xCC){
      return (h:(b[i+5]<<8)|b[i+6],w:(b[i+7]<<8)|b[i+8],comps:b[i+9]);
    }
    i+=2+len;
  }
  return null;
}

List<int> _esc(List<int> b){
  final out=<int>[];
  for(final c in b){if(c==0x28||c==0x29||c==0x5C)out.add(0x5C);out.add(c);}
  return out;
}

/// The whole document.
Uint8List buildPdf(List<PdfBlock> blocks,{String footer=''}){
  const usable=pdfPageW-2*pdfMargin;
  final pages=<BytesBuilder>[]; final images=<({Uint8List data,int w,int h,int comps})>[];
  final pageImages=<List<int>>[];
  late BytesBuilder page; var y=0.0;
  void newPage(){
    page=BytesBuilder(); pages.add(page); pageImages.add([]); y=pdfPageH-pdfMargin;
    if(footer.isNotEmpty){
      page.add(latin1.encode('BT /F1 8 Tf 0.5 g ${pdfMargin.toStringAsFixed(1)} 20 Td ('));
      page.add(_esc(winAnsi('$footer · ${pages.length}')));page.add(latin1.encode(') Tj ET\n'));
    }
  }
  newPage();
  for(final b in blocks){
    switch(b){
      case final PdfText t:
        y-=t.gapBefore;
        for(final line in wrapText(t.text,t.size,usable)){
          final lh=t.size*1.3;
          if(y-lh<pdfMargin)newPage();
          y-=lh;
          final g=(t.grey/255).toStringAsFixed(2);
          page.add(latin1.encode('BT /${t.bold?'F2':'F1'} ${t.size} Tf $g g ${pdfMargin.toStringAsFixed(1)} ${y.toStringAsFixed(1)} Td ('));
          page.add(_esc(line)); page.add(latin1.encode(') Tj ET\n'));
        }
      case final PdfImage im:
        final s=jpegSize(im.jpeg);
        if(s==null||(s.comps!=1&&s.comps!=3)||s.w==0)continue;
        final w=im.width.clamp(10,usable).toDouble(); final h=w*s.h/s.w;
        if(y-h-4<pdfMargin)newPage();
        y-=h+4;
        images.add((data:im.jpeg,w:s.w,h:s.h,comps:s.comps));
        pageImages.last.add(images.length);
        page.add(latin1.encode('q ${w.toStringAsFixed(1)} 0 0 ${h.toStringAsFixed(1)} ${pdfMargin.toStringAsFixed(1)} ${y.toStringAsFixed(1)} cm /Im${images.length} Do Q\n'));
      case PdfRule():
        if(y-8<pdfMargin)newPage();
        y-=6;
        page.add(latin1.encode('0.8 G 0.5 w ${pdfMargin.toStringAsFixed(1)} ${y.toStringAsFixed(1)} m ${(pdfPageW-pdfMargin).toStringAsFixed(1)} ${y.toStringAsFixed(1)} l S\n'));
        y-=4;
    }
  }
  // Objects: 1 catalog, 2 pages, 3 and 4 fonts, then the images, then per
  // page its content and the page itself.
  final objects=<List<int>>[];
  final firstImage=5, firstPage=firstImage+images.length;
  final kids=[for(var i=0;i<pages.length;i++)'${firstPage+2*i+1} 0 R'].join(' ');
  objects.add(latin1.encode('<< /Type /Catalog /Pages 2 0 R >>'));
  objects.add(latin1.encode('<< /Type /Pages /Kids [$kids] /Count ${pages.length} >>'));
  objects.add(latin1.encode('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'));
  objects.add(latin1.encode('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>'));
  for(final im in images){
    objects.add([...latin1.encode('<< /Type /XObject /Subtype /Image /Width ${im.w} /Height ${im.h} /ColorSpace /${im.comps==1?'DeviceGray':'DeviceRGB'} '
      '/BitsPerComponent 8 /Filter /DCTDecode /Length ${im.data.length} >>\nstream\n'),...im.data,...latin1.encode('\nendstream')]);
  }
  for(var i=0;i<pages.length;i++){
    final content=pages[i].toBytes();
    objects.add([...latin1.encode('<< /Length ${content.length} >>\nstream\n'),...content,...latin1.encode('endstream')]);
    final xo=pageImages[i].isEmpty?'':' /XObject << ${[for(final n in pageImages[i])'/Im$n ${firstImage+n-1} 0 R'].join(' ')} >>';
    objects.add(latin1.encode('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${pdfPageW.toInt()} ${pdfPageH.toInt()}] '
      '/Resources << /Font << /F1 3 0 R /F2 4 0 R >>$xo >> /Contents ${firstPage+2*i} 0 R >>'));
  }
  final out=BytesBuilder();
  out.add(latin1.encode('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n'));
  final offsets=<int>[];
  for(var i=0;i<objects.length;i++){
    offsets.add(out.length);
    out.add(latin1.encode('${i+1} 0 obj\n')); out.add(objects[i]); out.add(latin1.encode('\nendobj\n'));
  }
  final xref=out.length;
  out.add(latin1.encode('xref\n0 ${objects.length+1}\n0000000000 65535 f \n'));
  for(final o in offsets){out.add(latin1.encode('${o.toString().padLeft(10,'0')} 00000 n \n'));}
  out.add(latin1.encode('trailer\n<< /Size ${objects.length+1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n'));
  return out.toBytes();
}
