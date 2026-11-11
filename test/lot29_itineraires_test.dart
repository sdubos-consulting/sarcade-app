import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  test('« 1 point », « 3 points »',(){
    S.setLanguage('fr');
    expect(S.t('routes.pointsN',{'n':1}),'1 point');
    expect(S.t('routes.pointsN',{'n':3}),'3 points');
    expect(S.t('routes.section.drafts',{'n':4}),'Brouillons · 4');
  });
}
