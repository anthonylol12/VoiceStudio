import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/models.dart';
import '../services/text/speech_normalizer.dart';

int _now() => DateTime.now().millisecondsSinceEpoch;

class DocumentRepository {
  DocumentRepository(this.db);
  final Database db;

  Future<void> insert(VsDocument d) async {
    await db.transaction((txn) async {
      await txn.insert('documents', d.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('document_pages', where: 'document_id = ?', whereArgs: [d.id]);
      for (final p in d.pages) {
        await txn.insert('document_pages', {'document_id': d.id, 'number': p.number, 'text': p.text});
      }
    });
  }

  Future<List<VsDocument>> list({DocCategory? category, String? query, int? limit}) async {
    final where = <String>['deleted = 0'];
    final args = <Object?>[];
    if (category != null) {
      where.add('category = ?');
      args.add(category.name);
    }
    if (query != null && query.trim().isNotEmpty) {
      where.add('(title LIKE ? OR original_text LIKE ?)');
      args..add('%$query%')..add('%$query%');
    }
    final rows = await db.query('documents',
        where: where.join(' AND '), whereArgs: args, orderBy: 'updated_at DESC', limit: limit);
    return rows.map((r) => VsDocument.fromMap(r)).toList();
  }

  Future<VsDocument?> get(String id) async {
    final rows = await db.query('documents', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final pages = await db.query('document_pages', where: 'document_id = ?', whereArgs: [id], orderBy: 'number');
    return VsDocument.fromMap(rows.first,
        pages: pages.map((p) => DocumentPage(number: p['number'] as int, text: p['text'] as String)).toList());
  }

  Future<void> update(VsDocument d) async {
    d.updatedAt = _now();
    d.version++;
    await db.update('documents', d.toMap(), where: 'id = ?', whereArgs: [d.id]);
  }

  /// Progress is saved frequently; it does not bump the content version.
  Future<void> saveProgress(String id, int index) =>
      db.update('documents', {'progress_index': index}, where: 'id = ?', whereArgs: [id]);

  Future<void> delete(String id) => db.delete('documents', where: 'id = ?', whereArgs: [id]);

  Future<List<Bookmark>> bookmarks(String documentId) async {
    final rows = await db.query('bookmarks', where: 'document_id = ?', whereArgs: [documentId], orderBy: 'unit_index');
    return rows.map(Bookmark.fromMap).toList();
  }

  Future<void> addBookmark(Bookmark b) => db.insert('bookmarks', b.toMap());
  Future<void> deleteBookmark(int id) => db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);

  Future<List<String>> queue() async {
    final rows = await db.query('reading_queue', orderBy: 'position');
    return rows.map((r) => r['document_id'] as String).toList();
  }

  Future<void> enqueue(String documentId) async {
    final existing = await db.query('reading_queue', where: 'document_id = ?', whereArgs: [documentId]);
    if (existing.isEmpty) await db.insert('reading_queue', {'document_id': documentId});
  }

  Future<void> dequeue(String documentId) =>
      db.delete('reading_queue', where: 'document_id = ?', whereArgs: [documentId]);

  /// Latest derived text of [kind] (e.g. "translation:en"), or null.
  Future<DerivedText?> latestDerived(String documentId, String kind) async {
    final rows = await db.query('derived_texts',
        where: 'document_id = ? AND kind = ?', whereArgs: [documentId, kind], orderBy: 'created_at DESC', limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return DerivedText(
      id: r['id'] as int,
      documentId: r['document_id'] as String,
      kind: r['kind'] as String,
      content: r['content'] as String,
      engine: r['engine'] as String,
      createdAt: r['created_at'] as int,
    );
  }

  Future<void> addDerived(DerivedText t) => db.insert('derived_texts', {
        'document_id': t.documentId,
        'kind': t.kind,
        'content': t.content,
        'engine': t.engine,
        'created_at': t.createdAt,
      });
}

class RecordingRepository {
  RecordingRepository(this.db);
  final Database db;

  Future<void> insert(Recording r) => db.insert('recordings', r.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> update(Recording r) async {
    r.updatedAt = _now();
    r.version++;
    await db.update('recordings', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
  }

  Future<void> delete(String id) => db.delete('recordings', where: 'id = ?', whereArgs: [id]);

  Future<Recording?> get(String id) async {
    final list = await this.list(ids: [id]);
    return list.isEmpty ? null : list.first;
  }

  /// [sort] one of: date, name, type, language, duration.
  Future<List<Recording>> list({
    String? query,
    String? tag,
    bool favoritesOnly = false,
    String sort = 'date',
    List<String>? ids,
    int? limit,
  }) async {
    final where = <String>['r.deleted = 0'];
    final args = <Object?>[];
    if (ids != null) {
      where.add('r.id IN (${List.filled(ids.length, '?').join(',')})');
      args.addAll(ids);
    }
    if (favoritesOnly) where.add('r.favorite = 1');
    if (tag != null) {
      where.add('EXISTS (SELECT 1 FROM recording_tags rt JOIN tags t ON t.id = rt.tag_id WHERE rt.recording_id = r.id AND t.name = ?)');
      args.add(tag);
    }
    if (query != null && query.trim().isNotEmpty) {
      where.add('(r.title LIKE ? OR r.notes LIKE ? OR EXISTS (SELECT 1 FROM transcript_segments s WHERE s.recording_id = r.id AND s.text LIKE ?))');
      args..add('%$query%')..add('%$query%')..add('%$query%');
    }
    final order = switch (sort) {
      'name' => 'r.title COLLATE NOCASE ASC',
      'type' => 'r.kind ASC, r.created_at DESC',
      'language' => 'r.language ASC, r.created_at DESC',
      'duration' => 'r.duration_ms DESC',
      _ => 'r.created_at DESC',
    };
    final rows = await db.rawQuery(
      'SELECT r.*, (SELECT COUNT(*) FROM transcript_segments s WHERE s.recording_id = r.id) AS seg_count '
      'FROM recordings r WHERE ${where.join(' AND ')} ORDER BY $order${limit != null ? ' LIMIT $limit' : ''}',
      args,
    );
    final result = <Recording>[];
    for (final r in rows) {
      final id = r['id'] as String;
      result.add(Recording.fromMap(r, tags: await tagsFor(id), hasTranscript: (r['seg_count'] as int) > 0));
    }
    return result;
  }

  Future<List<String>> tagsFor(String recordingId) async {
    final rows = await db.rawQuery(
        'SELECT t.name FROM tags t JOIN recording_tags rt ON rt.tag_id = t.id WHERE rt.recording_id = ? ORDER BY t.name',
        [recordingId]);
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<List<String>> allTags() async {
    final rows = await db.query('tags', orderBy: 'name');
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<void> setTags(String recordingId, List<String> tags) async {
    await db.transaction((txn) async {
      await txn.delete('recording_tags', where: 'recording_id = ?', whereArgs: [recordingId]);
      for (final name in tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toSet()) {
        await txn.insert('tags', {'name': name}, conflictAlgorithm: ConflictAlgorithm.ignore);
        final row = await txn.query('tags', where: 'name = ?', whereArgs: [name]);
        await txn.insert('recording_tags', {'recording_id': recordingId, 'tag_id': row.first['id']},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  // ---- Transcript ----

  Future<List<TranscriptSegment>> segments(String recordingId) async {
    final rows = await db.query('transcript_segments', where: 'recording_id = ?', whereArgs: [recordingId], orderBy: 'idx');
    return rows.map(TranscriptSegment.fromMap).toList();
  }

  Future<void> replaceSegments(String recordingId, List<TranscriptSegment> segments) async {
    await db.transaction((txn) async {
      await txn.delete('transcript_segments', where: 'recording_id = ?', whereArgs: [recordingId]);
      for (var i = 0; i < segments.length; i++) {
        final s = segments[i]..index = i;
        final map = s.toMap()..remove('id');
        await txn.insert('transcript_segments', map);
      }
    });
  }

  Future<void> appendSegment(TranscriptSegment s) async {
    final map = s.toMap()..remove('id');
    await db.insert('transcript_segments', map);
  }

  Future<void> updateSegment(TranscriptSegment s) =>
      db.update('transcript_segments', s.toMap(), where: 'id = ?', whereArgs: [s.id]);

  Future<Map<String, String>> speakerNames(String recordingId) async {
    final rows = await db.query('speakers', where: 'recording_id = ?', whereArgs: [recordingId]);
    return {for (final r in rows) r['speaker_key'] as String: r['display_name'] as String};
  }

  Future<void> renameSpeaker(String recordingId, String key, String name) => db.insert(
        'speakers',
        {'recording_id': recordingId, 'speaker_key': key, 'display_name': name},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}

class PronunciationRepository {
  PronunciationRepository(this.db);
  final Database db;

  Future<List<PronunciationEntry>> all() async {
    final rows = await db.query('pronunciations', orderBy: 'term COLLATE NOCASE');
    return rows.map(PronunciationEntry.fromMap).toList();
  }

  Future<void> upsert(PronunciationEntry e) =>
      db.insert('pronunciations', e.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> delete(int id) => db.delete('pronunciations', where: 'id = ?', whereArgs: [id]);
}
