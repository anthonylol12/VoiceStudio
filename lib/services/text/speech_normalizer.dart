/// Converts display text into a speakable string for TTS engines.
///
/// IMPORTANT: the output is only sent to the speech engine. The original text
/// shown to the user is never modified.
library;

import 'language_detector.dart';

class PronunciationEntry {
  const PronunciationEntry({
    this.id,
    required this.term,
    required this.spokenEs,
    required this.spokenEn,
    this.caseSensitive = false,
  });

  final int? id;
  final String term;
  final String spokenEs;
  final String spokenEn;
  final bool caseSensitive;

  String spoken(Lang lang) => lang == Lang.es ? spokenEs : spokenEn;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'term': term,
        'spoken_es': spokenEs,
        'spoken_en': spokenEn,
        'case_sensitive': caseSensitive ? 1 : 0,
      };

  factory PronunciationEntry.fromMap(Map<String, Object?> m) =>
      PronunciationEntry(
        id: m['id'] as int?,
        term: m['term'] as String,
        spokenEs: m['spoken_es'] as String,
        spokenEn: m['spoken_en'] as String,
        caseSensitive: (m['case_sensitive'] as int? ?? 0) == 1,
      );
}

/// Default technical dictionary (editable by the user in the app).
const defaultPronunciations = <PronunciationEntry>[
  PronunciationEntry(term: 'EMT', spokenEs: 'E eme te', spokenEn: 'E M T', caseSensitive: true),
  PronunciationEntry(term: 'THHN', spokenEs: 'te hache hache ene', spokenEn: 'T H H N', caseSensitive: true),
  PronunciationEntry(term: 'PVC', spokenEs: 'pe uve ce', spokenEn: 'P V C', caseSensitive: true),
  PronunciationEntry(term: 'AWG', spokenEs: 'A W G', spokenEn: 'A W G', caseSensitive: true),
  PronunciationEntry(term: 'Conduit', spokenEs: 'cónduit', spokenEn: 'conduit'),
  PronunciationEntry(term: 'Romex', spokenEs: 'rómex', spokenEn: 'romex'),
  PronunciationEntry(term: 'Electrical panel', spokenEs: 'electrical panel', spokenEn: 'electrical panel'),
  PronunciationEntry(term: 'Circuit breaker', spokenEs: 'circuit breaker', spokenEn: 'circuit breaker'),
  PronunciationEntry(term: 'Feeder', spokenEs: 'fíder', spokenEn: 'feeder'),
  PronunciationEntry(term: 'Breaker', spokenEs: 'bréiker', spokenEn: 'breaker'),
  PronunciationEntry(term: 'GFCI', spokenEs: 'ge efe ce i', spokenEn: 'G F C I', caseSensitive: true),
];

class SpeechNormalizer {
  SpeechNormalizer({List<PronunciationEntry> dictionary = const []})
      : _dictionary = [...dictionary]
          ..sort((a, b) => b.term.length.compareTo(a.term.length));

  final List<PronunciationEntry> _dictionary;

  static const _monthsEs = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
    'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  static const _monthsEn = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December',
  ];

  static const _fractionsEs = {
    '1/2': 'un medio', '1/4': 'un cuarto', '3/4': 'tres cuartos',
    '1/8': 'un octavo', '3/8': 'tres octavos', '5/8': 'cinco octavos',
    '7/8': 'siete octavos', '1/3': 'un tercio', '2/3': 'dos tercios',
  };
  static const _fractionsEn = {
    '1/2': 'one half', '1/4': 'one quarter', '3/4': 'three quarters',
    '1/8': 'one eighth', '3/8': 'three eighths', '5/8': 'five eighths',
    '7/8': 'seven eighths', '1/3': 'one third', '2/3': 'two thirds',
  };

  String normalize(String text, Lang lang) {
    var t = text;
    // Order matters: numeric patterns first so dictionary expansions
    // (e.g. "A W G") are not mistaken for units.
    t = _dates(t, lang);
    t = _measures(t, lang);
    t = _symbols(t, lang);
    t = _applyDictionary(t, lang);
    return t.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  String _applyDictionary(String t, Lang lang) {
    for (final e in _dictionary) {
      final re = RegExp(
        r'(?<![\w])' + RegExp.escape(e.term) + r'(?![\w])',
        caseSensitive: e.caseSensitive,
      );
      t = t.replaceAll(re, e.spoken(lang));
    }
    return t;
  }

  String _dates(String t, Lang lang) {
    // ISO 2026-11-15
    t = t.replaceAllMapped(RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b'), (m) {
      final y = m[1]!, mo = int.parse(m[2]!), d = int.parse(m[3]!);
      return _date(d, mo, y, lang) ?? m[0]!;
    });
    // dd/mm/yyyy (es) or mm/dd/yyyy (en)
    t = t.replaceAllMapped(RegExp(r'\b(\d{1,2})/(\d{1,2})/(\d{4})\b'), (m) {
      final a = int.parse(m[1]!), b = int.parse(m[2]!);
      final y = m[3]!;
      final (d, mo) = lang == Lang.es ? (a, b) : (b, a);
      return _date(d, mo, y, lang) ?? m[0]!;
    });
    return t;
  }

  String? _date(int d, int mo, String y, Lang lang) {
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    return lang == Lang.es
        ? '$d de ${_monthsEs[mo - 1]} de $y'
        : '${_monthsEn[mo - 1]} $d, $y';
  }

  String _measures(String t, Lang lang) {
    final fr = lang == Lang.es ? _fractionsEs : _fractionsEn;
    // Mixed numbers: 1-1/2" or 1 1/2"
    t = t.replaceAllMapped(
      RegExp(r'\b(\d+)[ -](\d/\d{1,2})\s*("|”|in\b|pulg\b)'),
      (m) {
        final f = fr[m[2]] ?? m[2]!;
        return lang == Lang.es
            ? '${m[1]} y $f pulgadas'
            : '${m[1]} and $f inches';
      },
    );
    // Simple fractions with inch mark: 3/4"
    t = t.replaceAllMapped(RegExp(r'(?<![\d/])(\d/\d{1,2})\s*("|”|in\b|pulg\b)'), (m) {
      final f = fr[m[1]] ?? m[1]!;
      return lang == Lang.es ? '$f de pulgada' : '$f inch';
    });
    // Bare known fractions
    t = t.replaceAllMapped(RegExp(r'(?<![\d/])(\d/\d{1,2})(?![\d/])'), (m) {
      return fr[m[1]] ?? m[1]!;
    });
    // Feet and inches: 10' 6"
    t = t.replaceAllMapped(RegExp(r"\b(\d+(?:[.,]\d+)?)\s*'\s*(\d+)\s*\x22"), (m) {
      return lang == Lang.es
          ? '${m[1]} pies ${m[2]} pulgadas'
          : '${m[1]} feet ${m[2]} inches';
    });
    final units = lang == Lang.es
        ? {
            'ft': 'pies', "'": 'pies', '"': 'pulgadas', 'in': 'pulgadas',
            'mm': 'milímetros', 'cm': 'centímetros', 'm': 'metros',
            'km': 'kilómetros', 'kg': 'kilogramos', 'lb': 'libras',
            'lbs': 'libras', 'A': 'amperios', 'V': 'voltios', 'W': 'vatios',
            'kW': 'kilovatios', 'Hz': 'hercios',
          }
        : {
            'ft': 'feet', "'": 'feet', '"': 'inches', 'in': 'inches',
            'mm': 'millimeters', 'cm': 'centimeters', 'm': 'meters',
            'km': 'kilometers', 'kg': 'kilograms', 'lb': 'pounds',
            'lbs': 'pounds', 'A': 'amps', 'V': 'volts', 'W': 'watts',
            'kW': 'kilowatts', 'Hz': 'hertz',
          };
    t = t.replaceAllMapped(
      RegExp(r"\b(\d+(?:[.,]\d+)?)\s?(ft|in|mm|cm|km|kg|lbs|lb|kW|Hz|m|A|V|W)\b|\b(\d+(?:[.,]\d+)?)(['\x22])"),
      (m) {
        final number = m[1] ?? m[3]!;
        final unit = m[2] ?? m[4]!;
        return '$number ${units[unit] ?? unit}';
      },
    );
    return t;
  }

  String _symbols(String t, Lang lang) {
    final es = lang == Lang.es;
    t = t.replaceAllMapped(RegExp(r'(\d)\s?%'), (m) => '${m[1]} ${es ? 'por ciento' : 'percent'}');
    t = t.replaceAllMapped(RegExp(r'#\s?(\d+)'), (m) => '${es ? 'número' : 'number'} ${m[1]}');
    t = t.replaceAllMapped(RegExp(r'\b[xX]\s?(\d+)\b'), (m) => '${es ? 'por' : 'times'} ${m[1]}');
    t = t.replaceAllMapped(RegExp(r'(\d)\s?[xX×]\s?(\d)'), (m) => '${m[1]} ${es ? 'por' : 'by'} ${m[2]}');
    t = t.replaceAll('&', es ? ' y ' : ' and ');
    t = t.replaceAll('@', es ? ' arroba ' : ' at ');
    return t;
  }
}
