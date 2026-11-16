import 'package:audio_service/audio_service.dart';

import '../core/settings.dart';
import 'reader_controller.dart';
import '../core/i18n.dart';

/// Bridges [ReaderController] to the OS media session (audio_service):
/// background playback, lock-screen controls, Bluetooth/headset buttons and
/// the persistent Android notification. Commands from the system are mapped
/// onto the same reader methods the on-screen buttons use.
class ReaderAudioHandler extends BaseAudioHandler {
  ReaderAudioHandler(this.reader) {
    reader.addListener(_sync);
    _sync();
  }

  final ReaderController reader;

  /// "Repeat sentence" uses the rewind slot so it appears on the lock screen
  /// and maps to the headset's rewind button.
  static MediaControl get repeatControl => MediaControl(
    androidIcon: 'drawable/audio_service_fast_rewind',
    label: tr('Repetir frase'),
    action: MediaAction.rewind,
  );

  void _sync() {
    final doc = reader.document;
    if (doc != null) {
      final current = reader.current?.unit.text ?? '';
      final item = MediaItem(
        id: doc.id,
        title: doc.title,
        album: tr('Voice Studio'),
        artist: tr('Frase {0} de {1}', [reader.index + 1, reader.units.length]),
        displaySubtitle: current,
        displayDescription: current,
      );
      // MediaItem equality only compares `id`, so compare the visible fields.
      final old = mediaItem.value;
      if (old == null || old.id != item.id || old.title != item.title || old.artist != item.artist || old.displaySubtitle != item.displaySubtitle) {
        mediaItem.add(item);
      }
    }
    final playing = reader.state == PlayerState.playing;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        repeatControl,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.rewind, MediaAction.fastForward},
      androidCompactActionIndices: const [0, 2, 3],
      processingState: switch (reader.state) {
        PlayerState.idle when doc == null => AudioProcessingState.idle,
        PlayerState.error => AudioProcessingState.error,
        _ => AudioProcessingState.ready,
      },
      playing: playing,
      speed: reader.settings.speed,
      queueIndex: reader.index,
      errorMessage: reader.error,
    ));
  }

  @override
  Future<void> play() => reader.play();

  @override
  Future<void> pause() => reader.pause();

  @override
  Future<void> stop() async {
    await reader.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() => reader.next();

  @override
  Future<void> skipToPrevious() => reader.previous();

  @override
  Future<void> rewind() => reader.repeatSentence();

  /// Headset double-press / fast-forward: next paragraph.
  @override
  Future<void> fastForward() => reader.nextParagraph();

  @override
  Future<void> setSpeed(double speed) async {
    // Snap to the supported speeds.
    final s = AppSettings.speeds.reduce((a, b) => (a - speed).abs() <= (b - speed).abs() ? a : b);
    reader.setSpeed(s);
  }

  void dispose() => reader.removeListener(_sync);
}
