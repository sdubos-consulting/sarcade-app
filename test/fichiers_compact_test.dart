import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/files/file_tree.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

// Card « Fichiers : écran plus compact et noms lisibles » (validated on 5 Nov 2026).
void main(){
  setUp(()=>S.setLanguage('fr'));
  test('readable names of photos and exported drawings; others unchanged',(){
    expect(readableFileName('photo-20261030-222122.jpg'),'Photo du 30/10 à 22:21');
    expect(readableFileName('sarcade-objets-nas1-2026-10-30-16-48.geojson'),'Dessins exportés · 30/10 16:48');
    expect(readableFileName('Consignes PC.pdf'),isNull);
  });
  test('sizes rounded',(){
    expect(fileSizeLabel(654336),'639 Ko');
    expect(fileSizeLabel(2516582),'2,4 Mo');
    expect(fileSizeLabel(900),'900 o');
  });
}
