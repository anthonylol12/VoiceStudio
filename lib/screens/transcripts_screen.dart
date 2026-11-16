import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../transcription/transcript_export.dart';
import '../widgets/common.dart';
import 'recorder_screen.dart';
import '../core/i18n.dart';

const audioExtensions = ['wav', 'mp3', 'm4a', 'aac', 'flac', 'ogg'];

Future<void> importAudioFlow(BuildContext context) async {
  final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: audioExtensions);
  final files = picked.where((f) => f.path != null).map((f) => File(f.path!)).toList();
  if (files.isEmpty || !context.mounted) return;
  final transcribe = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Importar grabaciones')),
      content: Text(tr('{0} archivo(s). ¿Transcribir ahora (texto, marcas de tiempo, idioma y hablantes)?', [files.length])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Solo importar'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Importar y transcribir'))),
      ],
    ),
  );
  if (transcribe == null || !context.mounted) return;
  await runWithProgress(context, transcribe ? tr('Importando y transcribiendo… puede tardar varios minutos') : tr('Importando…'), () async {
    for (final f in files) {
      await services.importAudio(f, transcribe: transcribe);
    }
  });
}

class RecordingTile extends StatelessWidget {
  const RecordingTile({super.key, required this.recording});
  final Recording recording;

  @override
  Widget build(BuildContext context) {
    final r = recording;
    return ListTile(
      leading: Icon(r.kind == RecordingKind.live ? Icons.subtitles_outlined : Icons.graphic_eq),
      title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([
        DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(r.createdAt)),
        formatTimestamp(r.durationMs),
        recordingKindLabel(r.kind),
        if (r.language != null) r.language!.toUpperCase(),
        if (r.hasTranscript) tr('Transcrita'),
        if (r.tags.isNotEmpty) r.tags.map((t) => '#$t').join(' '),
      ].join(' · ')),
      trailing: r.favorite ? const Icon(Icons.star) : null,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TranscriptDetailScreen(recordingId: r.id))),
    );
  }
}

/// "Transcripciones": recordings that have (or can get) a transcript.
class TranscriptsScreen extends StatefulWidget {
  const TranscriptsScreen({super.key});
  @override
  State<TranscriptsScreen> createState() => _TranscriptsScreenState();
}

class _TranscriptsScreenState extends State<TranscriptsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: tr('Buscar palabras en todas las transcripciones')),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(onPressed: () => importAudioFlow(context), icon: const Icon(Icons.audio_file), label: Text(tr('Transcribir audio'))),
        ]),
      ),
      Expanded(
        child: ValueListenableBuilder<int>(
          valueListenable: services.dataVersion,
          builder: (context, _, _) => FutureBuilder<List<Recording>>(
            future: services.recordings.list(query: _query),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final withT = snap.data!.where((r) => r.hasTranscript).toList();
              final without = snap.data!.where((r) => !r.hasTranscript).toList();
              if (snap.data!.isEmpty) {
                return EmptyState(
                  icon: Icons.notes_outlined,
                  title: tr('Sin transcripciones'),
                  message: tr('Importa un audio (WAV, MP3, M4A, AAC, FLAC, OGG) o usa la transcripción en directo.'),
                );
              }
              return ListView(children: [
                for (final r in withT) RecordingTile(recording: r),
                if (without.isNotEmpty) Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(tr('Grabaciones sin transcribir'))),
                for (final r in without) RecordingTile(recording: r),
              ]);
            },
          ),
        ),
      ),
    ]);
  }
}

/// Recording detail: synchronized audio playback + editable transcript.
class TranscriptDetailScreen extends StatefulWidget {
  const TranscriptDetailScreen({super.key, required this.recordingId});
  final String recordingId;
  @override
  State<TranscriptDetailScreen> createState() => _TranscriptDetailScreenState();
}

class _TranscriptDetailScreenState extends State<TranscriptDetailScreen> {
  Recording? _rec;
  List<TranscriptSegment> _segs = [];
  Map<String, String> _names = {};
  final _player = AudioPlayer();
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  PlayerState _state = PlayerState.stopped;
  double _rate = 1.0;
  String _search = '';
  final _subs = <StreamSubscription>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_player.onPositionChanged.listen((p) => setState(() => _pos = p)))
      ..add(_player.onDurationChanged.listen((d) => setState(() => _dur = d)))
      ..add(_player.onPlayerStateChanged.listen((s) => setState(() => _state = s)));
    _load();
  }

  Future<void> _load() async {
    final rec = await services.recordings.get(widget.recordingId);
    final segs = await services.recordings.segments(widget.recordingId);
    final names = await services.recordings.speakerNames(widget.recordingId);
    if (!mounted) return;
    setState(() {
      _rec = rec;
      _segs = segs;
      _names = names;
      _loading = false;
    });
    if (rec?.filePath != null && File(rec!.filePath!).existsSync()) {
      await _player.setSource(DeviceFileSource(rec.filePath!));
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  bool get _hasAudio => _rec?.filePath != null && File(_rec!.filePath!).existsSync();

  String _speaker(String key) => _names[key] ?? defaultSpeakerName(key);

  Future<void> _seek(int ms) async {
    if (!_hasAudio) return;
    await _player.seek(Duration(milliseconds: ms));
    if (_state != PlayerState.playing) await _player.resume();
  }

  Future<void> _save(TranscriptSegment s) async {
    await services.recordings.updateSegment(s);
    await services.recordings.update(_rec!);
    services.refresh();
    setState(() {});
  }

  Future<void> _editSegment(TranscriptSegment s) async {
    final text = TextEditingController(text: s.text);
    final start = TextEditingController(text: (s.startMs / 1000).toStringAsFixed(1));
    final end = TextEditingController(text: (s.endMs / 1000).toStringAsFixed(1));
    var speaker = s.speaker;
    final speakers = {..._segs.map((e) => e.speaker), s.speaker}.toList()..sort();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Editar fragmento')),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: text, maxLines: 5, decoration: InputDecoration(labelText: tr('Texto'))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: start, decoration: InputDecoration(labelText: tr('Inicio (s)')), keyboardType: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: end, decoration: InputDecoration(labelText: tr('Fin (s)')), keyboardType: TextInputType.number)),
              ]),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: speaker,
                decoration: InputDecoration(labelText: tr('Hablante')),
                items: [
                  for (final k in speakers) DropdownMenuItem(value: k, child: Text(_speaker(k))),
                  DropdownMenuItem(value: 'S${speakers.length + 1}', child: Text(tr('Nuevo: {0}', [defaultSpeakerName('S${speakers.length + 1}')]))),
                ],
                onChanged: (v) => setD(() => speaker = v ?? speaker),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Guardar'))),
          ],
        ),
      ),
    );
    if (result != true) return;
    final st = double.tryParse(start.text.replaceAll(',', '.'));
    final en = double.tryParse(end.text.replaceAll(',', '.'));
    if (st == null || en == null || en < st) {
      if (mounted) showMessage(context, tr('Límites de tiempo no válidos.'), error: true);
      return;
    }
    s
      ..text = text.text.trim()
      ..startMs = (st * 1000).round()
      ..endMs = (en * 1000).round()
      ..speaker = speaker
      ..edited = true;
    await _save(s);
  }

  Future<void> _splitSegment(TranscriptSegment s) async {
    // Split at the current playback position (if inside) or the midpoint.
    final at = (_pos.inMilliseconds > s.startMs && _pos.inMilliseconds < s.endMs) ? _pos.inMilliseconds : (s.startMs + s.endMs) ~/ 2;
    final words = s.text.split(' ');
    final cut = ((at - s.startMs) / (s.endMs - s.startMs) * words.length).round().clamp(1, words.length - 1);
    if (words.length < 2) return;
    final second = TranscriptSegment(
      recordingId: s.recordingId,
      index: s.index + 1,
      startMs: at,
      endMs: s.endMs,
      speaker: s.speaker,
      text: words.sublist(cut).join(' '),
      language: s.language,
      edited: true,
    );
    s
      ..text = words.sublist(0, cut).join(' ')
      ..endMs = at
      ..edited = true;
    final list = [..._segs]..insert(_segs.indexOf(s) + 1, second);
    await services.recordings.replaceSegments(_rec!.id, list);
    await _load();
  }

  Future<void> _renameSpeaker(String key) async {
    final name = await promptText(context, title: tr('Nombre del hablante'), initial: _speaker(key));
    if (name == null || name.trim().isEmpty) return;
    await services.recordings.renameSpeaker(_rec!.id, key, name.trim());
    await services.recordings.update(_rec!);
    await _load();
  }

  Future<void> _export(String format) async {
    final r = _rec!;
    final (content, ext) = switch (format) {
      'srt' => (TranscriptExport.toSrt(_segs, _names), 'srt'),
      'json' => (TranscriptExport.toJson(r, _segs, _names), 'json'),
      _ => (TranscriptExport.toText(r, _segs, _names), 'txt'),
    };
    if (format == 'audio') {
      if (!_hasAudio) return;
      final f = File(r.filePath!);
      final name = '${r.title}${f.path.substring(f.path.lastIndexOf('.'))}';
      final uri = await FilePicker.saveFile(fileName: name, bytes: await f.readAsBytes(), dialogTitle: tr('Exportar audio'));
      if (uri != null && mounted) showMessage(context, tr('Audio exportado.'));
      return;
    }
    final safe = r.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final uri = await FilePicker.saveFile(
      fileName: '$safe.$ext',
      bytes: utf8.encode(content),
      mimeType: ext == 'json' ? 'application/json' : 'text/plain',
      dialogTitle: tr('Exportar transcripción'),
    );
    if (uri != null && mounted) showMessage(context, tr('Exportado.'));
  }

  Future<void> _menu(String a) async {
    final r = _rec!;
    switch (a) {
      case 'rename':
        final t = await promptText(context, title: tr('Cambiar nombre'), initial: r.title);
        if (t == null || t.trim().isEmpty) return;
        r.title = t.trim();
        await services.recordings.update(r);
      case 'notes':
        final t = await promptText(context, title: tr('Notas'), initial: r.notes, maxLines: 6);
        if (t == null) return;
        r.notes = t;
        await services.recordings.update(r);
      case 'tags':
        final all = await services.recordings.allTags();
        if (!mounted) return;
        final t = await promptText(context,
            title: tr('Etiquetas (separadas por comas)'), initial: r.tags.join(', '), hint: all.isEmpty ? tr('obra, cliente, urgente') : tr('Existentes: {0}', [all.join(', ')]));
        if (t == null) return;
        await services.recordings.setTags(r.id, t.split(','));
      case 'fav':
        r.favorite = !r.favorite;
        await services.recordings.update(r);
      case 'sync':
        r.syncEnabled = !r.syncEnabled;
        await services.recordings.update(r);
      case 'transcribe':
        if (_segs.isNotEmpty &&
            !await confirm(context, tr('Volver a transcribir'), tr('Se reemplazará la transcripción actual, incluidas las correcciones manuales.'), action: tr('Reemplazar'))) {
          return;
        }
        if (!mounted) return;
        await runWithProgress(context, tr('Transcribiendo y separando hablantes…'), () => services.transcribeRecording(r));
      case 'delete':
        if (!await confirm(context, tr('Eliminar grabación'), tr('Se eliminarán el audio, la transcripción y las notas de "{0}". No se puede deshacer.', [r.title]))) return;
        await services.deleteRecording(r);
        if (mounted) Navigator.pop(context);
        return;
      case 'txt':
      case 'srt':
      case 'json':
      case 'audio':
        await _export(a);
        return;
    }
    services.refresh();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final r = _rec;
    if (r == null) return Scaffold(appBar: AppBar(), body: EmptyState(icon: Icons.error_outline, title: tr('Grabación no encontrada')));
    final scheme = Theme.of(context).colorScheme;
    final visible = _search.isEmpty ? _segs : _segs.where((s) => s.text.toLowerCase().contains(_search.toLowerCase())).toList();
    final speakers = _segs.map((s) => s.speaker).toSet().toList()..sort();
    final posMs = _pos.inMilliseconds;
    return Scaffold(
      appBar: AppBar(
        title: Text(r.title),
        actions: [
          IconButton(tooltip: r.favorite ? tr('Quitar favorito') : tr('Favorito'), onPressed: () => _menu('fav'), icon: Icon(r.favorite ? Icons.star : Icons.star_border)),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text(tr('Cambiar nombre'))),
              PopupMenuItem(value: 'notes', child: Text(tr('Notas'))),
              PopupMenuItem(value: 'tags', child: Text(tr('Etiquetas'))),
              PopupMenuItem(value: 'sync', child: Text(r.syncEnabled ? tr('No sincronizar') : tr('Sincronizar con la nube'))),
              if (_hasAudio) PopupMenuItem(value: 'transcribe', child: Text(_segs.isEmpty ? tr('Transcribir') : 'Volver a transcribir')),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'txt', child: Text(tr('Exportar texto (.txt)'))),
              PopupMenuItem(value: 'srt', child: Text(tr('Exportar subtítulos (.srt)'))),
              PopupMenuItem(value: 'json', child: Text(tr('Exportar datos (.json)'))),
              if (_hasAudio) PopupMenuItem(value: 'audio', child: Text(tr('Exportar audio'))),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'delete', child: Text(tr('Eliminar'))),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (_hasAudio)
          Material(
            color: scheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(children: [
                IconButton.filled(
                  tooltip: _state == PlayerState.playing ? tr('Pausar') : 'Reproducir',
                  onPressed: () => _state == PlayerState.playing ? _player.pause() : _player.resume(),
                  icon: Icon(_state == PlayerState.playing ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(tooltip: tr('Detener'), onPressed: () => _player.stop(), icon: const Icon(Icons.stop)),
                Text(formatTimestamp(posMs)),
                Expanded(
                  child: Slider(
                    value: posMs.clamp(0, _dur.inMilliseconds == 0 ? 1 : _dur.inMilliseconds).toDouble(),
                    max: (_dur.inMilliseconds == 0 ? 1 : _dur.inMilliseconds).toDouble(),
                    onChanged: (v) => _player.seek(Duration(milliseconds: v.round())),
                  ),
                ),
                Text(formatTimestamp(_dur.inMilliseconds)),
                PopupMenuButton<double>(
                  tooltip: tr('Velocidad'),
                  initialValue: _rate,
                  onSelected: (v) {
                    setState(() => _rate = v);
                    _player.setPlaybackRate(v);
                  },
                  itemBuilder: (_) => [for (final v in [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]) PopupMenuItem(value: v, child: Text('${v}x'))],
                  child: Padding(padding: const EdgeInsets.all(8), child: Text('${_rate}x')),
                ),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: tr('Buscar en esta transcripción'), isDense: true),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
          ]),
        ),
        if (speakers.isNotEmpty)
          SizedBox(
            height: 52,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
              for (final k in speakers)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(avatar: const Icon(Icons.person_outline, size: 18), label: Text(_speaker(k)), onPressed: () => _renameSpeaker(k)),
                ),
            ]),
          ),
        if (r.notes.isNotEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(tr('Notas: {0}', [r.notes]), style: TextStyle(color: scheme.outline))),
        Expanded(
          child: _segs.isEmpty
              ? EmptyState(
                  icon: Icons.notes_outlined,
                  title: tr('Sin transcripción'),
                  message: _hasAudio ? tr('Pulsa "Transcribir" para convertir el audio en texto.') : tr('Esta grabación no tiene audio.'),
                  action: _hasAudio ? FilledButton(onPressed: () => _menu('transcribe'), child: Text(tr('Transcribir'))) : null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final s = visible[i];
                    final active = _hasAudio && posMs >= s.startMs && posMs < s.endMs;
                    return Card(
                      color: active ? scheme.primaryContainer : null,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _seek(s.startMs),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(
                                  '${_speaker(s.speaker)} — ${formatTimestamp(s.startMs)}${s.language != null ? ' · ${s.language!.toUpperCase()}' : ''}${s.edited ? ' · editado' : ''}',
                                  style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                _highlight(s.text, _search, scheme),
                              ]),
                            ),
                            PopupMenuButton<String>(
                              tooltip: tr('Editar'),
                              onSelected: (a) => a == 'edit' ? _editSegment(s) : _splitSegment(s),
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'edit', child: Text(tr('Corregir texto, hablante o límites'))),
                                PopupMenuItem(value: 'split', child: Text(tr('Dividir aquí (posición actual)'))),
                              ],
                            ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _highlight(String text, String q, ColorScheme scheme) {
    const style = TextStyle(fontSize: 17);
    if (q.isEmpty) return Text('"$text"', style: style);
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var i = 0;
    while (true) {
      final j = lower.indexOf(q.toLowerCase(), i);
      if (j < 0) {
        spans.add(TextSpan(text: text.substring(i)));
        break;
      }
      spans
        ..add(TextSpan(text: text.substring(i, j)))
        ..add(TextSpan(text: text.substring(j, j + q.length), style: TextStyle(backgroundColor: scheme.tertiaryContainer, fontWeight: FontWeight.w700)));
      i = j + q.length;
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
