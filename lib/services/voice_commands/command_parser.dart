/// Bilingual parser for reader voice commands.
///
/// To avoid accidental activations in noisy places, an utterance is only
/// accepted when it is short and matches a known command phrase.
library;

enum VoiceCommand {
  pause,
  resume,
  repeat,
  slower,
  faster,
  next,
  previous,
  readEnglish,
  readSpanish,
  stop,
}

class CommandParser {
  const CommandParser({this.maxWords = 5});

  final int maxWords;

  static const Map<VoiceCommand, List<String>> phrases = {
    VoiceCommand.pause: ['pausa', 'pausar', 'pause', 'espera', 'wait'],
    VoiceCommand.resume: ['continua', 'continúa', 'continuar', 'sigue', 'seguir', 'reanudar', 'resume', 'continue', 'play', 'reproducir'],
    VoiceCommand.repeat: ['repite', 'repetir', 'otra vez', 'repeat', 'again', 'say again'],
    VoiceCommand.slower: ['mas despacio', 'más despacio', 'mas lento', 'más lento', 'slower', 'slow down'],
    VoiceCommand.faster: ['mas rapido', 'más rápido', 'faster', 'speed up'],
    VoiceCommand.next: ['siguiente', 'next', 'adelante', 'skip'],
    VoiceCommand.previous: ['vuelve atras', 'vuelve atrás', 'atras', 'atrás', 'anterior', 'go back', 'back', 'previous'],
    VoiceCommand.readEnglish: ['leer en ingles', 'leer en inglés', 'lee en ingles', 'lee en inglés', 'read in english', 'english'],
    VoiceCommand.readSpanish: ['leer en espanol', 'leer en español', 'lee en español', 'lee en espanol', 'read in spanish', 'spanish', 'español'],
    VoiceCommand.stop: ['detener lectura', 'detener', 'para', 'parar', 'alto', 'stop', 'stop reading'],
  };

  static String _clean(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[¿?¡!.,;:"]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Returns the command or null when the utterance is not a command.
  VoiceCommand? parse(String utterance) {
    final text = _clean(utterance);
    if (text.isEmpty) return null;
    if (text.split(' ').length > maxWords) return null;
    // Exact match first, then longest-phrase containment ("por favor pausa").
    VoiceCommand? best;
    var bestLen = 0;
    for (final entry in phrases.entries) {
      for (final p in entry.value) {
        final phrase = _clean(p);
        if (text == phrase) return entry.key;
        final re = RegExp(r'(^| )' + RegExp.escape(phrase) + r'($| )');
        if (re.hasMatch(text) && phrase.length > bestLen) {
          best = entry.key;
          bestLen = phrase.length;
        }
      }
    }
    return best;
  }
}
