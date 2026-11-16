import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../backend/backend_client.dart';
import 'command_parser.dart';
import '../../core/i18n.dart';

/// Push-to-talk voice commands. The microphone is only opened while the user
/// holds/presses the button, which prevents accidental activations.
class VoiceCommandService extends ChangeNotifier {
  VoiceCommandService({required this.backend, required this.ensureConsent});

  final BackendClient backend;
  final Future<bool> Function() ensureConsent;
  final CommandParser parser = const CommandParser();

  bool listening = false;
  String lastHeard = '';
  String? error;

  SpeechToText? _stt;

  bool get _mobile => Platform.isAndroid || Platform.isIOS;

  /// Listens for one short utterance and returns the parsed command.
  Future<VoiceCommand?> listenOnce() async {
    if (listening) return null;
    listening = true;
    error = null;
    lastHeard = '';
    notifyListeners();
    try {
      final heard = _mobile ? await _systemListen() : await _backendListen();
      lastHeard = heard;
      final cmd = parser.parse(heard);
      if (cmd == null && heard.isNotEmpty) error = tr('No reconocí un comando en: "{0}"', [heard]);
      return cmd;
    } catch (e) {
      error = '$e';
      return null;
    } finally {
      listening = false;
      notifyListeners();
    }
  }

  Future<String> _systemListen() async {
    _stt ??= SpeechToText();
    if (!await _stt!.initialize()) throw Exception(tr('Reconocimiento de voz no disponible.'));
    final done = Completer<String>();
    await _stt!.listen(
      onResult: (r) {
        if (r.finalResult && !done.isCompleted) done.complete(r.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 4),
        pauseFor: const Duration(seconds: 2),
        partialResults: false,
        listenMode: ListenMode.confirmation,
      ),
    );
    return done.future.timeout(const Duration(seconds: 6), onTimeout: () async {
      await _stt!.stop();
      return '';
    });
  }

  Future<String> _backendListen() async {
    if (!await ensureConsent()) return '';
    final rec = AudioRecorder();
    try {
      if (!await rec.hasPermission()) throw Exception(tr('Permiso de micrófono denegado.'));
      final dir = await getTemporaryDirectory();
      final path = p.join(dir.path, 'vs_command.wav');
      await rec.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      await rec.stop();
      final result = await backend.transcribe(File(path), diarize: false);
      return result.segments.map((s) => s.text).join(' ').trim();
    } finally {
      await rec.dispose();
    }
  }
}
