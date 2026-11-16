import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voice_studio/database/app_database.dart';
import 'package:voice_studio/database/repositories.dart';
import 'package:voice_studio/models/models.dart';
import 'package:voice_studio/services/text/language_detector.dart';
import 'package:voice_studio/services/translation/translation_service.dart';

/// Fake engine: uppercases text, optionally drops a number to simulate a
/// machine-translation error.
class FakeEngine implements TranslationEngine {
  FakeEngine({this.corruptNumbers = false});
  final bool corruptNumbers;
  final calls = <List<String>>[];

  @override
  String get name => 'fake';
  @override
  Future<bool> isReady(Lang from, Lang to) async => true;
  @override
  Future<void> prepare(Lang from, Lang to) async {}
  @override
  Future<List<String>> translate(List<String> paragraphs, Lang from, Lang to) async {
    calls.add(paragraphs);
    return [
      for (final p in paragraphs) corruptNumbers ? p.toUpperCase().replaceAll('12', 'twelve') : '[${to.code}] $p',
    ];
  }
}

/// Simulates an engine that drops placeholders (a lost technical term).
class _DroppingEngine extends FakeEngine {
  @override
  Future<List<String>> translate(List<String> paragraphs, Lang from, Lang to) async =>
      [for (final p in paragraphs) p.replaceAll(RegExp(r'ZXQ[A-Z]+'), 'switch')];
}

VsDocument doc(String text) => VsDocument(id: 'd1', title: 'Orden', sourceType: 'text', originalText: text, language: 'es');

void main() {
  test('number tokens ignore separators and order', () {
    expect(numberTokens('1.500 ft y 3/4"'), ['1', '3', '4', '500']);
    expect(sameNumbers('Entrega 15/11/2026, 1.500 m', 'Delivery 11/15/2026, 1,500 m'), isTrue);
    expect(sameNumbers('12 cables', 'twelve wires'), isFalse);
    expect(sameNumbers('Paso 03', 'Step 3'), isTrue);
  });

  test('translates paragraph by paragraph and keeps the original', () async {
    final engine = FakeEngine();
    final t = await TranslationService(engine).translate(
      doc('Instalar 12 cables THHN.\n\nRevisar el panel mañana.'),
      Lang.en,
    );
    expect(engine.calls.single.length, 2);
    expect(t.paragraphs.map((p) => p.original), ['Instalar 12 cables THHN.', 'Revisar el panel mañana.']);
    expect(t.paragraphs.first.translation, '[en] Instalar 12 cables THHN.');
    expect(t.warnings, 0);
  });

  test('paragraphs already in the target language are not sent', () async {
    final engine = FakeEngine();
    final t = await TranslationService(engine).translate(
      doc('Necesitamos los materiales para la instalación.\n\nPull the wire through the conduit.'),
      Lang.en,
    );
    expect(engine.calls.single, ['Necesitamos los materiales para la instalación.']);
    expect(t.paragraphs[1].translation, 'Pull the wire through the conduit.');
  });

  test('flags paragraphs whose numbers changed', () async {
    final t = await TranslationService(FakeEngine(corruptNumbers: true)).translate(doc('Instalar 12 cables.\n\nSin cifras aquí.'), Lang.en);
    expect(t.paragraphs.map((p) => p.numbersMatch), [false, true]);
    expect(t.warnings, 1);
  });

  group('TermProtector', () {
    final p = TermProtector(const [
      TermRule('EMT', caseSensitive: true),
      TermRule('Conduit'),
      TermRule('Circuit breaker'),
      TermRule('Breaker'),
    ]);

    test('placeholders are opaque pseudo-acronyms', () {
      expect([0, 1, 25, 26, 27].map(TermProtector.placeholder), ['ZXQA', 'ZXQB', 'ZXQZ', 'ZXQAA', 'ZXQAB']);
    });

    test('protects whole words, longest first, keeping original spelling', () {
      final r = p.protect('Pasar el conduit EMT y revisar el circuit breaker; el breaker nuevo. EMTX no.');
      // Placeholders are numbered by rule (longest term first), not by position.
      expect(r.text, 'Pasar el ZXQB ZXQD y revisar el ZXQA; el ZXQC nuevo. EMTX no.');
      expect(r.slots, {'ZXQA': 'circuit breaker', 'ZXQB': 'conduit', 'ZXQC': 'breaker', 'ZXQD': 'EMT'});
    });

    test('case-sensitive acronyms are not matched in lowercase words', () {
      expect(p.protect('emt').slots, isEmpty);
    });

    test('restores terms (case-insensitive placeholder) and reports lost ones', () {
      final r = p.restore('Pass the zxqb ZXQC and check it.', {'ZXQB': 'conduit', 'ZXQC': 'EMT', 'ZXQA': 'circuit breaker'});
      expect(r.text, 'Pass the conduit EMT and check it.');
      expect(r.lost, ['circuit breaker']);
    });
  });

  test('service keeps technical terms and flags lost ones', () async {
    final engine = FakeEngine();
    final svc = TranslationService(engine)..protector = TermProtector(const [TermRule('Conduit'), TermRule('Breaker')]);
    final t = await svc.translate(doc('Pasar cable por el conduit y revisar el breaker.'), Lang.en);
    expect(engine.calls.single.single, 'Pasar cable por el ZXQA y revisar el ZXQB.');
    expect(t.paragraphs.single.translation, '[en] Pasar cable por el conduit y revisar el breaker.');
    expect(t.warnings, 0);

    final dropping = _DroppingEngine();
    final t2 = await (TranslationService(dropping)..protector = TermProtector(const [TermRule('Breaker')]))
        .translate(doc('Revisar el breaker del panel.'), Lang.en);
    expect(t2.paragraphs.single.lostTerms, ['breaker']);
    expect(t2.warnings, 1);
    // Saved translations keep the information.
    expect(Translation.decode(t2.encode(), 'x', DateTime.now()).paragraphs.single.lostTerms, ['breaker']);
  });

  test('suggested target is the opposite language', () {
    final svc = TranslationService(FakeEngine());
    expect(svc.suggestedTarget(doc('Hola')), Lang.en);
    expect(svc.suggestedTarget(VsDocument(id: 'x', title: 'x', sourceType: 'text', originalText: 'The panel', language: 'en')), Lang.es);
  });

  test('stored separately from the original and restored', () async {
    sqfliteFfiInit();
    final db = await AppDatabase.open(inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
    final repo = DocumentRepository(db.db);
    final d = doc('Instalar 12 cables.');
    await repo.insert(d);
    final t = await TranslationService(FakeEngine()).translate(d, Lang.en);
    await repo.addDerived(DerivedText(documentId: d.id, kind: Translation.kindFor(Lang.en), content: t.encode(), engine: t.engine));
    final saved = await repo.latestDerived(d.id, 'translation:en');
    final back = Translation.decode(saved!.content, saved.engine, DateTime.now());
    expect(back.text, '[en] Instalar 12 cables.');
    expect((await repo.get(d.id))!.originalText, 'Instalar 12 cables.', reason: 'original untouched');
    expect(await repo.latestDerived(d.id, 'translation:es'), isNull);
    await db.close();
  });
}
