import 'dart:io';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart' as csvlib;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/backend/backend_client.dart';
import '../services/text/language_detector.dart';
import 'text_formats.dart';
import 'xlsx_reader.dart';
import '../core/i18n.dart';

class ImportException implements Exception {
  ImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// OCR abstraction: Google ML Kit on Android/iOS (on-device, offline);
/// PaddleOCR models on the backend for Windows.
abstract class OcrEngine {
  Future<String> recognize(File image);
}

class MlKitOcrEngine implements OcrEngine {
  @override
  Future<String> recognize(File image) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(image.path));
      return result.blocks.map((b) => b.text).join('\n\n');
    } finally {
      await recognizer.close();
    }
  }
}

class BackendOcrEngine implements OcrEngine {
  BackendOcrEngine(this.client, this.ensureConsent);
  final BackendClient client;
  final Future<bool> Function() ensureConsent;
  @override
  Future<String> recognize(File image) async {
    if (!await ensureConsent()) throw ImportException(tr('Envío al servidor cancelado por el usuario.'));
    return client.ocr(image);
  }
}

class DocumentImporter {
  DocumentImporter({required this.ocr, required this.backend, required this.ensureConsent});

  final OcrEngine ocr;
  final BackendClient backend;
  final Future<bool> Function() ensureConsent;
  final _uuid = Uuid();
  final _detector = LanguageDetector();

  static final imageExt = {'.jpg', '.jpeg', '.png', '.webp', '.bmp'};
  static final supportedExt = {
    '.pdf', '.txt', '.md', '.csv', '.xlsx', '.xls', '.eml', '.html', '.htm', '.zip',
    ...imageExt,
  };

  static bool isSupported(String path) => supportedExt.contains(p.extension(path).toLowerCase());

  VsDocument _build(String title, String type, String? path, String text, {List<String>? pages}) {
    final body = text.trim();
    if (body.isEmpty) throw ImportException(tr('No se encontró texto legible en "{0}".', [title]));
    return VsDocument(
      id: _uuid.v4(),
      title: title,
      sourceType: type,
      sourcePath: path,
      originalText: body,
      pages: [
        if (pages != null)
          for (var i = 0; i < pages.length; i++) DocumentPage(number: i + 1, text: pages[i]),
      ],
      language: _detector.detect(body).code,
    );
  }

  Future<VsDocument> importFile(File file) async {
    final ext = p.extension(file.path).toLowerCase();
    final title = p.basenameWithoutExtension(file.path);
    if (!await file.exists()) throw ImportException(tr('El archivo no existe: {0}', [file.path]));
    switch (ext) {
      case '.pdf':
        return _pdf(file, title);
      case '.txt':
      case '.md':
        final text = decodeText(await file.readAsBytes());
        if (looksLikeWhatsAppChat(text)) {
          return _build(title, 'whatsapp', file.path, formatWhatsAppChat(text));
        }
        return _build(title, 'text', file.path, text);
      case '.zip':
        return _zip(file, title);
      case '.csv':
        final rows = csvlib.csv.decode(decodeText(await file.readAsBytes()));
        return _build(title, 'csv', file.path,
            tableToText(rows.map((r) => r.map((c) => '${c ?? ''}').toList()).toList()));
      case '.xlsx':
        return _xlsx(file, title);
      case '.xls':
        // Legacy binary Excel is parsed server-side (xlrd).
        return _viaBackend(file, title, 'excel');
      case '.eml':
        final mail = parseEml(decodeText(await file.readAsBytes()));
        return _build(mail.subject, 'email', file.path, mail.toReadableText());
      case '.html':
      case '.htm':
        final page = htmlToText(decodeText(await file.readAsBytes()));
        return _build(page.title.isEmpty ? title : page.title, 'web', file.path, page.text);
      default:
        if (imageExt.contains(ext)) {
          final text = await ocr.recognize(file);
          return _build(title, 'image', file.path, text);
        }
        throw ImportException(tr('Formato no compatible: {0}', [ext]));
    }
  }

  Future<VsDocument> importText(String text, {String? title, String type = 'text'}) async {
    final t = title ?? tr('Texto pegado');
    if (looksLikeWhatsAppChat(text)) return _build(t, 'whatsapp', null, formatWhatsAppChat(text));
    return _build(t, type, null, text);
  }

  Future<VsDocument> importUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw ImportException(tr('Enlace no válido. Debe empezar por http:// o https://'));
    }
    final http.Response r;
    try {
      r = await http.get(uri, headers: {'User-Agent': 'VoiceStudio/0.1 (reader)'}).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw ImportException(tr('No se pudo descargar la página: {0}', [e]));
    }
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw ImportException(tr('La página requiere autenticación o no permite el acceso (HTTP {0}).', [r.statusCode]));
    }
    if (r.statusCode != 200) throw ImportException(tr('La página respondió HTTP {0}.', [r.statusCode]));
    final page = htmlToText(decodeText(r.bodyBytes));
    return _build(page.title.isEmpty ? uri.host : page.title, 'web', url, page.text);
  }

  Future<VsDocument> _pdf(File file, String title) async {
    await pdfrxFlutterInitialize();
    final doc = await PdfDocument.openFile(file.path);
    final pages = <String>[];
    try {
      for (final page in doc.pages) {
        final t = await page.loadText();
        pages.add(t?.fullText.trim() ?? '');
      }
    } finally {
      await doc.dispose();
    }
    if (pages.every((t) => t.isEmpty)) {
      // Scanned PDF: no text layer. Server renders pages and applies OCR.
      return _viaBackend(file, title, 'pdf');
    }
    return _build(title, 'pdf', file.path, pages.join('\n\n'), pages: pages);
  }

  Future<VsDocument> _xlsx(File file, String title) async {
    final sheets = readXlsx(await file.readAsBytes());
    final parts = <String>[];
    for (final sheet in sheets) {
      final t = tableToText(sheet.rows, sheetName: sheets.length > 1 ? sheet.name : null);
      if (t.isNotEmpty) parts.add(t);
    }
    return _build(title, 'excel', file.path, parts.join('\n\n'), pages: parts.length > 1 ? parts : null);
  }

  Future<VsDocument> _zip(File file, String title) async {
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final txt = archive.files.where((f) => f.isFile && f.name.toLowerCase().endsWith('.txt')).toList();
    if (txt.isEmpty) throw ImportException(tr('El ZIP no contiene un chat exportado (.txt).'));
    final text = decodeText(txt.first.content as List<int>);
    final isChat = looksLikeWhatsAppChat(text);
    return _build(title, isChat ? 'whatsapp' : 'text', file.path, isChat ? formatWhatsAppChat(text) : text);
  }

  Future<VsDocument> _viaBackend(File file, String title, String type) async {
    if (!await ensureConsent()) throw ImportException(tr('Envío al servidor cancelado por el usuario.'));
    final r = await backend.extract(file);
    return _build(r.title.isEmpty ? title : r.title, type, file.path, r.pages.join('\n\n'), pages: r.pages);
  }
}
