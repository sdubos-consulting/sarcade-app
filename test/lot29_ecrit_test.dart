import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/typing.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  test('a direct chat has the same name on both sides',(){
    expect(typingWire('u:TEL-02','TEL-01'),'u:TEL-01|TEL-02');
    expect(typingWire('u:TEL-01','TEL-02'),'u:TEL-01|TEL-02');
    expect(typingWire('g:pco','TEL-01'),'g:pco');
    expect(typingWire('all','TEL-01'),'all');
  });
  test('received in the right conversation, never for others',(){
    expect(typingConversation('u:TEL-01|TEL-02','TEL-01','TEL-02'),'u:TEL-02');
    expect(typingConversation('u:TEL-02|TEL-03','TEL-01','TEL-02'),isNull);
    expect(typingConversation('g:pco','TEL-01','TEL-02'),'g:pco');
  });
  test('shown 6 s, gone after the message',(){
    final t=Typing();
    final at=DateTime(2026,11,5,23);
    t.received({'actor_id':'TEL-02','conversation':'g:pco'},'TEL-01',now:at);
    t.received({'actor_id':'TEL-01','conversation':'g:pco'},'TEL-01',now:at);
    expect(t.who('g:pco',now:at.add(const Duration(seconds:2))),['TEL-02']);
    expect(t.who('g:pco',now:at.add(const Duration(seconds:7))),isEmpty);
    t.sent('TEL-02');
    expect(t.who('g:pco',now:at),isEmpty);
  });
  test('at most one signal every 4 s per conversation',(){
    final s=TypingSender(); final at=DateTime(2026,11,5,23);
    expect(s.shouldSend('g:pco',at),isTrue);
    expect(s.shouldSend('g:pco',at.add(const Duration(seconds:2))),isFalse);
    expect(s.shouldSend('g:pco',at.add(const Duration(seconds:5))),isTrue);
    expect(s.shouldSend('u:TEL-02',at.add(const Duration(seconds:5,milliseconds:1))),isTrue);
  });
  test('text in French',(){
    S.setLanguage('fr');
    expect(S.t('messages.typing',{'n':1,'who':'TEL-02'}),'TEL-02 écrit…');
    expect(S.t('messages.typing',{'n':2,'who':'TEL-02, TEL-03'}),'TEL-02, TEL-03 écrivent…');
  });
}
