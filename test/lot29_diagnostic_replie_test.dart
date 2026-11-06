import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/settings/diagnostics_panel.dart';

void main(){
  test('colour of a section: red, then orange, then green',(){
    DiagLine l(String? st)=>(block:'b',label:'x',value:'y',state:st);
    expect(sectionState([l('green'),l('orange'),l(null)]),'orange');
    expect(sectionState([l('green'),l('red')]),'red');
    expect(sectionState([l(null)]),isNull);
  });
  test('folded when all is good, open on a problem, the choice of the person wins',(){
    expect(sectionOpen(stored:null,problem:false),isFalse);
    expect(sectionOpen(stored:null,problem:true),isTrue);
    expect(sectionOpen(stored:'1',problem:false),isTrue);
    expect(sectionOpen(stored:'0',problem:true),isFalse);
  });
}
