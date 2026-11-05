import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/locate_cycle.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  setUp(()=>S.setLanguage('fr'));
  test('Tesla: « Cap de route » in place of the compass, without trying',(){
    expect(nextLocateMode(LocateMode.follow,compass:false,course:true),LocateMode.course);
    expect(nextLocateMode(LocateMode.course),LocateMode.all);
    expect(nextLocateMode(LocateMode.follow),LocateMode.compass,reason:'elsewhere the compass first');
  });
  test('the label says the mode',(){
    expect(locateLabel(LocateMode.follow),'Suivi · nord en haut');
    expect(locateLabel(LocateMode.course),'Cap de route');
    expect(locateLabel(LocateMode.compass),'Boussole');
  });
}
