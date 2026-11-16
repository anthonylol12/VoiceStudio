import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voice_studio/core/settings.dart';
import 'package:voice_studio/database/app_database.dart';
import 'package:voice_studio/database/repositories.dart';
import 'package:voice_studio/models/models.dart';
import 'package:voice_studio/player/reader_controller.dart';
import 'package:voice_studio/services/text/language_detector.dart';
import 'package:voice_studio/services/text/speech_normalizer.dart';
import 'package:voice_studio/services/tts/tts_engine.dart';
import 'package:voice_studio/services/voice_commands/command_parser.dart';

/// Records what would be spoken; completes instantly (or waits when gated).
class FakeTts implements TtsEngine {
  final spoken = <(String, Lang, double)>[];
  Completer<void>? gate;
  @override
  String get id => 'system';
  @override
  Future<void> speak(String text, {required Lang lang, required double speed, required double volume, String voice = ''}) async {
    spoken.add((text, lang, speed));
    if (gate != null) await gate!.future;
  }

  @override
  Future<void> stop() async {
    if (!(gate?.isCompleted ?? true)) gate!.complete();
  }

  @override
  Future<List<TtsVoice>> voices() async => [];
  @override
  Future<void> dispose() async {}
}

void main() {
  late AppDatabase db;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await AppDatabase.open(inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
  });
  tearDown(() => db.close());

  test('documents: insert, pages, search, progress, bookmarks, queue', () async {
    final repo = DocumentRepository(db.db);
    final doc = VsDocument(
      id: 'd1',
      title: 'Orden 5',
      sourceType: 'pdf',
      originalText: 'Página uno.\n\nPágina dos.',
      pages: const [DocumentPage(number: 1, text: 'Página uno.'), DocumentPage(number: 2, text: 'Página dos.')],
      language: 'es',
    );
    await repo.insert(doc);
    expect((await repo.list(query: 'dos')).single.id, 'd1');
    expect((await repo.get('d1'))!.pages.length, 2);
    await repo.saveProgress('d1', 3);
    expect((await repo.get('d1'))!.progressIndex, 3);
    await repo.addBookmark(Bookmark(documentId: 'd1', unitIndex: 1, label: 'Aquí'));
    expect((await repo.bookmarks('d1')).single.label, 'Aquí');
    await repo.enqueue('d1');
    await repo.enqueue('d1');
    expect(await repo.queue(), ['d1']);
    doc.category = DocCategory.order;
    await repo.update(doc);
    expect((await repo.list(category: DocCategory.order)).length, 1);
    expect((await repo.get('d1'))!.version, 2);
    await repo.delete('d1');
    expect(await repo.bookmarks('d1'), isEmpty, reason: 'cascade delete');
  });

  test('recordings: tags, transcript search, speakers, sorting, cascade', () async {
    final repo = RecordingRepository(db.db);
    await repo.insert(Recording(id: 'a', title: 'Zeta', durationMs: 5000));
    await repo.insert(Recording(id: 'b', title: 'Alfa', durationMs: 9000, kind: RecordingKind.live));
    await repo.setTags('a', ['obra', 'Obra', ' urgente ']);
    expect(await repo.tagsFor('a'), ['obra', 'urgente']);
    await repo.replaceSegments('b', [
      TranscriptSegment(recordingId: 'b', index: 0, startMs: 0, endMs: 1000, speaker: 'S1', text: 'revisar los paneles'),
    ]);
    expect((await repo.list(query: 'paneles')).single.id, 'b');
    expect((await repo.list(tag: 'urgente')).single.id, 'a');
    expect((await repo.list(sort: 'name')).map((r) => r.title), ['Alfa', 'Zeta']);
    expect((await repo.list(sort: 'duration')).first.id, 'b');
    expect((await repo.get('b'))!.hasTranscript, isTrue);
    await repo.renameSpeaker('b', 'S1', 'Carlos');
    expect(await repo.speakerNames('b'), {'S1': 'Carlos'});
    await repo.delete('b');
    expect(await repo.segments('b'), isEmpty);
  });

  test('pronunciation dictionary is seeded with technical terms', () async {
    final terms = (await PronunciationRepository(db.db).all()).map((e) => e.term);
    expect(terms, containsAll(['EMT', 'THHN', 'PVC', 'AWG', 'Conduit', 'Romex', 'Feeder']));
  });

  group('ReaderController', () {
    late FakeTts tts;
    late ReaderController reader;
    final progress = <int>[];

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();
      tts = FakeTts();
      progress.clear();
      reader = ReaderController(
        settings: settings,
        engineFactory: () => tts,
        saveProgress: (_, i) async => progress.add(i),
      )..normalizer = SpeechNormalizer(dictionary: defaultPronunciations);
      reader.load(VsDocument(
        id: 'x',
        title: 'Mixto',
        sourceType: 'text',
        originalText: 'Instalar 3/4" de tubo EMT.\n\nPull the wire through the conduit.',
      ));
    });

    test('reads every sentence with per-sentence language and normalization', () async {
      await reader.play();
      expect(tts.spoken.map((e) => e.$2), [Lang.es, Lang.en]);
      expect(tts.spoken.first.$1, 'Instalar tres cuartos de pulgada de tubo E eme te.');
      // The displayed text is never modified.
      expect(reader.units.first.unit.text, 'Instalar 3/4" de tubo EMT.');
      expect(reader.state, PlayerState.idle);
      expect(progress, [0, 1]);
    });

    test('forced language and speed commands', () async {
      await reader.handleCommand(VoiceCommand.readSpanish);
      await reader.handleCommand(VoiceCommand.faster);
      await reader.play();
      expect(tts.spoken.map((e) => e.$2), [Lang.es, Lang.es]);
      expect(tts.spoken.first.$3, 1.25);
    });

    test('pause keeps position; next/previous move; repeat re-speaks', () async {
      tts.gate = Completer();
      unawaited(reader.play());
      await Future<void>.delayed(Duration.zero);
      expect(reader.state, PlayerState.playing);
      await reader.pause();
      expect(reader.state, PlayerState.paused);
      expect(reader.index, 0);
      await reader.next();
      expect(reader.index, 1);
      await reader.previous();
      expect(reader.index, 0);
      tts.gate = null;
      await reader.play(from: 1);
      expect(tts.spoken.last.$1, 'Pull the wire through the conduit.');
    });

    test('playParagraph stops at paragraph end', () async {
      await reader.playParagraph(0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(tts.spoken.length, 1);
    });
  });
}
