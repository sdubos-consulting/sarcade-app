import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/important.dart';

void main(){
  test('« événement/message », most recent first, no duplicate',(){
    var l=toggleImportant(const [],importantId('e1','m1'));
    l=toggleImportant(l,importantId('e1','m2'));
    expect(l,['e1/m2','e1/m1']);
    l=toggleImportant(l,'e1/m1');
    expect(l,['e1/m2']);
  });
  test('at most 500 kept',(){
    var l=<String>[for(var i=0;i<importantMax;i++)'e1/m$i'];
    l=toggleImportant(l,'e1/new');
    expect(l.length,importantMax);
    expect(l.first,'e1/new');
  });
  test('read from the server or the device',(){
    expect(parseImportant(['e1/m1','e1/m1','bad']),['e1/m1']);
    expect(parseImportant('["e1/m2"]'),['e1/m2']);
    expect(parseImportant('pas du json'),isEmpty);
    expect(parseImportant(null),isEmpty);
  });
}
