import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/settings.dart';
import '../models/models.dart';
import '../services/text/language_detector.dart';
import '../services/text/sentence_splitter.dart';
import '../services/text/speech_normalizer.dart';
import '../services/tts/tts_engine.dart';
import '../services/voice_commands/command_parser.dart';
import '../core/i18n.dart';

enum PlayerState { idle, playing, paused, error }

class ReadingUnit {
  ReadingUnit(this.unit, this.lang);
  final TextUnit unit;
  final Lang lang;
}

/// Sentence-by-sentence reading engine. Each sentence is spoken separately,
/// which gives precise "repeat sentence", next/previous and resume support
/// on every platform regardless of the TTS engine's own capabilities.
class ReaderController extends ChangeNotifier {
  ReaderController({
    required this.settings,
    required TtsEngine Function() engineFactory,
    required this.saveProgress,
    this.splitter = const SentenceSplitter(),
    this.detector = const LanguageDetector(),
  }) : _engineFactory = engineFactory; // ignore: prefer_initializing_formals

  final AppSettings settings;
  final TtsEngine Function() _engineFactory;
  final Future<void> Function(String documentId, int index) saveProgress;
  final SentenceSplitter splitter;
  final LanguageDetector detector;

  SpeechNormalizer normalizer = SpeechNormalizer();
  TtsEngine? _engine;
  VsDocument? document;
  List<ReadingUnit> units = [];
  int index = 0;
  PlayerState state = PlayerState.idle;
  String? error;
  int _session = 0;

  /// Index where reading should stop (exclusive); null = end of document.
  int? stopAt;

  /// Runs once before the first playback (e.g. ask for the notification
  /// permission that the background media notification needs).
  Future<void> Function()? beforeFirstPlay;
  bool _firstPlayDone = false;

  bool get hasDocument => document != null && units.isNotEmpty;
  ReadingUnit? get current => hasDocument && index < units.length ? units[index] : null;

  void load(VsDocument doc, {int? startIndex}) {
    stop();
    document = doc;
    final pages = doc.pages.isEmpty ? null : doc.pages.map((p) => p.text).toList();
    final docLang = LangCode.parse(doc.language) ?? Lang.es;
    units = splitter
        .units(doc.originalText, pages: pages)
        .map((u) => ReadingUnit(u, detector.detect(u.text, fallback: docLang)))
        .toList();
    index = (startIndex ?? doc.progressIndex).clamp(0, units.isEmpty ? 0 : units.length - 1);
    stopAt = null;
    settings.lastReadDocumentId = doc.id;
    notifyListeners();
  }

  Lang _langFor(ReadingUnit u) => switch (settings.readLanguage) {
        ReadLanguageMode.es => Lang.es,
        ReadLanguageMode.en => Lang.en,
        ReadLanguageMode.auto => u.lang,
      };

  TtsEngine get engine {
    final wanted = settings.ttsEngine == TtsEngineKind.backend ? 'backend' : 'system';
    if (_engine == null || _engine!.id != wanted) {
      _engine?.dispose();
      _engine = _engineFactory();
    }
    return _engine!;
  }

  Future<void> play({int? from, int? until}) async {
    if (!hasDocument) return;
    if (!_firstPlayDone) {
      _firstPlayDone = true;
      try {
        await beforeFirstPlay?.call();
      } catch (_) {
        // Permission prompts must never block reading.
      }
    }
    if (from != null) index = from.clamp(0, units.length - 1);
    if (until != null) stopAt = until;
    final session = ++_session;
    state = PlayerState.playing;
    error = null;
    notifyListeners();
    try {
      while (session == _session && index < (stopAt ?? units.length)) {
        final u = units[index];
        final lang = _langFor(u);
        final spoken = normalizer.normalize(u.unit.text, lang);
        unawaited(saveProgress(document!.id, index));
        await engine.speak(
          spoken,
          lang: lang,
          speed: settings.speed,
          volume: settings.volume,
          voice: settings.ttsEngine == TtsEngineKind.backend
              ? settings.backendVoiceFor(lang.code)
              : settings.voiceFor(lang.code),
        );
        if (session != _session) return;
        if (index + 1 >= (stopAt ?? units.length)) break;
        index++;
        notifyListeners();
      }
      if (session == _session) {
        state = PlayerState.idle;
        stopAt = null;
        notifyListeners();
      }
    } catch (e) {
      if (session != _session) return;
      state = PlayerState.error;
      error = tr('No se pudo reproducir: {0}', [e]);
      notifyListeners();
    }
  }

  Future<void> pause() async {
    if (state != PlayerState.playing) return;
    _session++;
    state = PlayerState.paused;
    notifyListeners();
    await _engine?.stop();
  }

  /// Resumes from the start of the current sentence.
  Future<void> resume() => play();

  Future<void> togglePlay() => state == PlayerState.playing ? pause() : play();

  Future<void> stop() async {
    _session++;
    state = PlayerState.idle;
    stopAt = null;
    notifyListeners();
    await _engine?.stop();
  }

  Future<void> _jump(int newIndex) async {
    if (!hasDocument) return;
    final wasPlaying = state == PlayerState.playing;
    await _engine?.stop();
    _session++;
    index = newIndex.clamp(0, units.length - 1);
    if (document != null) unawaited(saveProgress(document!.id, index));
    notifyListeners();
    if (wasPlaying) unawaited(play());
  }

  Future<void> next() => _jump(index + 1);
  Future<void> previous() => _jump(index - 1);

  Future<void> repeatSentence() async {
    await _engine?.stop();
    _session++;
    unawaited(play());
  }

  /// Jump to the first sentence of the next/previous paragraph.
  Future<void> nextParagraph() async {
    final p = current?.unit.paragraph ?? 0;
    final i = units.indexWhere((u) => u.unit.paragraph > p);
    if (i >= 0) await _jump(i);
  }

  Future<void> previousParagraph() async {
    final p = current?.unit.paragraph ?? 0;
    final i = units.indexWhere((u) => u.unit.paragraph == p - 1);
    if (i >= 0) await _jump(i);
  }

  /// Plays only the paragraph or page containing [i].
  Future<void> playParagraph(int i) {
    final p = units[i].unit.paragraph;
    final first = units.indexWhere((u) => u.unit.paragraph == p);
    final last = units.lastIndexWhere((u) => u.unit.paragraph == p);
    return _restartRange(first, last + 1);
  }

  Future<void> playPage(int page) {
    final first = units.indexWhere((u) => u.unit.page == page);
    final last = units.lastIndexWhere((u) => u.unit.page == page);
    if (first < 0) return Future.value();
    return _restartRange(first, last + 1);
  }

  Future<void> _restartRange(int from, int until) async {
    await _engine?.stop();
    _session++;
    unawaited(play(from: from, until: until));
  }

  void setSpeed(double s) {
    settings.speed = s;
    notifyListeners();
    if (state == PlayerState.playing) repeatSentence();
  }

  void changeSpeed(int delta) {
    final speeds = AppSettings.speeds;
    var i = speeds.indexOf(settings.speed);
    if (i < 0) i = 1;
    setSpeed(speeds[(i + delta).clamp(0, speeds.length - 1)]);
  }

  void setVolume(double v) {
    settings.volume = v;
    notifyListeners();
  }

  void setLanguageMode(ReadLanguageMode m) {
    settings.readLanguage = m;
    notifyListeners();
    if (state == PlayerState.playing) repeatSentence();
  }

  Future<void> handleCommand(VoiceCommand c) async {
    switch (c) {
      case VoiceCommand.pause:
        await pause();
      case VoiceCommand.resume:
        await play();
      case VoiceCommand.repeat:
        await repeatSentence();
      case VoiceCommand.slower:
        changeSpeed(-1);
      case VoiceCommand.faster:
        changeSpeed(1);
      case VoiceCommand.next:
        await next();
      case VoiceCommand.previous:
        await previous();
      case VoiceCommand.readEnglish:
        setLanguageMode(ReadLanguageMode.en);
      case VoiceCommand.readSpanish:
        setLanguageMode(ReadLanguageMode.es);
      case VoiceCommand.stop:
        await stop();
    }
  }

  @override
  void dispose() {
    _session++;
    _engine?.dispose();
    super.dispose();
  }
}
