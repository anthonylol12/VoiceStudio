import 'dart:typed_data';

/// Streaming PCM16 converter: interleaved N-channel audio at any sample rate
/// → mono 16 kHz, which is what the transcription backend expects.
///
/// Microphones often ignore the requested format (Windows adjusts it to the
/// device's capabilities), so live audio must be normalised on the client.
/// State (fractional position, last sample, odd byte) is kept between chunks
/// so there are no clicks or drift at chunk boundaries.
class PcmConverter {
  PcmConverter({this.sourceRate = 16000, this.channels = 1, this.targetRate = 16000});

  int sourceRate;
  int channels;
  final int targetRate;

  final _pending = BytesBuilder(copy: false);
  double _pos = 0; // position in source frames, relative to the next chunk start
  double _prev = 0; // last mono sample of the previous chunk (for interpolation)
  bool _hasPrev = false;

  bool get isPassthrough => sourceRate == targetRate && channels == 1;

  void configure({required int sampleRate, required int numChannels}) {
    sourceRate = sampleRate;
    channels = numChannels < 1 ? 1 : numChannels;
  }

  Uint8List convert(Uint8List chunk) {
    _pending.add(chunk);
    final all = _pending.takeBytes();
    final frameBytes = 2 * channels;
    final usable = all.length - all.length % frameBytes;
    if (usable < all.length) _pending.add(Uint8List.sublistView(all, usable));
    if (usable == 0) return Uint8List(0);
    if (isPassthrough) return Uint8List.fromList(Uint8List.sublistView(all, 0, usable));

    final data = ByteData.sublistView(all, 0, usable);
    final frames = usable ~/ frameBytes;
    double sample(int f) {
      if (f < 0) return _prev;
      var sum = 0;
      for (var c = 0; c < channels; c++) {
        sum += data.getInt16((f * channels + c) * 2, Endian.little);
      }
      return sum / channels;
    }

    final step = sourceRate / targetRate;
    final out = BytesBuilder();
    final buf = ByteData(2);
    // Interpolate between frame floor(pos) and floor(pos)+1; index -1 is the
    // last sample of the previous chunk.
    var pos = _hasPrev ? _pos : 0.0;
    while (pos <= frames - 1) {
      final i = pos.floor();
      final frac = pos - i;
      final a = sample(i);
      final b = i + 1 < frames ? sample(i + 1) : a;
      final v = (a + (b - a) * frac).round().clamp(-32768, 32767);
      buf.setInt16(0, v, Endian.little);
      out.add(buf.buffer.asUint8List(0, 2));
      pos += step;
    }
    _pos = pos - frames; // carry the fractional position into the next chunk
    _prev = sample(frames - 1);
    _hasPrev = true;
    return out.takeBytes();
  }
}
