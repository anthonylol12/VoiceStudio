import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_studio/core/i18n.dart';
import 'package:voice_studio/core/settings.dart';
import 'package:voice_studio/models/models.dart';
import 'package:voice_studio/player/reader_audio_handler.dart';
import 'package:voice_studio/player/reader_controller.dart' as rc;

import 'database_and_reader_test.dart' show FakeTts;

void main() {
  late FakeTts tts;
  late rc.ReaderController reader;
  late ReaderAudioHandler handler;
  var permissionAsked = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'uiLanguage': 'es'});
    tts = FakeTts();
    permissionAsked = 0;
    reader = rc.ReaderController(settings: await AppSettings.load(), engineFactory: () => tts, saveProgress: (_, _) async {})
      ..beforeFirstPlay = () async => permissionAsked++;
    reader.load(VsDocument(
      id: 'd',
      title: 'Orden 12',
      sourceType: 'text',
      originalText: 'Primera frase. Segunda frase.\n\nTercer párrafo.',
    ));
    handler = ReaderAudioHandler(reader);
  });

  tearDown(() => handler.dispose());

  test('publishes the document as the lock-screen media item', () {
    expect(handler.mediaItem.value?.title, 'Orden 12');
    expect(handler.mediaItem.value?.displaySubtitle, 'Primera frase.');
    expect(handler.mediaItem.value?.artist, 'Frase 1 de 3');
    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.playbackState.value.controls, contains(MediaControl.play));
  });

  test('lock-screen text follows the interface language', () async {
    reader.settings.uiLanguage = UiLanguage.en;
    await reader.next();
    expect(handler.mediaItem.value?.artist, 'Sentence 2 of 3');
    reader.settings.uiLanguage = UiLanguage.es;
  });

  test('system media commands drive the reader', () async {
    tts.gate = Completer();
    unawaited(handler.play());
    await Future<void>.delayed(Duration.zero);
    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.playbackState.value.controls, contains(MediaControl.pause));
    expect(permissionAsked, 1);

    await handler.pause();
    expect(reader.state, rc.PlayerState.paused);
    expect(handler.playbackState.value.playing, isFalse);

    await handler.skipToNext();
    expect(reader.index, 1);
    expect(handler.mediaItem.value?.displaySubtitle, 'Segunda frase.');
    await handler.skipToPrevious();
    expect(reader.index, 0);
    await handler.fastForward(); // next paragraph
    expect(reader.index, 2);

    await handler.setSpeed(1.6);
    expect(reader.settings.speed, 1.5);

    tts.gate = null;
    await handler.rewind(); // repeat sentence
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(tts.spoken.last.$1, 'Tercer párrafo.');

    await handler.stop();
    expect(reader.state, rc.PlayerState.idle);
    expect(permissionAsked, 1, reason: 'asked only once');
  });
}
