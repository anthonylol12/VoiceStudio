import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../audio/recorder_controller.dart';
import '../database/app_database.dart';
import '../database/repositories.dart';
import '../models/models.dart';
import '../player/reader_audio_handler.dart';
import '../player/reader_controller.dart';
import '../readers/document_importer.dart';
import '../services/backend/backend_client.dart';
import '../services/sync/sync_service.dart';
import '../services/text/speech_normalizer.dart';
import '../services/translation/translation_service.dart';
import '../services/tts/tts_engine.dart';
import '../transcription/live_transcription_controller.dart';
import 'settings.dart';
import '../core/i18n.dart';

/// Composition root. Every engine is created behind an interface here, so a
/// provider can be swapped (system TTS ↔ Piper ↔ cloud, ML Kit ↔ PaddleOCR)
/// without touching screens.
class AppServices {
  AppServices._({
    required this.settings,
    required this.database,
    required this.dataDir,
    required this.backend,
  })  : documents = DocumentRepository(database.db),
        recordings = RecordingRepository(database.db),
        pronunciations = PronunciationRepository(database.db);

  static late AppServices instance;

  final AppSettings settings;
  final AppDatabase database;
  final Directory dataDir;
  final BackendClient backend;
  final DocumentRepository documents;
  final RecordingRepository recordings;
  final PronunciationRepository pronunciations;
  final navigatorKey = GlobalKey<NavigatorState>();
  final dataVersion = ValueNotifier<int>(0); // bump to refresh lists

  late final ReaderController reader;
  late final RecorderController recorder;
  late final LiveTranscriptionController live;
  late final DocumentImporter importer;
  late final SyncService sync;
  late final TranslationService translation;

  /// Media-session bridge (Android/iOS only; null on Windows).
  ReaderAudioHandler? mediaHandler;

  Directory get recordingsDir => Directory(p.join(dataDir.path, 'recordings'));

  static Future<AppServices> init() async {
    final settings = await AppSettings.load();
    final support = await getApplicationSupportDirectory();
    final dataDir = Directory(p.join(support.path, 'VoiceStudio'));
    await dataDir.create(recursive: true);
    final db = await AppDatabase.open(p.join(dataDir.path, 'voice_studio.db'));
    final backend = BackendClient(baseUrl: settings.backendUrl);
    final s = AppServices._(settings: settings, database: db, dataDir: dataDir, backend: backend);
    settings.addListener(() => backend.baseUrl = settings.backendUrl);

    s.reader = ReaderController(
      settings: settings,
      engineFactory: () => settings.ttsEngine == TtsEngineKind.backend ? BackendTtsEngine(backend) : SystemTtsEngine(),
      saveProgress: s.documents.saveProgress,
    );
    if (Platform.isAndroid || Platform.isIOS) {
      // Background reading, lock-screen controls, Bluetooth buttons and the
      // persistent notification. Failure here must not prevent the app from
      // starting: reading still works in the foreground.
      try {
        s.mediaHandler = await AudioService.init(
          builder: () => ReaderAudioHandler(s.reader),
          config: AudioServiceConfig(
            androidNotificationChannelId: 'com.voicestudio.reader',
            androidNotificationChannelName: tr('Lectura en voz alta'),
            androidNotificationOngoing: true,
            androidStopForegroundOnPause: true,
          ),
        );
      } catch (e) {
        debugPrint('audio_service no disponible: $e');
      }
      if (Platform.isAndroid) {
        s.reader.beforeFirstPlay = () async {
          if (await Permission.notification.isDenied) await Permission.notification.request();
        };
      }
    }
    s.recorder = RecorderController(recordingsDir: s.recordingsDir);
    s.live = LiveTranscriptionController(client: backend, settings: settings, recordingsDir: s.recordingsDir);
    final OcrEngine ocr = (Platform.isAndroid || Platform.isIOS)
        ? MlKitOcrEngine()
        : BackendOcrEngine(backend, s.ensureBackendConsent);
    s.importer = DocumentImporter(ocr: ocr, backend: backend, ensureConsent: s.ensureBackendConsent);
    s.translation = TranslationService(defaultTranslationEngine(backend, s.ensureBackendConsent));
    s.sync = SyncService(db: db.db, client: backend, settings: settings, docs: s.documents, recs: s.recordings);
    await s.reloadPronunciations();
    instance = s;
    return s;
  }

  /// The technical dictionary drives both pronunciation and the terms that
  /// translation must keep verbatim.
  Future<void> reloadPronunciations() async {
    final entries = await pronunciations.all();
    reader.normalizer = SpeechNormalizer(dictionary: entries);
    translation.protector = TermProtector(entries.map((e) => TermRule(e.term, caseSensitive: e.caseSensitive)));
  }

  void refresh() => dataVersion.value++;

  /// Asks for explicit consent before audio or documents leave the device.
  /// A backend on localhost keeps data on this machine, but the user is
  /// still informed once.
  Future<bool> ensureBackendConsent() async {
    if (settings.backendConsent) return true;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return false;
    final local = backend.isLocal;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(tr('Procesamiento en el servidor')),
        content: Text(local
            ? tr('Esta función envía el audio o documento al backend de Voice Studio en este equipo ({0}). Los datos no salen del ordenador. ¿Permitir?', [backend.baseUrl])
            : tr('Esta función enviará el audio o documento al servidor {0}. Asegúrate de que confías en ese servidor y de tener el consentimiento de las personas grabadas. ¿Permitir?', [backend.baseUrl])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Permitir'))),
        ],
      ),
    );
    if (ok == true) settings.backendConsent = true;
    return ok == true;
  }

  /// Deletes a recording, its transcript and audio file.
  Future<void> deleteRecording(Recording r) async {
    if (r.syncEnabled) await sync.markDeleted('recording', r.id);
    await recordings.delete(r.id);
    if (r.filePath != null) {
      final f = File(r.filePath!);
      if (await f.exists()) await f.delete();
    }
    refresh();
  }

  Future<void> deleteDocument(VsDocument d) async {
    if (d.syncEnabled) await sync.markDeleted('document', d.id);
    if (reader.document?.id == d.id) {
      await reader.stop();
      reader.document = null;
      reader.units = [];
    }
    await documents.delete(d.id);
    refresh();
  }

  /// Copies an external audio file into the library and transcribes it.
  Future<Recording> importAudio(File source, {required bool transcribe}) async {
    await recordingsDir.create(recursive: true);
    final id = const Uuid().v4();
    final dest = File(p.join(recordingsDir.path, '$id${p.extension(source.path).toLowerCase()}'));
    await source.copy(dest.path);
    final rec = Recording(id: id, title: p.basenameWithoutExtension(source.path), filePath: dest.path, kind: RecordingKind.imported);
    await recordings.insert(rec);
    refresh();
    if (transcribe) await transcribeRecording(rec);
    return rec;
  }

  Future<void> transcribeRecording(Recording rec, {String language = 'auto'}) async {
    if (rec.filePath == null) throw BackendException(tr('Esta transcripción no tiene audio asociado.'));
    if (!await ensureBackendConsent()) throw BackendException(tr('Envío al servidor cancelado.'));
    final result = await backend.transcribe(File(rec.filePath!), language: language, diarize: settings.diarizeByDefault);
    final segs = [
      for (var i = 0; i < result.segments.length; i++)
        TranscriptSegment(
          recordingId: rec.id,
          index: i,
          startMs: result.segments[i].startMs,
          endMs: result.segments[i].endMs,
          speaker: result.segments[i].speaker,
          text: result.segments[i].text,
          language: result.segments[i].language,
        ),
    ];
    await recordings.replaceSegments(rec.id, segs);
    rec.language = result.language ?? rec.language;
    if (result.durationMs > 0) rec.durationMs = result.durationMs;
    await recordings.update(rec);
    refresh();
  }
}
