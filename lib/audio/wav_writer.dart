import 'dart:io';
import 'dart:typed_data';

/// Streams PCM16 mono audio into a WAV file, patching the header on close.
class WavWriter {
  WavWriter(this.path, {this.sampleRate = 16000, this.channels = 1});

  final String path;

  /// May be updated while recording (the header is rewritten on close) when
  /// the device reports its real format.
  int sampleRate;
  int channels;
  RandomAccessFile? _raf;
  int _dataBytes = 0;

  int get dataBytes => _dataBytes;
  Duration get duration => Duration(milliseconds: (_dataBytes / (sampleRate * channels * 2) * 1000).round());

  Future<void> open() async {
    _raf = await File(path).open(mode: FileMode.write);
    await _raf!.writeFrom(header(0, sampleRate: sampleRate, channels: channels));
  }

  Future<void> add(Uint8List pcm) async {
    if (_raf == null) return;
    await _raf!.writeFrom(pcm);
    _dataBytes += pcm.length;
  }

  Future<void> close() async {
    final raf = _raf;
    if (raf == null) return;
    _raf = null;
    await raf.setPosition(0);
    await raf.writeFrom(header(_dataBytes, sampleRate: sampleRate, channels: channels));
    await raf.close();
  }

  static Uint8List header(int dataLength, {int sampleRate = 16000, int channels = 1}) {
    final b = ByteData(44);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    const bits = 16;
    str(0, 'RIFF');
    b.setUint32(4, 36 + dataLength, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, channels, Endian.little);
    b.setUint32(24, sampleRate, Endian.little);
    b.setUint32(28, sampleRate * channels * bits ~/ 8, Endian.little);
    b.setUint16(32, channels * bits ~/ 8, Endian.little);
    b.setUint16(34, bits, Endian.little);
    str(36, 'data');
    b.setUint32(40, dataLength, Endian.little);
    return b.buffer.asUint8List();
  }
}
