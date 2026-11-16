/// Lightweight, offline Spanish/English language detector.
///
/// Uses stop-word frequency plus orthographic cues (ñ, accents, ¿ ¡).
/// Works per sentence so mixed-language documents can switch voices.
library;

enum Lang { es, en }

extension LangCode on Lang {
  String get code => this == Lang.es ? 'es' : 'en';
  String get ttsLocale => this == Lang.es ? 'es-ES' : 'en-US';
  static Lang? parse(String? value) {
    if (value == null) return null;
    final v = value.toLowerCase();
    if (v.startsWith('es')) return Lang.es;
    if (v.startsWith('en')) return Lang.en;
    return null;
  }
}

class LanguageDetector {
  const LanguageDetector();

  static const _es = {
    'el', 'la', 'los', 'las', 'de', 'del', 'que', 'y', 'en', 'un', 'una',
    'por', 'para', 'con', 'no', 'es', 'se', 'al', 'lo', 'como', 'más',
    'pero', 'sus', 'su', 'ya', 'o', 'este', 'esta', 'son', 'entre', 'cuando',
    'muy', 'sin', 'sobre', 'también', 'hasta', 'hay', 'donde', 'desde',
    'todo', 'nos', 'durante', 'todos', 'uno', 'ni', 'contra', 'otros', 'ese',
    'eso', 'ante', 'ellos', 'esto', 'antes', 'algunos', 'qué', 'unos', 'yo',
    'otro', 'otras', 'otra', 'él', 'tanto', 'esa', 'estos', 'mucho',
    'quienes', 'nada', 'muchos', 'cual', 'poco', 'ella', 'estar', 'necesitamos',
    'instalar', 'revisar', 'tenemos', 'mañana', 'cables', 'cable', 'tubería',
    'cantidad', 'pies', 'pulgadas', 'metros', 'materiales', 'instalación',
  };

  static const _en = {
    'the', 'of', 'and', 'to', 'in', 'is', 'you', 'that', 'it', 'he', 'was',
    'for', 'on', 'are', 'as', 'with', 'his', 'they', 'at', 'be', 'this',
    'have', 'from', 'or', 'one', 'had', 'by', 'but', 'not', 'what', 'all',
    'were', 'we', 'when', 'your', 'can', 'said', 'there', 'use', 'an',
    'each', 'which', 'she', 'do', 'how', 'their', 'if', 'will', 'up', 'other',
    'about', 'out', 'many', 'then', 'them', 'these', 'so', 'some', 'her',
    'would', 'make', 'like', 'into', 'has', 'more', 'two', 'need', 'install',
    'check', 'wire', 'wires', 'feet', 'inches', 'panel', 'breaker', 'please',
    'tomorrow', 'materials', 'should', 'must', 'run', 'pull',
  };

  static final _wordRe = RegExp(r"[a-záéíóúüñ']+", caseSensitive: false);

  /// Returns the detected language, or [fallback] when there is no signal.
  Lang detect(String text, {Lang fallback = Lang.es}) {
    final scores = score(text);
    if (scores.es == 0 && scores.en == 0) return fallback;
    if (scores.es == scores.en) return fallback;
    return scores.es > scores.en ? Lang.es : Lang.en;
  }

  ({double es, double en}) score(String text) {
    final lower = text.toLowerCase();
    double es = 0, en = 0;
    for (final m in _wordRe.allMatches(lower)) {
      final w = m.group(0)!;
      if (_es.contains(w)) es += 1;
      if (_en.contains(w)) en += 1;
      if (RegExp('[ñáéíóú]').hasMatch(w)) es += 1.5;
      if (w.contains("'")) en += 0.5;
      if (w.endsWith('ción') || w.endsWith('mente')) es += 1;
      if (w.endsWith('ing') || w.endsWith('tion')) en += 0.7;
    }
    if (lower.contains('¿') || lower.contains('¡')) es += 2;
    return (es: es, en: en);
  }
}
