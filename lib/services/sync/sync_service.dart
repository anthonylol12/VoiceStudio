import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/settings.dart';
import '../../database/repositories.dart';
import '../../models/models.dart';
import '../backend/backend_client.dart';
import '../../core/i18n.dart';

class SyncReport {
  int pushed = 0;
  int pulled = 0;
  int conflicts = 0;
  int uploads = 0;
  final List<String> errors = [];
  @override
  String toString() =>
      tr('Enviados: {0} · Recibidos: {1} · Conflictos: {2} · Audios subidos: {3}{4}', [pushed, pulled, conflicts, uploads, errors.isEmpty ? '' : '\n${tr('Errores: {0}', [errors.join('; ')])}']);
}

/// Optimistic-concurrency sync. Only items the user marked for sync are sent.
/// Each item carries the server version it was based on; the server rejects
/// stale writes with a conflict and the local copy is never overwritten
/// silently — the remote version is kept as a separate copy.
class SyncService extends ChangeNotifier {
  SyncService({required this.db, required this.client, required this.settings, required this.docs, required this.recs});

  final Database db;
  final BackendClient client;
  final AppSettings settings;
  final DocumentRepository docs;
  final RecordingRepository recs;

  bool running = false;
  SyncReport? lastReport;

  Future<int> _remoteVersion(String entity, String id) async {
    final r = await db.query('sync_state', where: 'entity = ? AND entity_id = ?', whereArgs: [entity, id]);
    return r.isEmpty ? 0 : r.first['remote_version'] as int;
  }

  Future<int?> _syncedAt(String entity, String id) async {
    final r = await db.query('sync_state', where: 'entity = ? AND entity_id = ?', whereArgs: [entity, id]);
    return r.isEmpty ? null : r.first['synced_at'] as int?;
  }

  Future<void> _setState(String entity, String id, int version, {bool conflict = false}) => db.insert(
        'sync_state',
        {'entity': entity, 'entity_id': id, 'remote_version': version, 'synced_at': DateTime.now().millisecondsSinceEpoch, 'conflict': conflict ? 1 : 0},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  /// Records a tombstone so a synced item deleted locally is deleted remotely.
  Future<void> markDeleted(String entity, String id) async {
    final v = await _remoteVersion(entity, id);
    if (v > 0) {
      await db.insert('sync_state', {'entity': 'deleted:$entity', 'entity_id': id, 'remote_version': v, 'conflict': 0},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<SyncReport> syncNow() async {
    if (running) return lastReport ?? SyncReport();
    running = true;
    notifyListeners();
    final report = SyncReport();
    try {
      if (!await client.isLoggedIn) throw BackendException(tr('Inicia sesión para sincronizar.'));
      await _push(report);
      await _pull(report);
      settings.lastSyncAt = DateTime.now().millisecondsSinceEpoch;
    } catch (e) {
      report.errors.add('$e');
    } finally {
      running = false;
      lastReport = report;
      notifyListeners();
    }
    return report;
  }

  Future<void> _push(SyncReport report) async {
    final items = <Map<String, dynamic>>[];
    for (final d in (await docs.list()).where((d) => d.syncEnabled)) {
      final full = await docs.get(d.id);
      items.add({
        'entity': 'document',
        'id': d.id,
        'base_version': await _remoteVersion('document', d.id),
        'deleted': false,
        'payload': {
          ...full!.toMap(),
          'pages': full.pages.map((p) => {'number': p.number, 'text': p.text}).toList(),
        },
      });
    }
    for (final r in (await recs.list()).where((r) => r.syncEnabled)) {
      final segs = await recs.segments(r.id);
      items.add({
        'entity': 'recording',
        'id': r.id,
        'base_version': await _remoteVersion('recording', r.id),
        'deleted': false,
        'payload': {
          ...r.toMap()..remove('file_path'),
          'tags': r.tags,
          'speakers': await recs.speakerNames(r.id),
          'segments': segs.map((s) => s.toJson()).toList(),
        },
      });
    }
    final tombstones = await db.query('sync_state', where: 'entity LIKE \'deleted:%\'');
    for (final t in tombstones) {
      items.add({
        'entity': (t['entity'] as String).substring(8),
        'id': t['entity_id'],
        'base_version': t['remote_version'],
        'deleted': true,
        'payload': <String, dynamic>{},
      });
    }
    if (items.isEmpty) return;
    final results = await client.push(items);
    for (final res in results) {
      final entity = res['entity'] as String;
      final id = res['id'] as String;
      final version = (res['server_version'] as num).toInt();
      if (res['status'] == 'ok') {
        report.pushed++;
        await _setState(entity, id, version);
        await db.delete('sync_state', where: 'entity = ? AND entity_id = ?', whereArgs: ['deleted:$entity', id]);
      } else if (res['status'] == 'conflict') {
        report.conflicts++;
        await _keepRemoteCopy(entity, res['server_payload'] as Map<String, dynamic>?);
        await _setState(entity, id, version, conflict: true);
      }
    }
    // Audio files (optional, user controlled)
    if (settings.syncAudio) {
      for (final r in (await recs.list()).where((r) => r.syncEnabled && r.filePath != null)) {
        final f = File(r.filePath!);
        if (!await f.exists()) continue;
        final uploadedAt = await _syncedAt('audio', r.id);
        if (uploadedAt != null && uploadedAt >= r.updatedAt) continue;
        try {
          await client.upload(f, entityId: r.id);
          await _setState('audio', r.id, 1);
          report.uploads++;
        } catch (e) {
          report.errors.add(tr('Audio "{0}": {1}', [r.title, e]));
        }
      }
    }
  }

  Future<void> _keepRemoteCopy(String entity, Map<String, dynamic>? payload) async {
    if (payload == null || payload.isEmpty || entity != 'document') return;
    final copy = VsDocument.fromMap({
      ...payload,
      'id': '${payload['id']}-remoto-${DateTime.now().millisecondsSinceEpoch}',
      'title': tr('{0} (versión del servidor)', [payload['title']]),
      'sync_enabled': 0,
    }, pages: _pages(payload));
    await docs.insert(copy);
  }

  List<DocumentPage> _pages(Map<String, dynamic> payload) => ((payload['pages'] as List?) ?? [])
      .map((p) => DocumentPage(number: (p['number'] as num).toInt(), text: '${p['text']}'))
      .toList();

  Future<void> _pull(SyncReport report) async {
    final since = (await db.query('sync_state', where: 'entity = \'cursor\'')).firstOrNull?['remote_version'] as int? ?? 0;
    final changes = await client.pull(since);
    for (final item in changes.items) {
      final entity = item['entity'] as String;
      final id = item['id'] as String;
      final version = (item['version'] as num).toInt();
      final local = await _remoteVersion(entity, id);
      if (version <= local) continue;
      final deleted = item['deleted'] == true;
      final payload = (item['payload'] as Map?)?.cast<String, dynamic>() ?? {};
      final syncedAt = await _syncedAt(entity, id);
      if (entity == 'document') {
        final existing = await docs.get(id);
        if (existing != null && syncedAt != null && existing.updatedAt > syncedAt) {
          report.conflicts++;
          await _keepRemoteCopy(entity, payload);
          await _setState(entity, id, version, conflict: true);
          continue;
        }
        if (deleted) {
          await docs.delete(id);
        } else {
          await docs.insert(VsDocument.fromMap({...payload, 'sync_enabled': 1}, pages: _pages(payload)));
        }
      } else if (entity == 'recording') {
        final existing = await recs.get(id);
        if (existing != null && syncedAt != null && existing.updatedAt > syncedAt) {
          report.conflicts++;
          await _setState(entity, id, version, conflict: true);
          continue;
        }
        if (deleted) {
          await recs.delete(id);
        } else {
          final rec = Recording.fromMap({...payload, 'file_path': existing?.filePath, 'sync_enabled': 1});
          await recs.insert(rec);
          await recs.setTags(id, ((payload['tags'] as List?) ?? []).map((e) => '$e').toList());
          final segs = ((payload['segments'] as List?) ?? []).asMap().entries.map((e) {
            final s = e.value as Map;
            return TranscriptSegment(
              recordingId: id,
              index: e.key,
              startMs: (s['start_ms'] as num).toInt(),
              endMs: (s['end_ms'] as num).toInt(),
              speaker: '${s['speaker']}',
              text: '${s['text']}',
              language: s['language'] as String?,
            );
          }).toList();
          await recs.replaceSegments(id, segs);
          for (final e in ((payload['speakers'] as Map?) ?? {}).entries) {
            await recs.renameSpeaker(id, '${e.key}', '${e.value}');
          }
        }
      }
      report.pulled++;
      await _setState(entity, id, version);
    }
    await db.insert('sync_state', {'entity': 'cursor', 'entity_id': '-', 'remote_version': changes.cursor},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
