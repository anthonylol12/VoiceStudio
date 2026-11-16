/// Pure-Dart parsers (no platform plugins) so they are unit-testable.
library;

import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

String decodeText(List<int> bytes) {
  // Strip UTF-8 BOM, fall back to Latin-1 for legacy files.
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    bytes = bytes.sublist(3);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// ---------------- WhatsApp exported chats ----------------

final _waLine = RegExp(
  r'^\[?(\d{1,2}[/.]\d{1,2}[/.]\d{2,4}),?\s+(\d{1,2}:\d{2}(?::\d{2})?\s?(?:[ap]\.?\s?m\.?)?)\]?\s*(?:-\s*)?([^:]{1,60}):\s(.*)$',
  caseSensitive: false,
);

bool looksLikeWhatsAppChat(String text) {
  final lines = text.split('\n').where((l) => l.trim().isNotEmpty).take(20).toList();
  if (lines.isEmpty) return false;
  final hits = lines.where((l) => _waLine.hasMatch(l.replaceAll('‎', '').trim())).length;
  return hits >= (lines.length / 2).ceil();
}

/// Formats an exported chat as one paragraph per message:
/// "Ana (15/11/26 10:30): Mañana empezamos".
String formatWhatsAppChat(String text) {
  final out = <String>[];
  for (final raw in text.split('\n')) {
    final line = raw.replaceAll('‎', '').trim();
    if (line.isEmpty) continue;
    final m = _waLine.firstMatch(line);
    if (m != null) {
      out.add('${m[3]!.trim()} (${m[1]} ${m[2]!.trim()}): ${m[4]}');
    } else if (out.isNotEmpty) {
      out[out.length - 1] = '${out.last} $line'; // multi-line message
    } else {
      out.add(line);
    }
  }
  return out.join('\n\n');
}

/// ---------------- Tables (Excel / CSV) ----------------

/// Converts rows into readable text. When the first row looks like a header
/// each row is read as "Header: value; Header: value".
String tableToText(List<List<String>> rows, {String? sheetName}) {
  final clean = rows
      .map((r) => r.map((c) => c.trim()).toList())
      .where((r) => r.any((c) => c.isNotEmpty))
      .toList();
  if (clean.isEmpty) return '';
  final buf = StringBuffer();
  if (sheetName != null) buf.writeln('$sheetName.\n');
  final first = clean.first;
  final isHeader = clean.length > 1 &&
      first.where((c) => c.isNotEmpty).length >= 2 &&
      first.every((c) => c.isEmpty || double.tryParse(c.replaceAll(',', '.')) == null);
  final body = isHeader ? clean.skip(1) : clean;
  var n = 1;
  for (final row in body) {
    final parts = <String>[];
    for (var i = 0; i < row.length; i++) {
      if (row[i].isEmpty) continue;
      final h = isHeader && i < first.length && first[i].isNotEmpty ? '${first[i]}: ' : '';
      parts.add('$h${row[i]}');
    }
    if (parts.isEmpty) continue;
    buf.writeln('${isHeader ? 'Fila $n. ' : ''}${parts.join('; ')}.');
    buf.writeln();
    n++;
  }
  return buf.toString().trim();
}

/// ---------------- HTML / Web ----------------

({String title, String text}) htmlToText(String html) {
  final doc = html_parser.parse(html);
  final title = doc.querySelector('title')?.text.trim() ?? '';
  for (final sel in ['script', 'style', 'noscript', 'nav', 'footer', 'header', 'aside', 'form', 'iframe', 'svg']) {
    for (final e in doc.querySelectorAll(sel)) {
      e.remove();
    }
  }
  dom.Element? root = doc.querySelector('article') ?? doc.querySelector('main') ?? doc.querySelector('[role=main]');
  root ??= _largestTextBlock(doc.body);
  final blocks = <String>[];
  void walk(dom.Element e) {
    const blockTags = {'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'td', 'th', 'blockquote', 'pre', 'dt', 'dd'};
    if (blockTags.contains(e.localName)) {
      final t = e.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isNotEmpty) blocks.add(e.localName == 'li' ? '- $t' : t);
      return;
    }
    for (final c in e.children) {
      walk(c);
    }
  }

  if (root != null) walk(root);
  if (blocks.isEmpty && root != null) {
    blocks.add(root.text.replaceAll(RegExp(r'\s+'), ' ').trim());
  }
  return (title: title, text: blocks.join('\n\n'));
}

dom.Element? _largestTextBlock(dom.Element? body) {
  if (body == null) return null;
  dom.Element best = body;
  var bestScore = 0;
  for (final e in body.querySelectorAll('div, section')) {
    final pCount = e.querySelectorAll('p').length;
    final score = pCount * 50 + e.text.length ~/ 100;
    if (score > bestScore) {
      best = e;
      bestScore = score;
    }
  }
  return best;
}

/// ---------------- E-mail (.eml, RFC 822 / MIME) ----------------

class ParsedEmail {
  ParsedEmail(this.subject, this.from, this.date, this.body, this.attachments);
  final String subject;
  final String from;
  final String date;
  final String body;
  final List<String> attachments;

  String toReadableText() {
    final b = StringBuffer()
      ..writeln('Asunto: $subject.')
      ..writeln()
      ..writeln('De: $from.')
      ..writeln();
    if (date.isNotEmpty) b..writeln('Fecha: $date.')..writeln();
    b.writeln(body.trim());
    if (attachments.isNotEmpty) b..writeln()..writeln('Adjuntos: ${attachments.join(', ')}.');
    return b.toString().trim();
  }
}

ParsedEmail parseEml(String raw) {
  final text = raw.replaceAll('\r\n', '\n');
  final split = text.indexOf('\n\n');
  final headerPart = split < 0 ? text : text.substring(0, split);
  final bodyPart = split < 0 ? '' : text.substring(split + 2);
  final headers = _parseHeaders(headerPart);
  final attachments = <String>[];
  final body = _mimeBody(headers, bodyPart, attachments);
  return ParsedEmail(
    _decodeWords(headers['subject'] ?? '(sin asunto)'),
    _decodeWords(headers['from'] ?? ''),
    headers['date'] ?? '',
    body,
    attachments,
  );
}

Map<String, String> _parseHeaders(String block) {
  final map = <String, String>{};
  String? last;
  for (final line in block.split('\n')) {
    if (line.startsWith(' ') || line.startsWith('\t')) {
      if (last != null) map[last] = '${map[last]} ${line.trim()}';
      continue;
    }
    final i = line.indexOf(':');
    if (i <= 0) continue;
    last = line.substring(0, i).trim().toLowerCase();
    map[last] = line.substring(i + 1).trim();
  }
  return map;
}

String _param(String header, String name) {
  final m = RegExp('$name\\*?="?([^";]+)"?', caseSensitive: false).firstMatch(header);
  return m?.group(1) ?? '';
}

String _mimeBody(Map<String, String> headers, String body, List<String> attachments) {
  final ctype = (headers['content-type'] ?? 'text/plain').toLowerCase();
  if (ctype.startsWith('multipart/')) {
    final boundary = _param(headers['content-type']!, 'boundary');
    if (boundary.isEmpty) return body;
    final parts = body.split('--$boundary');
    String? plain, html;
    for (final part in parts.skip(1)) {
      if (part.startsWith('--')) break;
      final p = part.replaceFirst(RegExp(r'^\n'), '');
      final idx = p.indexOf('\n\n');
      if (idx < 0) continue;
      final h = _parseHeaders(p.substring(0, idx));
      final disp = h['content-disposition'] ?? '';
      final pt = (h['content-type'] ?? 'text/plain').toLowerCase();
      if (disp.toLowerCase().startsWith('attachment')) {
        final name = _param(disp, 'filename');
        attachments.add(_decodeWords(name.isEmpty ? _param(h['content-type'] ?? '', 'name') : name));
        continue;
      }
      final content = _mimeBody(h, p.substring(idx + 2), attachments);
      if (pt.startsWith('text/plain')) {
        plain ??= content;
      } else if (pt.startsWith('text/html')) {
        html ??= content;
      } else if (pt.startsWith('multipart/')) {
        plain ??= content;
      }
    }
    return plain ?? html ?? '';
  }
  final enc = (headers['content-transfer-encoding'] ?? '').toLowerCase();
  final charset = _param(headers['content-type'] ?? '', 'charset').toLowerCase();
  List<int> bytes;
  if (enc == 'base64') {
    try {
      bytes = base64.decode(body.replaceAll(RegExp(r'\s'), ''));
    } catch (_) {
      bytes = utf8.encode(body);
    }
  } else if (enc == 'quoted-printable') {
    bytes = _decodeQuotedPrintable(body);
  } else {
    bytes = utf8.encode(body);
  }
  var decoded = charset.contains('8859') || charset.contains('1252') ? latin1.decode(bytes) : decodeText(bytes);
  if (ctype.startsWith('text/html')) decoded = htmlToText(decoded).text;
  return decoded.trim();
}

List<int> _decodeQuotedPrintable(String s) {
  final out = <int>[];
  final src = s.replaceAll(RegExp(r'=\n'), '');
  for (var i = 0; i < src.length; i++) {
    final c = src[i];
    if (c == '=' && i + 2 < src.length) {
      final v = int.tryParse(src.substring(i + 1, i + 3), radix: 16);
      if (v != null) {
        out.add(v);
        i += 2;
        continue;
      }
    }
    out.addAll(utf8.encode(c));
  }
  return out;
}

/// RFC 2047 encoded words: =?utf-8?B?...?= / =?utf-8?Q?...?=
String _decodeWords(String s) => s.replaceAllMapped(
      RegExp(r'=\?([^?]+)\?([bBqQ])\?([^?]*)\?=', caseSensitive: false),
      (m) {
        final charset = m[1]!.toLowerCase();
        List<int> bytes;
        if (m[2]!.toLowerCase() == 'b') {
          try {
            bytes = base64.decode(m[3]!);
          } catch (_) {
            return m[0]!;
          }
        } else {
          bytes = _decodeQuotedPrintable(m[3]!.replaceAll('_', ' '));
        }
        return charset.contains('8859') || charset.contains('1252') ? latin1.decode(bytes) : decodeText(bytes);
      },
    );
