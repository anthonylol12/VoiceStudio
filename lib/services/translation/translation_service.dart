import 'dart:convert';
import 'dart:io';

import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../../models/models.dart';
import '../backend/backend_client.dart';
import '../text/language_detector.dart';
import '../text/sentence_splitter.dart';
import '../../core/i18n.dart';

/// Offline translation engine. Android/iOS: Google ML Kit on-device models
/// (~30 MB per language, downloaded once with the user's consent). Windows:
/// the backend (Argos models on CTranslate2, also offline on the PC).
abstract class TranslationEngine {
  String get name;

  /// Whether the model needed for [from]→[to] is available locally.
  Future<bool> isReady(Lang from, Lang to);

  /// Downloads the model(s); only called after the user agreed.
  Future<void> prepare(Lang from, Lang to);

  Future<List<String>> translate(List<String> paragraphs, Lang from, Lang to);
}

class MlKitTranslationEngine implements TranslationEngine {
  final _models = OnDeviceTranslatorModelManager();

  static TranslateLanguage _l(Lang l) => l == Lang.es ? TranslateLanguage.spanish : TranslateLanguage.english;

  @override
  String get name => tr('Google ML Kit (en el dispositivo)');

  @override
  Future<bool> isReady(Lang from, Lang to) async =>
      await _models.isModelDownloaded(_l(from).bcpCode) && await _models.isModelDownloaded(_l(to).bcpCode);

  @override
  Future<void> prepare(Lang from, Lang to) async {
    for (final l in {from, to}) {
      if (!await _models.isModelDownloaded(_l(l).bcpCode)) {
        final ok = await _models.downloadModel(_l(l).bcpCode, isWifiRequired: false);
        if (!ok) throw Exception(tr('No se pudo descargar el modelo de traducción ({0}).', [l.code]));
      }
    }
  }

  @override
  Future<List<String>> translate(List<String> paragraphs, Lang from, Lang to) async {
    final t = OnDeviceTranslator(sourceLanguage: _l(from), targetLanguage: _l(to));
    try {
      return [for (final p in paragraphs) await t.translateText(p)];
    } finally {
      await t.close();
    }
  }
}

class BackendTranslationEngine implements TranslationEngine {
  BackendTranslationEngine(this.client, this.ensureConsent);
  final BackendClient client;
  final Future<bool> Function() ensureConsent;

  @override
  String get name => tr('Argos (backend, sin conexión)');

  @override
  Future<bool> isReady(Lang from, Lang to) async => true; // the server reports missing models itself

  @override
  Future<void> prepare(Lang from, Lang to) async {}

  @override
  Future<List<String>> translate(List<String> paragraphs, Lang from, Lang to) async {
    if (!await ensureConsent()) throw BackendException(tr('Envío al servidor cancelado.'));
    final out = <String>[];
    // Batches keep each request small.
    for (var i = 0; i < paragraphs.length; i += 40) {
      final batch = paragraphs.sublist(i, (i + 40).clamp(0, paragraphs.length));
      out.addAll(await client.translate(batch, source: from.code, target: to.code));
    }
    return out;
  }
}

TranslationEngine defaultTranslationEngine(BackendClient client, Future<bool> Function() consent) =>
    (Platform.isAndroid || Platform.isIOS) ? MlKitTranslationEngine() : BackendTranslationEngine(client, consent);

/// One translated paragraph, with a safety flag when its numbers differ from
/// the original (quantities, measures, dates must never change silently).
class TranslatedParagraph {
  TranslatedParagraph(this.original, this.translation, this.numbersMatch, {this.lostTerms = const []});
  final String original;
  final String translation;
  final bool numbersMatch;

  /// Protected technical terms the engine dropped or altered.
  final List<String> lostTerms;

  bool get ok => numbersMatch && lostTerms.isEmpty;

  Map<String, Object> toJson() => {'o': original, 't': translation, 'n': numbersMatch, 'l': lostTerms};
  factory TranslatedParagraph.fromJson(Map<String, dynamic> j) => TranslatedParagraph(
        j['o'] as String,
        j['t'] as String,
        j['n'] as bool,
        lostTerms: ((j['l'] as List?) ?? const []).map((e) => '$e').toList(),
      );
}

/// Replaces protected technical terms with opaque placeholders before
/// translation and puts the original terms back afterwards.
///
/// Placeholders are all-caps pseudo-acronyms ("ZXQA", "ZXQB"…): tested with
/// the real Argos/OPUS-MT models, they are copied verbatim in both directions,
/// while bracketed or underscored markers get mangled.
class TermProtector {
  TermProtector(Iterable<TermRule> rules)
      : _rules = (rules.where((r) => r.term.trim().isNotEmpty).toList()..sort((a, b) => b.term.length.compareTo(a.term.length)));

  final List<TermRule> _rules;

  static String placeholder(int i) {
    var n = i, s = '';
    do {
      s = String.fromCharCode(65 + n % 26) + s;
      n = n ~/ 26 - 1;
    } while (n >= 0);
    return 'ZXQ$s';
  }

  ({String text, Map<String, String> slots}) protect(String text) {
    final slots = <String, String>{};
    var out = text;
    for (final r in _rules) {
      final re = RegExp(r'(?<![\w])' + RegExp.escape(r.term) + r'(?![\w])', caseSensitive: r.caseSensitive, unicode: true);
      out = out.replaceAllMapped(re, (m) {
        final key = placeholder(slots.length);
        slots[key] = m.group(0)!; // keep the exact original spelling
        return key;
      });
    }
    return (text: out, slots: slots);
  }

  /// Restores terms; returns the terms whose placeholder did not survive.
  ({String text, List<String> lost}) restore(String translated, Map<String, String> slots) {
    var out = translated;
    final lost = <String>[];
    // Longest keys first so "ZXQAB" is not partially matched by "ZXQA".
    final keys = slots.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      final re = RegExp(r'\b' + key + r'\b', caseSensitive: false);
      if (re.hasMatch(out)) {
        out = out.replaceAll(re, slots[key]!);
      } else {
        lost.add(slots[key]!);
      }
    }
    return (text: out, lost: lost);
  }
}

class TermRule {
  const TermRule(this.term, {this.caseSensitive = false});
  final String term;
  final bool caseSensitive;
}

class Translation {
  Translation(this.target, this.engine, this.paragraphs, {DateTime? createdAt}) : createdAt = createdAt ?? DateTime.now();
  final Lang target;
  final String engine;
  final List<TranslatedParagraph> paragraphs;
  final DateTime createdAt;

  int get warnings => paragraphs.where((p) => !p.ok).length;
  String get text => paragraphs.map((p) => p.translation).join('\n\n');

  static String kindFor(Lang target) => 'translation:${target.code}';

  String encode() => jsonEncode({'target': target.code, 'paragraphs': paragraphs.map((p) => p.toJson()).toList()});

  static Translation decode(String content, String engine, DateTime createdAt) {
    final j = jsonDecode(content) as Map<String, dynamic>;
    return Translation(
      LangCode.parse(j['target'] as String)!,
      engine,
      (j['paragraphs'] as List).map((e) => TranslatedParagraph.fromJson(e as Map<String, dynamic>)).toList(),
      createdAt: createdAt,
    );
  }
}

/// Digit groups of a text, order-independent: "1.500" and "1,500" both give
/// [1, 500]; "3/4"" gives [3, 4]; dates keep day/month/year.
List<String> numberTokens(String text) =>
    (RegExp(r'\d+').allMatches(text).map((m) => int.parse(m.group(0)!).toString()).toList()..sort());

bool sameNumbers(String a, String b) {
  final x = numberTokens(a), y = numberTokens(b);
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

class TranslationService {
  TranslationService(this.engine, {this.splitter = const SentenceSplitter(), this.detector = const LanguageDetector()});

  final TranslationEngine engine;
  final SentenceSplitter splitter;
  final LanguageDetector detector;

  /// Technical terms kept verbatim (normally the pronunciation dictionary).
  TermProtector protector = TermProtector(const []);

  /// Target language: the opposite of the document's dominant language.
  Lang suggestedTarget(VsDocument doc) =>
      (LangCode.parse(doc.language) ?? detector.detect(doc.originalText)) == Lang.es ? Lang.en : Lang.es;

  /// Translates paragraph by paragraph. Paragraphs already in the target
  /// language (mixed documents) are kept unchanged.
  Future<Translation> translate(VsDocument doc, Lang target) async {
    final paragraphs = splitter.paragraphs(doc.originalText);
    final source = target == Lang.es ? Lang.en : Lang.es;
    final toTranslate = <int>[
      for (var i = 0; i < paragraphs.length; i++)
        if (detector.detect(paragraphs[i], fallback: source) != target) i,
    ];
    final protectedTexts = [for (final i in toTranslate) protector.protect(paragraphs[i])];
    final translated = toTranslate.isEmpty
        ? <String>[]
        : await engine.translate([for (final p in protectedTexts) p.text], source, target);
    final byIndex = <int, ({String text, List<String> lost})>{
      for (var k = 0; k < toTranslate.length; k++) toTranslate[k]: protector.restore(translated[k], protectedTexts[k].slots),
    };
    return Translation(target, engine.name, [
      for (var i = 0; i < paragraphs.length; i++)
        TranslatedParagraph(
          paragraphs[i],
          byIndex[i]?.text ?? paragraphs[i],
          sameNumbers(paragraphs[i], byIndex[i]?.text ?? paragraphs[i]),
          lostTerms: byIndex[i]?.lost ?? const [],
        ),
    ]);
  }
}
