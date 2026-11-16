import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../audio/pcm_converter.dart';
import '../audio/wav_writer.dart';
import '../core/settings.dart';
import '../models/models.dart';
import '../services/backend/backend_client.dart';
import '../core/i18n.dart';

enum LiveState { idle, connecting, listening, finishing, error }

class LiveSegment {
  LiveSegment(this.startMs, this.endMs, this.text, this.language, this.speaker);
  int startMs;
  int endMs;
  String text;
  String? language;
  String speaker;
}

/// Real-time transcription.
///
/// * backend: streams 16 kHz PCM to the Voice Studio backend over WebSocket
///   (faster-whisper), while saving the same audio locally as WAV so every
///   segment stays linked to its position in the recording.
/// * system: Android/iOS on-device recognizer (speech_to_text). Text only;
///   the OS recognizer owns the microphone so no audio file is produced.
class LiveTranscriptionController extends ChangeNotifier {
  LiveTranscriptionController({required this.client, required this.settings, required this.recordingsDir});

  final BackendClient client;
  final AppSettings settings;
  final Directory recordingsDir;

  LiveState state = LiveState.idle;
  String? error;
  String partial = '';
  final List<LiveSegment> segments = [];
  String languageMode = 'auto';
  Duration elapsed = Duration.zero;
  double level = 0;

  String? _id;
  String? _wavPath;
  AudioRecorder? _rec;
  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription<Amplitude>? _ampSub;
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  WavWriter? _wav;
  Completer<void>? _done;
  final Stopwatch _watch = Stopwatch();
  Timer? _ticker;
  SpeechToText? _stt;
  bool _sttActive = false;

  bool get isRunning => state == LiveState.listening || state == LiveState.connecting;
  bool get usesBackend => settings.liveEngine == LiveEngineKind.backend || !(Platform.isAndroid || Platform.isIOS);

  Future<void> start() async {
    if (isRunning) return;
    segments.clear();
    partial = '';
    error = null;
    _id = const Uuid().v4();
    state = LiveState.connecting;
    notifyListeners();
    try {
      if (usesBackend) {
        await _startBackend();
      } else {
        await _startSystem();
      }
      state = LiveState.listening;
      _watch
        ..reset()
        ..start();
      _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
        elapsed = _watch.elapsed;
        notifyListeners();
      });
    } catch (e) {
      await _teardown();
      state = LiveState.error;
      error = '$e';
    }
    notifyListeners();
  }

  Future<void> _startBackend() async {
    await client.token();
    _rec = AudioRecorder();
    if (!await _rec!.hasPermission()) throw Exception(tr('Permiso de micrófono denegado.'));
    const config = RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1);
    if (!await _rec!.isEncoderSupported(AudioEncoder.pcm16bits)) {
      throw Exception(tr('Este dispositivo no permite capturar audio PCM.'));
    }
    final ws = WebSocketChannel.connect(client.liveUri(language: languageMode));
    try {
      await ws.ready.timeout(const Duration(seconds: 8));
    } catch (e) {
      throw BackendException(tr('No se pudo conectar al servicio de transcripción en {0}. ¿Está el backend en marcha? ({1})', [client.baseUrl, e]));
    }
    _ws = ws;
    _done = Completer<void>();
    _wsSub = ws.stream.listen(_onMessage, onError: (Object e) {
      error = tr('Conexión interrumpida: {0}', [e]);
      notifyListeners();
    }, onDone: () {
      if (!(_done?.isCompleted ?? true)) _done!.complete();
    });
    await recordingsDir.create(recursive: true);
    _wavPath = p.join(recordingsDir.path, '$_id.wav');
    _wav = WavWriter(_wavPath!);
    await _wav!.open();
    // The device may not honour 16 kHz mono (Windows adapts the format to the
    // microphone). Keep the real format in the WAV header and send 16 kHz
    // mono to the server, which is what Whisper and the segmenter expect.
    final converter = PcmConverter();
    await _rec!.setOnConfigChanged((actual) {
      debugPrint('Formato real del micrófono: ${actual.sampleRate} Hz, ${actual.numChannels} canal(es)');
      converter.configure(sampleRate: actual.sampleRate, numChannels: actual.numChannels);
      _wav?.sampleRate = actual.sampleRate;
      _wav?.channels = actual.numChannels;
    });
    final stream = await _rec!.startStream(config);
    _audioSub = stream.listen((chunk) {
      _wav?.add(chunk);
      final pcm16k = converter.convert(chunk);
      if (pcm16k.isNotEmpty) _ws?.sink.add(pcm16k);
    });
    _ampSub = _rec!.onAmplitudeChanged(const Duration(milliseconds: 150)).listen((a) {
      level = ((a.current + 50) / 50).clamp(0.0, 1.0);
    });
  }

  void _onMessage(dynamic msg) {
    if (msg is! String) return;
    final j = jsonDecode(msg) as Map<String, dynamic>;
    switch (j['type']) {
      case 'partial':
        partial = '${j['text'] ?? ''}';
      case 'segment':
        partial = '';
        segments.add(LiveSegment(
          (j['start_ms'] as num).toInt(),
          (j['end_ms'] as num).toInt(),
          '${j['text']}',
          j['language'] as String?,
          '${j['speaker'] ?? 'S1'}',
        ));
      case 'speakers':
        // Server re-labels speakers once enough audio is available.
        final labels = (j['segments'] as List).cast<Map<String, dynamic>>();
        for (var i = 0; i < labels.length && i < segments.length; i++) {
          segments[i].speaker = '${labels[i]['speaker']}';
        }
      case 'error':
        error = '${j['detail']}';
      case 'done':
        if (!(_done?.isCompleted ?? true)) _done!.complete();
    }
    notifyListeners();
  }

  Future<void> _startSystem() async {
    _stt = SpeechToText();
    final ok = await _stt!.initialize(onError: (e) {
      if (e.permanent) {
        error = tr('Reconocedor del sistema: {0}', [e.errorMsg]);
        notifyListeners();
      }
    }, onStatus: (s) {
      // The OS recognizer stops after silence; restart while the session lives.
      if ((s == 'done' || s == 'notListening') && _sttActive) {
        Future.delayed(const Duration(milliseconds: 250), _listenOnce);
      }
    });
    if (!ok) throw Exception(tr('El reconocimiento de voz del sistema no está disponible en este dispositivo.'));
    _sttActive = true;
    await _listenOnce();
  }

  int _utteranceStart = 0;

  Future<void> _listenOnce() async {
    if (!_sttActive || _stt == null || _stt!.isListening) return;
    _utteranceStart = _watch.elapsedMilliseconds;
    final locale = switch (languageMode) { 'en' => 'en_US', 'es' => 'es_ES', _ => null };
    await _stt!.listen(
      onResult: (SpeechRecognitionResult r) {
        if (r.finalResult) {
          if (r.recognizedWords.trim().isNotEmpty) {
            segments.add(LiveSegment(_utteranceStart, _watch.elapsedMilliseconds, r.recognizedWords.trim(),
                languageMode == 'auto' ? null : languageMode, 'S1'));
          }
          partial = '';
        } else {
          partial = r.recognizedWords;
        }
        notifyListeners();
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        localeId: locale,
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(minutes: 5),
      ),
    );
  }

  /// Stops capture, waits for the final segments and returns the saved
  /// recording plus its transcript (caller persists them).
  Future<(Recording, List<TranscriptSegment>)?> stop({required String title}) async {
    if (!isRunning) return null;
    state = LiveState.finishing;
    notifyListeners();
    _watch.stop();
    if (usesBackend) {
      await _audioSub?.cancel();
      await _rec?.stop();
      _ws?.sink.add('stop');
      try {
        await _done?.future.timeout(const Duration(seconds: 60));
      } catch (_) {
        error = tr('El servidor tardó demasiado en finalizar; se guardó lo recibido.');
      }
      await _wav?.close();
    } else {
      _sttActive = false;
      await _stt?.stop();
      if (partial.trim().isNotEmpty) {
        segments.add(LiveSegment(_utteranceStart, _watch.elapsedMilliseconds, partial.trim(), null, 'S1'));
      }
    }
    final duration = _wav?.duration ?? _watch.elapsed;
    final rec = Recording(
      id: _id!,
      title: title,
      filePath: _wavPath,
      durationMs: duration.inMilliseconds,
      kind: RecordingKind.live,
      language: _dominantLanguage(),
    );
    final segs = [
      for (var i = 0; i < segments.length; i++)
        TranscriptSegment(
          recordingId: _id!,
          index: i,
          startMs: segments[i].startMs,
          endMs: segments[i].endMs,
          speaker: segments[i].speaker,
          text: segments[i].text,
          language: segments[i].language,
        ),
    ];
    await _teardown();
    state = LiveState.idle;
    notifyListeners();
    return (rec, segs);
  }

  String? _dominantLanguage() {
    final counts = <String, int>{};
    for (final s in segments) {
      if (s.language != null) counts[s.language!] = (counts[s.language!] ?? 0) + s.text.length;
    }
    if (counts.isEmpty) return languageMode == 'auto' ? null : languageMode;
    return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }

  Future<void> _teardown() async {
    _ticker?.cancel();
    await _audioSub?.cancel();
    await _ampSub?.cancel();
    await _wsSub?.cancel();
    await _ws?.sink.close();
    await _wav?.close();
    try {
      await _rec?.stop();
    } catch (_) {}
    await _rec?.dispose();
    _rec = null;
    _ws = null;
    _wav = null;
    _sttActive = false;
    level = 0;
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}
