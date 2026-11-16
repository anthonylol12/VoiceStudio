import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../backend/backend_client.dart';
import '../text/language_detector.dart';

class TtsVoice {
  const TtsVoice(this.name, this.locale);
  final String name;
  final String locale;
}

/// Speech engine abstraction: local system voices, Piper (backend) or a
/// cloud provider (backend) are interchangeable.
abstract class TtsEngine {
  String get id;

  /// Speaks [text] and completes when the utterance finished or was stopped.
  Future<void> speak(String text, {required Lang lang, required double speed, required double volume, String voice = ''});

  Future<void> stop();

  Future<List<TtsVoice>> voices();

  Future<void> dispose();
}

/// Uses the OS speech engine (Android TTS, AVSpeechSynthesizer, Windows
/// SAPI/OneCore) through flutter_tts. Fully offline when voices are installed.
class SystemTtsEngine implements TtsEngine {
  SystemTtsEngine() {
    _tts.awaitSpeakCompletion(true);
  }

  final FlutterTts _tts = FlutterTts();

  @override
  String get id => 'system';

  // flutter_tts uses 0.5 as the "normal" rate on Android/iOS and 1.0 on Windows.
  double _rate(double speed) {
    if (Platform.isAndroid) return (0.5 * speed).clamp(0.1, 1.0);
    if (Platform.isIOS) return (0.5 * speed).clamp(0.0, 1.0);
    return speed.clamp(0.5, 3.0);
  }

  @override
  Future<void> speak(String text, {required Lang lang, required double speed, required double volume, String voice = ''}) async {
    await _tts.setLanguage(lang.ttsLocale);
    if (voice.isNotEmpty) {
      await _tts.setVoice({'name': voice, 'locale': lang.ttsLocale});
    }
    await _tts.setSpeechRate(_rate(speed));
    await _tts.setVolume(volume.clamp(0.0, 1.0));
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async => _tts.stop();

  @override
  Future<List<TtsVoice>> voices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((v) => TtsVoice('${v['name']}', '${v['locale'] ?? ''}'))
        .where((v) => v.locale.toLowerCase().startsWith('es') || v.locale.toLowerCase().startsWith('en'))
        .toList();
  }

  @override
  Future<void> dispose() => stop();
}

/// Synthesises on the backend (Piper locally, or Azure Speech when
/// configured) and plays the returned WAV.
class BackendTtsEngine implements TtsEngine {
  BackendTtsEngine(this.client);

  final BackendClient client;
  final AudioPlayer _player = AudioPlayer();
  Completer<void>? _playing;
  StreamSubscription<void>? _sub;
  int _generation = 0;

  @override
  String get id => 'backend';

  @override
  Future<void> speak(String text, {required Lang lang, required double speed, required double volume, String voice = ''}) async {
    final gen = ++_generation;
    final bytes = await client.tts(text, language: lang.code, voice: voice);
    if (gen != _generation) return; // stopped while synthesising
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'vs_tts_${gen % 4}.wav'));
    await file.writeAsBytes(bytes, flush: true);
    _playing = Completer<void>();
    _sub?.cancel();
    _sub = _player.onPlayerComplete.listen((_) {
      if (!(_playing?.isCompleted ?? true)) _playing!.complete();
    });
    await _player.setVolume(volume);
    await _player.setPlaybackRate(speed);
    await _player.play(DeviceFileSource(file.path));
    await _playing!.future;
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _player.stop();
    if (!(_playing?.isCompleted ?? true)) _playing!.complete();
  }

  @override
  Future<List<TtsVoice>> voices() async {
    final names = await client.ttsVoices();
    return names.map((n) => TtsVoice(n, n.split('-').first)).toList();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _sub?.cancel();
    await _player.dispose();
  }
}
