import 'package:flutter_test/flutter_test.dart';
import 'package:voice_studio/services/text/language_detector.dart';
import 'package:voice_studio/services/text/sentence_splitter.dart';
import 'package:voice_studio/services/text/speech_normalizer.dart';
import 'package:voice_studio/services/voice_commands/command_parser.dart';

void main() {
  group('LanguageDetector', () {
    const d = LanguageDetector();
    test('detects Spanish', () {
      expect(d.detect('Mañana necesitamos comenzar la instalación de los paneles.'), Lang.es);
      expect(d.detect('¿Ya tenemos todos los materiales?'), Lang.es);
    });
    test('detects English', () {
      expect(d.detect('Pull the wires through the conduit and check the breaker.'), Lang.en);
      expect(d.detect('We need to install the panel tomorrow.'), Lang.en);
    });
    test('falls back when no signal', () {
      expect(d.detect('12345', fallback: Lang.en), Lang.en);
    });
  });

  group('SentenceSplitter', () {
    const s = SentenceSplitter();
    test('keeps decimals, abbreviations and numbering intact', () {
      final out = s.sentences('Instalar 3.5 m de tubo aprox. en la pared. Luego revisar el No. 4. Fin.');
      expect(out, ['Instalar 3.5 m de tubo aprox. en la pared.', 'Luego revisar el No. 4.', 'Fin.']);
    });
    test('list items become separate paragraphs', () {
      final p = s.paragraphs('Orden de trabajo:\n1. Cortar 10 ft de EMT.\n2. Pasar 3 cables THHN.\n\nNotas finales');
      expect(p, ['Orden de trabajo:', '1. Cortar 10 ft de EMT.', '2. Pasar 3 cables THHN.', 'Notas finales']);
    });
    test('joins wrapped lines', () {
      expect(s.paragraphs('Esta frase continúa\nen la línea siguiente.'), ['Esta frase continúa en la línea siguiente.']);
    });
    test('does not alter original text', () {
      const text = 'Necesitamos 12 cables #10 AWG de 3/4". ¿Listo?';
      final units = s.units(text);
      expect(units.map((u) => u.text).join(' '), text);
    });
    test('units track pages', () {
      final u = s.units('', pages: ['Página uno.', 'Página dos. Segunda frase.']);
      expect(u.map((e) => e.page).toList(), [1, 2, 2]);
    });
  });

  group('SpeechNormalizer', () {
    final n = SpeechNormalizer(dictionary: defaultPronunciations);
    test('expands fractions and inches in Spanish', () {
      expect(n.normalize('Tubo de 3/4"', Lang.es), 'Tubo de tres cuartos de pulgada');
      expect(n.normalize('Tubo de 1-1/2"', Lang.es), 'Tubo de 1 y un medio pulgadas');
    });
    test('expands units in English', () {
      expect(n.normalize('Run 10 ft of wire', Lang.en), 'Run 10 feet of wire');
      expect(n.normalize("Cut 10' 6\"", Lang.en), 'Cut 10 feet 6 inches');
    });
    test('dates per language', () {
      expect(n.normalize('Entrega 15/11/2026', Lang.es), 'Entrega 15 de noviembre de 2026');
      expect(n.normalize('Due 11/15/2026', Lang.en), 'Due November 15, 2026');
      expect(n.normalize('2026-11-15', Lang.es), '15 de noviembre de 2026');
    });
    test('applies technical dictionary without breaking unit parsing', () {
      expect(n.normalize('12 AWG THHN', Lang.en), '12 A W G T H H N');
      expect(n.normalize('Breaker de 20A', Lang.es), 'bréiker de 20 amperios');
    });
    test('symbols', () {
      expect(n.normalize('Caja #4 al 50%', Lang.es), 'Caja número 4 al 50 por ciento');
      expect(n.normalize('Box 4x4', Lang.en), 'Box 4 by 4');
    });
  });

  group('CommandParser', () {
    const p = CommandParser();
    test('recognizes Spanish and English commands', () {
      expect(p.parse('Pausa'), VoiceCommand.pause);
      expect(p.parse('continúa'), VoiceCommand.resume);
      expect(p.parse('más despacio'), VoiceCommand.slower);
      expect(p.parse('Faster!'), VoiceCommand.faster);
      expect(p.parse('vuelve atrás'), VoiceCommand.previous);
      expect(p.parse('leer en inglés'), VoiceCommand.readEnglish);
      expect(p.parse('Leer en español'), VoiceCommand.readSpanish);
      expect(p.parse('detener lectura'), VoiceCommand.stop);
      expect(p.parse('por favor repite'), VoiceCommand.repeat);
    });
    test('rejects long or unrelated utterances (avoid accidental activation)', () {
      expect(p.parse('hoy vamos a revisar el panel y luego seguimos con la instalación'), isNull);
      expect(p.parse('hola qué tal'), isNull);
      expect(p.parse(''), isNull);
    });
  });
}
