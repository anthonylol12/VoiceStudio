/// Domain models persisted in SQLite. Identifiers are UUID v4 strings so
/// records can be synchronised with the cloud without collisions.
library;

int _now() => DateTime.now().millisecondsSinceEpoch;

enum DocCategory { document, order }

enum OrderStatus { pending, inProgress, done }

class DocumentPage {
  const DocumentPage({required this.number, required this.text});
  final int number;
  final String text;
}

class VsDocument {
  VsDocument({
    required this.id,
    required this.title,
    required this.sourceType,
    this.sourcePath,
    required this.originalText,
    this.pages = const [],
    this.language,
    this.category = DocCategory.document,
    this.orderStatus = OrderStatus.pending,
    this.progressIndex = 0,
    this.favorite = false,
    this.syncEnabled = false,
    int? createdAt,
    int? updatedAt,
    this.version = 1,
  })  : createdAt = createdAt ?? _now(),
        updatedAt = updatedAt ?? _now();

  final String id;
  String title;
  final String sourceType; // pdf, image, excel, csv, email, whatsapp, web, text
  final String? sourcePath;
  final String originalText;
  final List<DocumentPage> pages;
  String? language;
  DocCategory category;
  OrderStatus orderStatus;
  int progressIndex;
  bool favorite;
  bool syncEnabled;
  final int createdAt;
  int updatedAt;
  int version;

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'source_type': sourceType,
        'source_path': sourcePath,
        'original_text': originalText,
        'language': language,
        'category': category.name,
        'order_status': orderStatus.name,
        'progress_index': progressIndex,
        'favorite': favorite ? 1 : 0,
        'sync_enabled': syncEnabled ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'version': version,
      };

  factory VsDocument.fromMap(Map<String, Object?> m,
          {List<DocumentPage> pages = const []}) =>
      VsDocument(
        id: m['id'] as String,
        title: m['title'] as String,
        sourceType: m['source_type'] as String,
        sourcePath: m['source_path'] as String?,
        originalText: m['original_text'] as String,
        pages: pages,
        language: m['language'] as String?,
        category: DocCategory.values.byName(m['category'] as String),
        orderStatus: OrderStatus.values.byName(m['order_status'] as String),
        progressIndex: m['progress_index'] as int? ?? 0,
        favorite: (m['favorite'] as int? ?? 0) == 1,
        syncEnabled: (m['sync_enabled'] as int? ?? 0) == 1,
        createdAt: m['created_at'] as int?,
        updatedAt: m['updated_at'] as int?,
        version: m['version'] as int? ?? 1,
      );
}

class Bookmark {
  Bookmark({this.id, required this.documentId, required this.unitIndex, required this.label, int? createdAt})
      : createdAt = createdAt ?? _now();
  final int? id;
  final String documentId;
  final int unitIndex;
  final String label;
  final int createdAt;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'document_id': documentId,
        'unit_index': unitIndex,
        'label': label,
        'created_at': createdAt,
      };
  factory Bookmark.fromMap(Map<String, Object?> m) => Bookmark(
        id: m['id'] as int?,
        documentId: m['document_id'] as String,
        unitIndex: m['unit_index'] as int,
        label: m['label'] as String,
        createdAt: m['created_at'] as int?,
      );
}

/// Content derived from a document (translation, summary). Always stored
/// separately so the original instructions are never silently modified.
class DerivedText {
  DerivedText({this.id, required this.documentId, required this.kind, required this.content, required this.engine, int? createdAt})
      : createdAt = createdAt ?? _now();
  final int? id;
  final String documentId;
  final String kind;
  final String content;
  final String engine;
  final int createdAt;
}

enum RecordingKind { recording, imported, live }

class Recording {
  Recording({
    required this.id,
    required this.title,
    this.filePath,
    this.durationMs = 0,
    this.language,
    this.notes = '',
    this.favorite = false,
    this.kind = RecordingKind.recording,
    this.syncEnabled = false,
    this.tags = const [],
    this.hasTranscript = false,
    int? createdAt,
    int? updatedAt,
    this.version = 1,
  })  : createdAt = createdAt ?? _now(),
        updatedAt = updatedAt ?? _now();

  final String id;
  String title;
  String? filePath;
  int durationMs;
  String? language;
  String notes;
  bool favorite;
  RecordingKind kind;
  bool syncEnabled;
  List<String> tags;
  bool hasTranscript;
  final int createdAt;
  int updatedAt;
  int version;

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'file_path': filePath,
        'duration_ms': durationMs,
        'language': language,
        'notes': notes,
        'favorite': favorite ? 1 : 0,
        'kind': kind.name,
        'sync_enabled': syncEnabled ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'version': version,
      };

  factory Recording.fromMap(Map<String, Object?> m, {List<String> tags = const [], bool hasTranscript = false}) => Recording(
        id: m['id'] as String,
        title: m['title'] as String,
        filePath: m['file_path'] as String?,
        durationMs: m['duration_ms'] as int? ?? 0,
        language: m['language'] as String?,
        notes: m['notes'] as String? ?? '',
        favorite: (m['favorite'] as int? ?? 0) == 1,
        kind: RecordingKind.values.byName(m['kind'] as String),
        syncEnabled: (m['sync_enabled'] as int? ?? 0) == 1,
        tags: tags,
        hasTranscript: hasTranscript,
        createdAt: m['created_at'] as int?,
        updatedAt: m['updated_at'] as int?,
        version: m['version'] as int? ?? 1,
      );
}

class TranscriptSegment {
  TranscriptSegment({
    this.id,
    required this.recordingId,
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.speaker,
    required this.text,
    this.language,
    this.edited = false,
  });

  final int? id;
  final String recordingId;
  int index;
  int startMs;
  int endMs;
  String speaker; // generic key: "S1", "S2"...
  String text;
  String? language;
  bool edited;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'recording_id': recordingId,
        'idx': index,
        'start_ms': startMs,
        'end_ms': endMs,
        'speaker': speaker,
        'text': text,
        'language': language,
        'edited': edited ? 1 : 0,
      };

  factory TranscriptSegment.fromMap(Map<String, Object?> m) => TranscriptSegment(
        id: m['id'] as int?,
        recordingId: m['recording_id'] as String,
        index: m['idx'] as int,
        startMs: m['start_ms'] as int,
        endMs: m['end_ms'] as int,
        speaker: m['speaker'] as String,
        text: m['text'] as String,
        language: m['language'] as String?,
        edited: (m['edited'] as int? ?? 0) == 1,
      );

  Map<String, Object?> toJson() => {
        'start_ms': startMs,
        'end_ms': endMs,
        'speaker': speaker,
        'text': text,
        'language': language,
      };
}

/// Generic default label for a speaker key, e.g. "S2" -> "Persona 2".
String defaultSpeakerName(String key) {
  final n = RegExp(r'\d+').firstMatch(key)?.group(0);
  return n == null ? key : 'Persona $n';
}

String formatTimestamp(int ms) {
  final d = Duration(milliseconds: ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}
