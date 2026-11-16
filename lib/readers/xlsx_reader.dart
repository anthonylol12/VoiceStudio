/// Minimal, dependency-light XLSX reader (Office Open XML = ZIP + XML).
///
/// Reads cell values (shared strings, inline strings, numbers, booleans and
/// cached formula results) per sheet. Formatting is ignored on purpose: the
/// goal is to read tables of materials and quantities aloud.
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class XlsxSheet {
  XlsxSheet(this.name, this.rows);
  final String name;
  final List<List<String>> rows;
}

class XlsxFormatException implements Exception {
  XlsxFormatException(this.message);
  final String message;
  @override
  String toString() => 'Excel no válido: $message';
}

List<XlsxSheet> readXlsx(List<int> bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw XlsxFormatException('no es un archivo ZIP/XLSX ($e)');
  }
  XmlDocument? doc(String path) {
    final f = zip.findFile(path);
    if (f == null) return null;
    return XmlDocument.parse(utf8.decode(f.content, allowMalformed: true));
  }

  final workbook = doc('xl/workbook.xml');
  if (workbook == null) throw XlsxFormatException('falta xl/workbook.xml');

  // Relationship id -> sheet XML path
  final rels = <String, String>{};
  for (final r in doc('xl/_rels/workbook.xml.rels')?.findAllElements('Relationship') ?? const <XmlElement>[]) {
    var target = r.getAttribute('Target') ?? '';
    target = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    rels[r.getAttribute('Id') ?? ''] = target;
  }

  final shared = <String>[
    for (final si in doc('xl/sharedStrings.xml')?.findAllElements('si') ?? const <XmlElement>[])
      si.findAllElements('t').map((t) => t.innerText).join(),
  ];

  final sheets = <XlsxSheet>[];
  var index = 1;
  for (final s in workbook.findAllElements('sheet')) {
    final name = s.getAttribute('name') ?? 'Hoja $index';
    final rid = s.attributes.where((a) => a.name.local == 'id').map((a) => a.value).firstOrNull ?? '';
    final path = rels[rid] ?? 'xl/worksheets/sheet$index.xml';
    index++;
    final sheetDoc = doc(path);
    if (sheetDoc == null) continue;
    final rows = <List<String>>[];
    for (final row in sheetDoc.findAllElements('row')) {
      final cells = <int, String>{};
      var nextCol = 0;
      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r');
        final col = ref == null ? nextCol : columnIndex(ref);
        nextCol = col + 1;
        cells[col] = _cellValue(c, shared);
      }
      if (cells.isEmpty) {
        rows.add(const []);
        continue;
      }
      final maxCol = cells.keys.reduce((a, b) => a > b ? a : b);
      rows.add([for (var i = 0; i <= maxCol; i++) cells[i] ?? '']);
    }
    sheets.add(XlsxSheet(name, rows));
  }
  return sheets;
}

String _cellValue(XmlElement c, List<String> shared) {
  final type = c.getAttribute('t');
  final v = c.getElement('v')?.innerText ?? '';
  switch (type) {
    case 's':
      final i = int.tryParse(v);
      return i != null && i < shared.length ? shared[i] : '';
    case 'inlineStr':
      return c.findAllElements('t').map((t) => t.innerText).join();
    case 'b':
      return v == '1' ? 'Sí' : 'No';
    default:
      // Numbers: drop a trailing ".0" so "4.0" is read as "4".
      final n = num.tryParse(v);
      if (n != null && n == n.roundToDouble() && v.contains('.') && !v.contains('E')) {
        return n.toInt().toString();
      }
      return v;
  }
}

/// "A1" -> 0, "B7" -> 1, "AA3" -> 26.
int columnIndex(String ref) {
  var col = 0;
  for (final ch in ref.toUpperCase().codeUnits) {
    if (ch < 65 || ch > 90) break;
    col = col * 26 + (ch - 64);
  }
  return col - 1;
}
