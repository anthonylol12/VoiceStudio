// End-to-end check against a running backend with Argos models installed:
//   backend\run_server.ps1        (in another terminal)
//   flutter test test/integration/real_translation_test.dart
// Skipped automatically when the backend is not reachable.
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_studio/models/models.dart';
import 'package:voice_studio/services/backend/backend_client.dart';
import 'package:voice_studio/services/text/language_detector.dart';
import 'package:voice_studio/services/text/speech_normalizer.dart';
import 'package:voice_studio/services/translation/translation_service.dart';

Future<bool> _backendUp(String url) async {
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final r = await (await c.getUrl(Uri.parse('$url/api/v1/health'))).close();
    c.close(force: true);
    return r.statusCode == 200;
  } catch (_) {
    return false;
  }
}

void main() {
  const url = String.fromEnvironment('VS_BACKEND', defaultValue: 'http://127.0.0.1:8765');

  test('technical terms survive real offline translation', () async {
    if (!await _backendUp(url)) {
      markTestSkipped('backend not running at $url');
      return;
    }
    // No platform keychain in tests; the plugin provides an in-memory store.
    FlutterSecureStorage.setMockInitialValues({});
    final svc = TranslationService(BackendTranslationEngine(BackendClient(baseUrl: url), () async => true))
      ..protector = TermProtector(defaultPronunciations.map((e) => TermRule(e.term, caseSensitive: e.caseSensitive)));

    final es = await svc.translate(
      VsDocument(
        id: 'es',
        title: 't',
        sourceType: 'text',
        language: 'es',
        originalText: 'Pasar 12 cables THHN por el conduit EMT de 3/4 de pulgada.\n\nRevisar el breaker de 20 amperios.',
      ),
      Lang.en,
    );
    for (final p in es.paragraphs) {
      // ignore: avoid_print
      print('ES→EN: ${p.original}  =>  ${p.translation}  (ok=${p.ok}, lost=${p.lostTerms})');
    }
    expect(es.paragraphs[0].translation, allOf(contains('THHN'), contains('conduit'), contains('EMT')));
    expect(es.paragraphs[1].translation, contains('breaker'));

    final en = await svc.translate(
      VsDocument(
        id: 'en',
        title: 't',
        sourceType: 'text',
        language: 'en',
        originalText: 'Pull two 12 AWG wires through the conduit and check the breaker.',
      ),
      Lang.es,
    );
    final p = en.paragraphs.single;
    // ignore: avoid_print
    print('EN→ES: ${p.original}  =>  ${p.translation}  (ok=${p.ok}, lost=${p.lostTerms}, numbers=${p.numbersMatch})');
    expect(p.translation, allOf(contains('AWG'), contains('conduit'), contains('breaker')));
    // If the model drops a quantity the paragraph must be flagged, never silent.
    expect(p.numbersMatch, sameNumbers(p.original, p.translation));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
