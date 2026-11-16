import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_studio/readers/text_formats.dart';
import 'package:voice_studio/readers/xlsx_reader.dart';

List<int> buildXlsx() {
  final files = {
    'xl/workbook.xml': '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        '<sheet name="Materiales" sheetId="1" r:id="rId1"/><sheet name="Notas" sheetId="2" r:id="rId2"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="worksheet" Target="/xl/worksheets/sheet2.xml"/></Relationships>',
    'xl/sharedStrings.xml': '<?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<si><t>Material</t></si><si><t>Cantidad</t></si><si><r><t>Cable </t></r><r><t>THHN 12</t></r></si></sst>',
    'xl/worksheets/sheet1.xml': '<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
        '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>'
        '<row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>500.0</v></c></row>'
        '<row r="3"><c r="A3" t="inlineStr"><is><t>Breaker 20A</t></is></c><c r="C3"><v>4</v></c></row>'
        '</sheetData></worksheet>',
    'xl/worksheets/sheet2.xml': '<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
        '<row r="1"><c r="A1" t="b"><v>1</v></c><c r="B1" t="str"><v>Fórmula</v></c></row></sheetData></worksheet>',
  };
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encode(archive);
}

void main() {
  test('reads shared, inline, rich, numeric, boolean and formula cells', () {
    final sheets = readXlsx(buildXlsx());
    expect(sheets.map((s) => s.name), ['Materiales', 'Notas']);
    expect(sheets[0].rows, [
      ['Material', 'Cantidad'],
      ['Cable THHN 12', '500'],
      ['Breaker 20A', '', '4'],
    ]);
    expect(sheets[1].rows.single, ['Sí', 'Fórmula']);
    expect(tableToText(sheets[0].rows), contains('Fila 1. Material: Cable THHN 12; Cantidad: 500.'));
  });

  test('column letters', () {
    expect(columnIndex('A1'), 0);
    expect(columnIndex('Z9'), 25);
    expect(columnIndex('AA3'), 26);
  });

  test('invalid file is reported', () {
    expect(() => readXlsx([1, 2, 3]), throwsA(isA<XlsxFormatException>()));
  });
}
