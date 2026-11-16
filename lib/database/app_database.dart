import 'dart:io';

import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../services/text/speech_normalizer.dart';

/// Owns the SQLite connection and schema migrations.
///
/// Mobile uses the native sqflite plugin; Windows/Linux/macOS and unit tests
/// use the FFI implementation.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;
  static const schemaVersion = 1;

  static Future<AppDatabase> open(String path, {DatabaseFactory? factory}) async {
    final f = factory ?? _defaultFactory();
    final db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async => _migrate(db, 0, version),
        onUpgrade: (db, from, to) async => _migrate(db, from, to),
      ),
    );
    return AppDatabase._(db);
  }

  static DatabaseFactory _defaultFactory() {
    if (Platform.isAndroid || Platform.isIOS) return mobile.databaseFactory;
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    if (from < 1) {
      final batch = db.batch();
      batch.execute('''
        CREATE TABLE documents(
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          source_type TEXT NOT NULL,
          source_path TEXT,
          original_text TEXT NOT NULL,
          language TEXT,
          category TEXT NOT NULL DEFAULT 'document',
          order_status TEXT NOT NULL DEFAULT 'pending',
          progress_index INTEGER NOT NULL DEFAULT 0,
          favorite INTEGER NOT NULL DEFAULT 0,
          sync_enabled INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          version INTEGER NOT NULL DEFAULT 1,
          deleted INTEGER NOT NULL DEFAULT 0
        )''');
      batch.execute('''
        CREATE TABLE document_pages(
          document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
          number INTEGER NOT NULL,
          text TEXT NOT NULL,
          PRIMARY KEY(document_id, number)
        )''');
      batch.execute('''
        CREATE TABLE bookmarks(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
          unit_index INTEGER NOT NULL,
          label TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )''');
      batch.execute('''
        CREATE TABLE derived_texts(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
          kind TEXT NOT NULL,
          content TEXT NOT NULL,
          engine TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )''');
      batch.execute('''
        CREATE TABLE reading_queue(
          position INTEGER PRIMARY KEY AUTOINCREMENT,
          document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE
        )''');
      batch.execute('''
        CREATE TABLE recordings(
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          file_path TEXT,
          duration_ms INTEGER NOT NULL DEFAULT 0,
          language TEXT,
          notes TEXT NOT NULL DEFAULT '',
          favorite INTEGER NOT NULL DEFAULT 0,
          kind TEXT NOT NULL,
          sync_enabled INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          version INTEGER NOT NULL DEFAULT 1,
          deleted INTEGER NOT NULL DEFAULT 0
        )''');
      batch.execute('''
        CREATE TABLE tags(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE COLLATE NOCASE
        )''');
      batch.execute('''
        CREATE TABLE recording_tags(
          recording_id TEXT NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
          tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
          PRIMARY KEY(recording_id, tag_id)
        )''');
      batch.execute('''
        CREATE TABLE transcript_segments(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          recording_id TEXT NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
          idx INTEGER NOT NULL,
          start_ms INTEGER NOT NULL,
          end_ms INTEGER NOT NULL,
          speaker TEXT NOT NULL,
          text TEXT NOT NULL,
          language TEXT,
          edited INTEGER NOT NULL DEFAULT 0
        )''');
      batch.execute('CREATE INDEX idx_segments_recording ON transcript_segments(recording_id, idx)');
      batch.execute('''
        CREATE TABLE speakers(
          recording_id TEXT NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
          speaker_key TEXT NOT NULL,
          display_name TEXT NOT NULL,
          PRIMARY KEY(recording_id, speaker_key)
        )''');
      batch.execute('''
        CREATE TABLE pronunciations(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          term TEXT NOT NULL UNIQUE,
          spoken_es TEXT NOT NULL,
          spoken_en TEXT NOT NULL,
          case_sensitive INTEGER NOT NULL DEFAULT 0
        )''');
      batch.execute('''
        CREATE TABLE sync_state(
          entity TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          remote_version INTEGER NOT NULL DEFAULT 0,
          synced_at INTEGER,
          conflict INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY(entity, entity_id)
        )''');
      for (final p in defaultPronunciations) {
        batch.insert('pronunciations', p.toMap());
      }
      await batch.commit(noResult: true);
    }
  }

  Future<void> close() => db.close();
}
