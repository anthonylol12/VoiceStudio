import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../core/i18n.dart';

class BackendException implements Exception {
  BackendException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => statusCode == null ? message : tr('{0} (HTTP {1})', [message, statusCode]);
}

class EngineStatus {
  EngineStatus(this.available, this.name, this.detail);
  final bool available;
  final String name;
  final String detail;
  factory EngineStatus.fromJson(Map<String, dynamic> j) =>
      EngineStatus(j['available'] == true, '${j['name'] ?? ''}', '${j['detail'] ?? ''}');
}

class BackendSegment {
  BackendSegment(this.startMs, this.endMs, this.text, this.language, this.speaker);
  final int startMs;
  final int endMs;
  final String text;
  final String? language;
  final String speaker;
  factory BackendSegment.fromJson(Map<String, dynamic> j) => BackendSegment(
        (j['start_ms'] as num).toInt(),
        (j['end_ms'] as num).toInt(),
        '${j['text'] ?? ''}',
        j['language'] as String?,
        '${j['speaker'] ?? 'S1'}',
      );
}

class TranscriptionResult {
  TranscriptionResult(this.language, this.durationMs, this.segments, this.diarization);
  final String? language;
  final int durationMs;
  final List<BackendSegment> segments;
  final String diarization;
}

/// REST client for the Voice Studio backend (see backend/README.md and the
/// OpenAPI document served at /docs).
class BackendClient {
  BackendClient({required this.baseUrl, http.Client? client, FlutterSecureStorage? storage})
      : _http = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  String baseUrl;
  final http.Client _http;
  final FlutterSecureStorage _storage;
  String? _token;

  static const _tokenKey = 'vs_access_token';
  static const timeout = Duration(seconds: 20);

  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('$baseUrl/api/v1$path').replace(queryParameters: q);

  /// True when the backend is on this machine (no data leaves the device).
  bool get isLocal {
    final host = Uri.tryParse(baseUrl)?.host ?? '';
    return host == '127.0.0.1' || host == 'localhost' || host == '::1';
  }

  Future<String?> token() async => _token ??= await _storage.read(key: _tokenKey);
  Future<bool> get isLoggedIn async => (await token()) != null;

  Future<Map<String, String>> _headers({bool json = false}) async {
    final t = await token();
    return {
      if (json) 'Content-Type': 'application/json',
      if (t != null) 'Authorization': 'Bearer $t',
    };
  }

  dynamic _decode(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    }
    var msg = tr('Error del servidor');
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      msg = '${j['detail'] ?? msg}';
    } catch (_) {}
    throw BackendException(msg, statusCode: r.statusCode);
  }

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on SocketException catch (e) {
      throw BackendException(tr('No se pudo conectar con el backend en {0} ({1})', [baseUrl, e.osError?.message ?? e.message]));
    } on TimeoutException {
      throw BackendException(tr('El backend no respondió a tiempo ({0})', [baseUrl]));
    } on http.ClientException catch (e) {
      throw BackendException(tr('Error de red: {0}', [e.message]));
    }
  }

  Future<Map<String, dynamic>> health() => _guard(() async =>
      _decode(await _http.get(_u('/health')).timeout(const Duration(seconds: 5))) as Map<String, dynamic>);

  Future<Map<String, EngineStatus>> engines() => _guard(() async {
        final j = _decode(await _http.get(_u('/engines')).timeout(timeout)) as Map<String, dynamic>;
        return j.map((k, v) => MapEntry(k, EngineStatus.fromJson(v as Map<String, dynamic>)));
      });

  Future<dynamic> _multipart(String path, File file, Map<String, String> fields, {Duration? t}) =>
      _guard(() async {
        final req = http.MultipartRequest('POST', _u(path))
          ..headers.addAll(await _headers())
          ..fields.addAll(fields)
          ..files.add(await http.MultipartFile.fromPath('file', file.path, filename: p.basename(file.path)));
        final streamed = await _http.send(req).timeout(t ?? const Duration(minutes: 30));
        return _decode(await http.Response.fromStream(streamed));
      });

  Future<TranscriptionResult> transcribe(File audio, {String language = 'auto', bool diarize = true}) async {
    final j = await _multipart('/transcribe', audio, {'language': language, 'diarize': '$diarize'}) as Map<String, dynamic>;
    return TranscriptionResult(
      j['language'] as String?,
      (j['duration_ms'] as num? ?? 0).toInt(),
      (j['segments'] as List).map((s) => BackendSegment.fromJson(s as Map<String, dynamic>)).toList(),
      '${j['diarization'] ?? ''}',
    );
  }

  Future<String> ocr(File image, {String language = 'auto'}) async {
    final j = await _multipart('/ocr', image, {'language': language}, t: const Duration(minutes: 5)) as Map<String, dynamic>;
    return '${j['text'] ?? ''}';
  }

  /// Server-side extraction (PyMuPDF, openpyxl/xlrd, readability).
  Future<({String title, List<String> pages})> extract(File file) async {
    final j = await _multipart('/extract', file, {}, t: const Duration(minutes: 5)) as Map<String, dynamic>;
    return (
      title: '${j['title'] ?? p.basenameWithoutExtension(file.path)}',
      pages: (j['pages'] as List).map((e) => '${(e as Map)['text']}').toList(),
    );
  }

  Future<Uint8List> tts(String text, {required String language, String voice = ''}) => _guard(() async {
        final r = await _http
            .post(_u('/tts'), headers: await _headers(json: true), body: jsonEncode({'text': text, 'language': language, 'voice': voice}))
            .timeout(const Duration(minutes: 2));
        if (r.statusCode != 200) _decode(r);
        return r.bodyBytes;
      });

  Future<List<String>> translate(List<String> texts, {required String source, required String target}) => _guard(() async {
        final r = await _http
            .post(_u('/translate'),
                headers: await _headers(json: true), body: jsonEncode({'texts': texts, 'source': source, 'target': target}))
            .timeout(const Duration(minutes: 5));
        final j = _decode(r) as Map<String, dynamic>;
        return (j['translations'] as List).map((e) => '$e').toList();
      });

  Future<List<String>> ttsVoices() => _guard(() async {
        final j = _decode(await _http.get(_u('/tts/voices')).timeout(timeout)) as Map<String, dynamic>;
        return (j['voices'] as List).map((e) => '$e').toList();
      });

  Uri liveUri({String language = 'auto'}) {
    final http = Uri.parse(baseUrl);
    return http.replace(
      scheme: http.scheme == 'https' ? 'wss' : 'ws',
      path: '${http.path}/api/v1/live',
      queryParameters: {'language': language, 'token': ?_token},
    );
  }

  // ---- Authentication ----

  Future<void> login(String email, String password, {bool register = false}) => _guard(() async {
        final r = await _http
            .post(_u(register ? '/auth/register' : '/auth/login'),
                headers: {'Content-Type': 'application/json'}, body: jsonEncode({'email': email, 'password': password}))
            .timeout(timeout);
        final j = _decode(r) as Map<String, dynamic>;
        _token = j['access_token'] as String;
        await _storage.write(key: _tokenKey, value: _token);
      });

  Future<void> logout() async {
    _token = null;
    await _storage.delete(key: _tokenKey);
  }

  Future<Map<String, dynamic>> me() => _guard(() async =>
      _decode(await _http.get(_u('/auth/me'), headers: await _headers()).timeout(timeout)) as Map<String, dynamic>);

  Future<void> deleteAccount() => _guard(() async {
        _decode(await _http.delete(_u('/account'), headers: await _headers()).timeout(timeout));
        await logout();
      });

  // ---- Sync ----

  Future<List<Map<String, dynamic>>> push(List<Map<String, dynamic>> items) => _guard(() async {
        final r = await _http
            .post(_u('/sync/push'), headers: await _headers(json: true), body: jsonEncode({'items': items}))
            .timeout(const Duration(minutes: 2));
        final j = _decode(r) as Map<String, dynamic>;
        return (j['results'] as List).cast<Map<String, dynamic>>();
      });

  Future<({List<Map<String, dynamic>> items, int cursor})> pull(int since) => _guard(() async {
        final r = await _http.get(_u('/sync/changes', {'since': '$since'}), headers: await _headers()).timeout(timeout);
        final j = _decode(r) as Map<String, dynamic>;
        return (items: (j['items'] as List).cast<Map<String, dynamic>>(), cursor: (j['cursor'] as num).toInt());
      });

  /// Resumable, chunked upload. Restarts from the offset the server reports.
  Future<String> upload(File file, {required String entityId, void Function(double)? onProgress}) => _guard(() async {
        final size = await file.length();
        final init = _decode(await _http
            .post(_u('/uploads'),
                headers: await _headers(json: true),
                body: jsonEncode({'filename': p.basename(file.path), 'size': size, 'entity_id': entityId}))
            .timeout(timeout)) as Map<String, dynamic>;
        final id = init['upload_id'] as String;
        var offset = (init['offset'] as num).toInt();
        const chunk = 1024 * 1024;
        final raf = await file.open();
        try {
          while (offset < size) {
            await raf.setPosition(offset);
            final bytes = await raf.read(chunk);
            final r = await _http
                .put(_u('/uploads/$id', {'offset': '$offset'}),
                    headers: {...await _headers(), 'Content-Type': 'application/octet-stream'}, body: bytes)
                .timeout(const Duration(minutes: 2));
            offset = ((_decode(r) as Map<String, dynamic>)['offset'] as num).toInt();
            onProgress?.call(offset / size);
          }
        } finally {
          await raf.close();
        }
        final done = _decode(await _http.post(_u('/uploads/$id/complete'), headers: await _headers()).timeout(timeout))
            as Map<String, dynamic>;
        return done['file_id'] as String;
      });
}
