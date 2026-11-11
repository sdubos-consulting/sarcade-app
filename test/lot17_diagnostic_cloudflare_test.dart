import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/access/access_session.dart';
import 'package:sarcade_app/src/features/settings/diagnostics_panel.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

// Card « Diagnostic : bouton « Se reconnecter » à Cloudflare dans
// Paramètres » (1 Nov 2026).
void main() {
  setUp(() => S.setLanguage('fr'));
  tearDown(() => S.setLanguage('fr'));

  const viaCloudflare = <String, dynamic>{'via_cloudflare': true, 'ip': '1.2.3.4'};
  const local = <String, dynamic>{'via_cloudflare': false};

  group('web', () {
    test('server answering through Cloudflare: green « par le navigateur », no alert', () {
      final l = accessDiagLine('Liaisons', web: true, session: null, client: viaCloudflare);
      expect(l.label, 'Cloudflare Access');
      expect(l.value, 'par le navigateur');
      expect(l.state, 'green');
      expect(diagnosticProblems([l]), isEmpty);
      expect(showsAccessReconnect(l, web: true), isFalse);
    });

    test('local server without Access: no state, no button', () {
      final l = accessDiagLine('Liaisons', web: true, session: null, client: local);
      expect(l.value, 'réseau local (sans Access)');
      expect(l.state, isNull);
      expect(showsAccessReconnect(l, web: true), isFalse);
    });

    test('server refusing while the browser is online: orange with « Se reconnecter »', () {
      final l = accessDiagLine('Liaisons', web: true, session: null, client: null);
      expect(l.value, 'sans réponse, reconnectez-vous');
      expect(l.state, 'orange');
      expect(diagnosticProblems([l]), hasLength(1));
      expect(showsAccessReconnect(l, web: true), isTrue);
      final refused = accessDiagLine('Liaisons', web: true, session: null, client: viaCloudflare, refused: true);
      expect(refused.state, 'orange');
    });

    test('browser offline: no Cloudflare alert', () {
      final l = accessDiagLine('Liaisons', web: true, session: null, client: null, online: false);
      expect(l.state, isNull);
      expect(showsAccessReconnect(l, web: true), isFalse);
    });

    test('English', () {
      S.setLanguage('en');
      expect(accessDiagLine('Links', web: true, session: null, client: viaCloudflare).value, 'through the browser');
      expect(accessDiagLine('Links', web: true, session: null, client: null).value, 'no answer, sign in again');
    });
  });

  group('installed apps (unchanged, with the button)', () {
    test('no token through Cloudflare: orange « non connecté », button', () {
      final l = accessDiagLine('Liaisons', web: false, session: null, client: viaCloudflare);
      expect(l.value, 'non connecté');
      expect(l.state, 'orange');
      expect(showsAccessReconnect(l, web: false), isTrue);
    });

    test('token stored: green, email, button to renew it', () {
      const s = AccessSession(token: 'a.b.c', email: 'f1abc@example.org');
      final l = accessDiagLine('Liaisons', web: false, session: s, client: {'via_cloudflare': true, 'email': 'f1abc@example.org'});
      expect(l.value, 'connecté · f1abc@example.org · e-mail vérifié');
      expect(l.state, 'green');
      expect(showsAccessReconnect(l, web: false), isTrue);
    });

    test('local network: no state, no button', () {
      final l = accessDiagLine('Liaisons', web: false, session: null, client: local);
      expect(l.value, 'réseau local (sans Access)');
      expect(l.state, isNull);
      expect(showsAccessReconnect(l, web: false), isFalse);
    });
  });

  test('Paramètres › Diagnostic: the button does not need the map', () {
    // The panel of Paramètres has no onSignIn: the button only depends on
    // the line, as from the map.
    final l = accessDiagLine('Liaisons', web: false, session: null, client: viaCloudflare);
    expect(showsAccessReconnect(l, web: false), isTrue);
    expect(S.t('links.signInAgain'), isNotEmpty);
  });
}
