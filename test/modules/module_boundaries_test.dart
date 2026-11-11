// Lot C (A3), 1 Nov 2026: the Core does not import a module, except the
// composition points listed in lib/src/modules/registry.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/modules/registry.dart';

final _import=RegExp(r"""^\s*(?:import|export)\s+['"]([^'"]+)['"]""",multiLine:true);

String _resolve(String from,String uri){
  if(uri.startsWith('package:sarcade_app/'))return 'lib/${uri.substring(20)}';
  if(uri.contains(':'))return uri;
  // [from] uses « / » on every platform (Windows paths are normalised first).
  final parts=[...from.substring(0,from.lastIndexOf('/')).split('/'),...uri.split('/')];
  final out=<String>[];
  for(final p in parts){if(p=='..'){out.removeLast();}else if(p!='.'&&p.isNotEmpty){out.add(p);}}
  return out.join('/');
}

void main(){
  test('Core files do not import a module',(){
    final bad=<String>[];
    for(final f in Directory('lib').listSync(recursive:true).whereType<File>().where((f)=>f.path.endsWith('.dart'))){
      final path=f.path.replaceAll('\\','/');
      if(path.startsWith('lib/src/modules/'))continue;
      for(final m in _import.allMatches(f.readAsStringSync())){
        final target=_resolve(path,m.group(1)!);
        final module=appModules.where((x)=>target.startsWith('lib/src/modules/${x.folder}/')).firstOrNull;
        if(module!=null&&!moduleCompositionPoints.contains(path))bad.add('$path → $target');
      }
    }
    expect(bad,isEmpty,reason:'Core imports a module outside the composition points:\n${bad.join('\n')}');
  });

  test('composition points exist and the old folders are gone',(){
    for(final p in moduleCompositionPoints){expect(File(p).existsSync(),isTrue,reason:p);}
    for(final p in ['lib/src/features/bearings','lib/src/features/aprs']){expect(Directory(p).existsSync(),isFalse,reason:p);}
    expect(File('lib/src/features/tools/resection.dart').existsSync(),isFalse);
  });

  test('module code lives in its folder',(){
    for(final m in appModules){expect(Directory('lib/src/modules/${m.folder}').existsSync(),isTrue);}
  });
}
