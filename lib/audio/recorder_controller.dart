import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../core/i18n.dart';

enum RecState { idle, recording, paused, stopped }

/// Manual-only audio recorder. The microphone is opened exclusively when the
/// user presses "start"; there is no automatic or hidden activation.
class RecorderController extends ChangeNotifier {
  RecorderController({required this.recordingsDir});

  final Directory recordingsDir;
  AudioRecorder? _rec;
  RecState state = RecState.idle;
  String? filePath;
  String? error;
  bool? micPermission;
  double level = 0; // 0..1
  Duration elapsed = Duration.zero;
  int fileBytes = 0;
  String? _id;

  final Stopwatch _watch = Stopwatch();
  Timer? _ticker;
  StreamSubscription<Amplitude>? _ampSub;

  String? get recordingId => _id;

  Future<void> start() async {
    if (state == RecState.recording || state == RecState.paused) return;
    error = null;
    _rec = AudioRecorder();
    micPermission = await _rec!.hasPermission();
    if (micPermission != true) {
      error = tr('Permiso de micrófono denegado. Actívalo en los ajustes del sistema.');
      notifyListeners();
      return;
    }
    await recordingsDir.create(recursive: true);
    _id = const Uuid().v4();
    var encoder = AudioEncoder.aacLc;
    var ext = 'm4a';
    if (!await _rec!.isEncoderSupported(encoder)) {
      encoder = AudioEncoder.wav;
      ext = 'wav';
    }
    filePath = p.join(recordingsDir.path, '$_id.$ext');
    try {
      await _rec!.start(
        RecordConfig(encoder: encoder, sampleRate: 16000, numChannels: 1, bitRate: 64000),
        path: filePath!,
      );
    } catch (e) {
      error = tr('No se pudo iniciar la grabación: {0}', [e]);
      notifyListeners();
      return;
    }
    state = RecState.recording;
    elapsed = Duration.zero;
    _watch
      ..reset()
      ..start();
    _ampSub = _rec!.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((a) {
      // dBFS (-160..0) -> 0..1, with -50 dB as floor
      level = ((a.current + 50) / 50).clamp(0.0, 1.0);
      notifyListeners();
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      elapsed = _watch.elapsed;
      final f = File(filePath!);
      if (await f.exists()) fileBytes = await f.length();
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> pause() async {
    if (state != RecState.recording) return;
    await _rec?.pause();
    _watch.stop();
    level = 0;
    state = RecState.paused;
    notifyListeners();
  }

  Future<void> resume() async {
    if (state != RecState.paused) return;
    await _rec?.resume();
    _watch.start();
    state = RecState.recording;
    notifyListeners();
  }

  /// Stops and returns an unsaved [Recording] (caller persists it).
  Future<Recording?> finish({required String title}) async {
    if (state != RecState.recording && state != RecState.paused) return null;
    final path = await _rec?.stop();
    _cleanup();
    state = RecState.stopped;
    elapsed = _watch.elapsed;
    notifyListeners();
    if (path == null) return null;
    final f = File(path);
    fileBytes = await f.exists() ? await f.length() : 0;
    return Recording(id: _id!, title: title, filePath: path, durationMs: elapsed.inMilliseconds);
  }

  /// Discards the current take and deletes the file.
  Future<void> discard() async {
    try {
      await _rec?.stop();
    } catch (_) {}
    _cleanup();
    if (filePath != null) {
      final f = File(filePath!);
      if (await f.exists()) await f.delete();
    }
    reset();
  }

  void reset() {
    state = RecState.idle;
    filePath = null;
    elapsed = Duration.zero;
    fileBytes = 0;
    level = 0;
    _id = null;
    notifyListeners();
  }

  void _cleanup() {
    _ticker?.cancel();
    _ampSub?.cancel();
    _watch.stop();
    level = 0;
    _rec?.dispose();
    _rec = null;
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return tr('{0} KB', [(b / 1024).toStringAsFixed(1)]);
  if (b < 1024 * 1024 * 1024) return tr('{0} MB', [(b / 1024 / 1024).toStringAsFixed(1)]);
  return tr('{0} GB', [(b / 1024 / 1024 / 1024).toStringAsFixed(2)]);
}
