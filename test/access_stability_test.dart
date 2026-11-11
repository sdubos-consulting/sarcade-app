// Cloudflare token asked too often (1 Nov 2026): a passing refusal with a
// still valid token is retried once; every refusal is noted; the web waits
// 2 minutes before speaking of an expired session.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarcade_app/src/access/access_manager.dart';
import 'package:sarcade_app/src/access/access_session.dart';
import 'package:sarcade_app/src/operations/operations_widgets.dart';

String _token(DateTime exp) {
  String b64(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${b64({'alg': 'RS256'})}.${b64({'email': 'a@b.fr', 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a passing refusal with a valid token is retried once, then noted', () async {
    final access = AccessManager.instance;
    final token = _token(DateTime.now().add(const Duration(days: 20)));
    expect(AccessSession.fromToken(token), isNotNull);
    await access.save('https://app.example.org', token);
    var calls = 0;
    final client = AccessHttpClient(access: access, inner: MockClient((r) async {
      calls++;
      return calls == 1 ? http.Response('', 403, headers: {'cf-access-domain': 'x'}) : http.Response('{}', 200);
    }));
    final r = await client.get(Uri.parse('https://app.example.org/api/v0.1/sync'));
    expect(r.statusCode, 200);
    expect(calls, 2);
    final c = access.challenges.last;
    expect(c.recovered, isTrue);
    expect(c.status, 403);
    expect(c.path, '/api/v0.1/sync');
    expect(c.tokenUntil, isNotNull);
  });

  test('web: no « session expired » before 2 minutes without an answer', () {
    final t = DateTime(2026, 11, 1, 2);
    expect(webOutageLong(t, t.add(const Duration(seconds: 90))), isFalse);
    expect(webOutageLong(t, t.add(const Duration(minutes: 3))), isTrue);
  });
}
