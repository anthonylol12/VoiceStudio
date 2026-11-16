import 'dart:convert';

import '../models/models.dart';

/// Export formats for transcripts. Pure functions (unit tested).
class TranscriptExport {
  static String _name(String key, Map<String, String> names) => names[key] ?? defaultSpeakerName(key);

  static String toText(Recording r, List<TranscriptSegment> segs, Map<String, String> names) {
    final b = StringBuffer()
      ..writeln(r.title)
      ..writeln('=' * r.title.length)
      ..writeln();
    for (final s in segs) {
      b
        ..writeln('${_name(s.speaker, names)} — ${formatTimestamp(s.startMs)}')
        ..writeln('"${s.text}"')
        ..writeln();
    }
    return b.toString();
  }

  static String _srtTime(int ms) {
    final d = Duration(milliseconds: ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)},${(ms % 1000).toString().padLeft(3, '0')}';
  }

  static String toSrt(List<TranscriptSegment> segs, Map<String, String> names) {
    final b = StringBuffer();
    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      b
        ..writeln(i + 1)
        ..writeln('${_srtTime(s.startMs)} --> ${_srtTime(s.endMs)}')
        ..writeln('${_name(s.speaker, names)}: ${s.text}')
        ..writeln();
    }
    return b.toString();
  }

  static String toJson(Recording r, List<TranscriptSegment> segs, Map<String, String> names) =>
      const JsonEncoder.withIndent('  ').convert({
        'id': r.id,
        'title': r.title,
        'language': r.language,
        'duration_ms': r.durationMs,
        'speakers': {for (final s in segs.map((e) => e.speaker).toSet()) s: _name(s, names)},
        'segments': segs.map((s) => s.toJson()).toList(),
      });
}
