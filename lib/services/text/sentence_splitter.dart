/// Splits document text into paragraphs and sentences without altering the
/// original characters (numbering, quantities and punctuation are preserved).
library;

class TextUnit {
  const TextUnit({
    required this.text,
    required this.paragraph,
    required this.sentence,
    this.page,
  });

  /// Original text, untouched.
  final String text;
  final int paragraph;
  final int sentence;
  final int? page;
}

class SentenceSplitter {
  const SentenceSplitter();

  static const _abbreviations = {
    'no', 'nro', 'núm', 'sr', 'sra', 'dr', 'dra', 'ing', 'aprox', 'approx',
    'etc', 'ej', 'e.g', 'i.e', 'vs', 'ft', 'in', 'pulg', 'mr', 'mrs', 'ms',
    'st', 'av', 'avda', 'pág', 'pag', 'p', 'fig', 'ref', 'qty', 'cant', 'ud',
    'uds', 'inc', 'ltd', 'co', 'jr',
  };

  /// Paragraphs are separated by one or more line breaks. A line starting
  /// with a list marker is always its own paragraph.
  List<String> paragraphs(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return normalized
        .split(RegExp(r'\n\s*\n|\n(?=\s*(?:\d+[.)]|[-•*–]|[a-zA-Z][.)])\s)'))
        .expand((p) => _splitSingleLines(p))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
  }

  // Single newlines inside a block: join wrapped lines unless the previous
  // line ends with terminal punctuation or a colon.
  Iterable<String> _splitSingleLines(String block) sync* {
    final lines = block.split('\n');
    final buffer = StringBuffer();
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (buffer.isNotEmpty) {
        final prev = buffer.toString();
        if (RegExp(r'[.!?:;]$').hasMatch(prev)) {
          yield prev;
          buffer.clear();
        } else {
          buffer.write(' ');
        }
      }
      buffer.write(line);
    }
    if (buffer.isNotEmpty) yield buffer.toString();
  }

  List<String> sentences(String paragraph) {
    final result = <String>[];
    var start = 0;
    final s = paragraph;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c != '.' && c != '!' && c != '?' && c != '…') continue;
      // Consume repeated terminators and closing quotes/brackets.
      var end = i + 1;
      while (end < s.length && '.!?…"\')»”'.contains(s[end])) {
        end++;
      }
      if (end >= s.length) break;
      if (s[end] != ' ') continue;
      if (c == '.' && _isNonTerminalDot(s, i)) continue;
      // Next visible char must look like a sentence start.
      var next = end;
      while (next < s.length && s[next] == ' ') {
        next++;
      }
      if (next >= s.length) break;
      final n = s[next];
      final startsSentence = RegExp(r'[A-ZÁÉÍÓÚÑ¿¡"“«(0-9]').hasMatch(n);
      if (!startsSentence) continue;
      result.add(s.substring(start, end).trim());
      start = next;
      i = next - 1;
    }
    final tail = s.substring(start).trim();
    if (tail.isNotEmpty) result.add(tail);
    return result;
  }

  bool _isNonTerminalDot(String s, int i) {
    // Decimal number: 3.5
    if (i > 0 && i + 1 < s.length && _isDigit(s[i - 1]) && _isDigit(s[i + 1])) {
      return true;
    }
    // Word before the dot
    var j = i - 1;
    while (j >= 0 && RegExp(r'[A-Za-zÁÉÍÓÚÑáéíóúñ.]').hasMatch(s[j])) {
      j--;
    }
    final word = s.substring(j + 1, i).toLowerCase();
    if (word.isEmpty) {
      // List marker like "1. " at paragraph start
      final before = s.substring(0, i).trim();
      return RegExp(r'^\d+$').hasMatch(before);
    }
    if (_abbreviations.contains(word)) return true;
    if (word.length == 1 && RegExp(r'[a-z]').hasMatch(word)) return true;
    return false;
  }

  bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  /// Builds reading units for an entire document. [pages] maps a page number
  /// to its text; when null the whole [text] is treated as one page.
  List<TextUnit> units(String text, {List<String>? pages}) {
    final out = <TextUnit>[];
    var paragraphIndex = 0;
    final sources = pages ?? [text];
    for (var p = 0; p < sources.length; p++) {
      for (final para in paragraphs(sources[p])) {
        final ss = sentences(para);
        for (var k = 0; k < ss.length; k++) {
          out.add(TextUnit(
            text: ss[k],
            paragraph: paragraphIndex,
            sentence: k,
            page: pages == null ? null : p + 1,
          ));
        }
        paragraphIndex++;
      }
    }
    return out;
  }
}
