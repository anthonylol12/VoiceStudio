import 'dart:io';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../core/settings.dart';
import '../models/models.dart';
import '../transcription/live_transcription_controller.dart';
import '../widgets/common.dart';
import 'transcripts_screen.dart';
import '../core/i18n.dart';

class LiveTranscriptionScreen extends StatefulWidget {
  const LiveTranscriptionScreen({super.key});
  @override
  State<LiveTranscriptionScreen> createState() => _LiveTranscriptionScreenState();
}

class _LiveTranscriptionScreenState extends State<LiveTranscriptionScreen> {
  final _scroll = ScrollController();
  LiveTranscriptionController get live => services.live;

  @override
  void initState() {
    super.initState();
    live.addListener(_autoScroll);
  }

  @override
  void dispose() {
    live.removeListener(_autoScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _start() async {
    if (live.usesBackend && !await services.ensureBackendConsent()) return;
    await live.start();
    if (mounted && live.error != null) showMessage(context, live.error!, error: true);
  }

  Future<void> _stop() async {
    final result = await live.stop(title: tr('Transcripción {0}', [DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())]));
    if (result == null) return;
    final (rec, segs) = result;
    await services.recordings.insert(rec);
    await services.recordings.replaceSegments(rec.id, segs);
    services.refresh();
    if (!mounted) return;
    showMessage(context, tr('Transcripción guardada ({0} fragmentos).', [segs.length]));
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TranscriptDetailScreen(recordingId: rec.id)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([live, services.settings]),
      builder: (context, _) {
        final running = live.isRunning;
        final mobile = Platform.isAndroid || Platform.isIOS;
        final scheme = Theme.of(context).colorScheme;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'auto', label: Text(tr('Detectar idioma'))),
                  ButtonSegment(value: 'es', label: Text(tr('Español'))),
                  ButtonSegment(value: 'en', label: Text(tr('English'))),
                ],
                selected: {live.languageMode},
                onSelectionChanged: running ? null : (v) => setState(() => live.languageMode = v.first),
              ),
              if (mobile)
                DropdownButton<LiveEngineKind>(
                  value: services.settings.liveEngine,
                  items: [
                    DropdownMenuItem(value: LiveEngineKind.backend, child: Text(tr('Whisper (backend) + audio + hablantes'))),
                    DropdownMenuItem(value: LiveEngineKind.system, child: Text(tr('Reconocedor del dispositivo (sin audio)'))),
                  ],
                  onChanged: running ? null : (v) => services.settings.liveEngine = v!,
                ),
              if (running)
                Chip(
                  avatar: const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                  label: Text(tr('EN DIRECTO · {0}', [formatTimestamp(live.elapsed.inMilliseconds)])),
                ),
              if (running && live.usesBackend)
                SizedBox(width: 120, child: LinearProgressIndicator(value: live.level, minHeight: 8)),
            ]),
          ),
          if (live.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(live.error!, style: TextStyle(color: scheme.error)),
            ),
          Expanded(
            child: live.segments.isEmpty && live.partial.isEmpty
                ? EmptyState(
                    icon: Icons.subtitles_outlined,
                    title: running ? tr('Escuchando…') : tr('Transcripción en tiempo real'),
                    message: running
                        ? tr('El texto aparecerá aquí mientras las personas hablan.')
                        : tr('Pulsa "Comenzar" para transcribir. Los hablantes se etiquetan como Persona 1, Persona 2…'),
                  )
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final s in live.segments)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${defaultSpeakerName(s.speaker)} — ${formatTimestamp(s.startMs)}${s.language != null ? ' · ${s.language!.toUpperCase()}' : ''}',
                                style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
                            Text('"${s.text}"', style: const TextStyle(fontSize: 18)),
                          ]),
                        ),
                      if (live.partial.isNotEmpty)
                        Text(live.partial, style: TextStyle(fontSize: 18, color: scheme.outline, fontStyle: FontStyle.italic)),
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: 64,
                child: running
                    ? FilledButton.icon(onPressed: live.state == LiveState.finishing ? null : _stop, icon: const Icon(Icons.stop), label: Text(tr('Detener y guardar')))
                    : live.state == LiveState.finishing
                        ? const Center(child: CircularProgressIndicator())
                        : FilledButton.icon(onPressed: _start, icon: const Icon(Icons.mic), label: Text(tr('Comenzar transcripción'))),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
