import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_studio/audio/pcm_converter.dart';

Uint8List pcm(List<int> samples) {
  final b = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    b.setInt16(i * 2, samples[i], Endian.little);
  }
  return b.buffer.asUint8List();
}

List<int> samplesOf(Uint8List bytes) {
  final b = ByteData.sublistView(bytes);
  return [for (var i = 0; i < bytes.length ~/ 2; i++) b.getInt16(i * 2, Endian.little)];
}

void main() {
  test('16 kHz mono passes through unchanged', () {
    final c = PcmConverter();
    final input = pcm([1, -2, 3, 32767, -32768]);
    expect(c.convert(input), input);
  });

  test('stereo is mixed down to mono', () {
    final c = PcmConverter(sourceRate: 16000, channels: 2);
    expect(samplesOf(c.convert(pcm([100, 300, -50, -150]))), [200, -100]);
  });

  test('48 kHz becomes 16 kHz with the right length and frequency', () {
    final c = PcmConverter(sourceRate: 48000, channels: 1);
    // 1 s of a 440 Hz tone, delivered in uneven chunks (odd byte counts too).
    final tone = [for (var i = 0; i < 48000; i++) (10000 * sin(2 * pi * 440 * i / 48000)).round()];
    final bytes = pcm(tone);
    final out = <int>[];
    var i = 0;
    for (final size in [1001, 3, 47000, 48996]) {
      final end = min(i + size, bytes.length);
      out.addAll(samplesOf(c.convert(Uint8List.sublistView(bytes, i, end))));
      i = end;
    }
    expect(out.length, closeTo(16000, 2));
    // Count zero crossings: 440 Hz → ~880 per second.
    var crossings = 0;
    for (var k = 1; k < out.length; k++) {
      if ((out[k - 1] < 0) != (out[k] < 0)) crossings++;
    }
    expect(crossings, closeTo(880, 6));
  });

  test('format reported mid-stream is applied (Windows onConfigChanged)', () {
    final c = PcmConverter()..configure(sampleRate: 32000, numChannels: 2);
    final stereo32k = pcm([for (var i = 0; i < 3200; i++) 1000]); // 1600 stereo frames = 50 ms
    expect(samplesOf(c.convert(stereo32k)).length, closeTo(800, 1)); // 50 ms at 16 kHz
  });
}
