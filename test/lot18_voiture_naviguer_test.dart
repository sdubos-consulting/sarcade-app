// Android Auto, lot 18 (card « Android Auto : « Naviguer » ouvre directement
// une application, sans choix entre Waze et Google Maps », choice 1): the
// button says that the navigation application of the car is used, with a
// short form for the narrow buttons; CarPlay keeps « Naviguer ».
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/car/car_screen.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  tearDown(()=>S.setLanguage('fr'));

  test('« Naviguer (application de la voiture) », short form « Naviguer · voiture »',(){
    S.setLanguage('fr');
    var labels=carLabels();
    expect(labels['navigateCar'],'Naviguer (application de la voiture)');
    expect(labels['navigateCarShort'],'Naviguer · voiture');
    expect(labels['navigate'],'Naviguer',reason:'CarPlay unchanged');
    S.setLanguage('en');
    labels=carLabels();
    expect(labels['navigateCar'],'Navigate (car navigation app)');
    expect(labels['navigateCarShort'],'Navigate · car');
  });
}
