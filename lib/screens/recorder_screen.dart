import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../audio/recorder_controller.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'transcripts_screen.dart';
import '../core/i18n.dart';

class RecorderScreen extends StatelessWidget {
  const RecorderScreen({super.key});

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Future<void> _finish(BuildContext context) async {
    final rc = services.recorder;
    final title = await promptText(context,
        title: tr('Guardar grabación'), initial: tr('Grabación {0}', [DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())]));
    if (!context.mounted) return;
    if (title == null) return; // still paused/recording; user can continue
    final rec = await rc.finish(title: title.trim().isEmpty ? tr('Grabación') : title.trim());
    if (rec == null) return;
    await services.recordings.insert(rec);
    services.refresh();
    rc.reset();
    if (!context.mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Grabación guardada')),
        content: Text(tr('"{0}" ({1}) se guardó en la biblioteca.', [rec.title, _fmt(Duration(milliseconds: rec.durationMs))])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'close'), child: Text(tr('Cerrar'))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'open'), child: Text(tr('Abrir'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'transcribe'), child: Text(tr('Transcribir'))),
        ],
      ),
    );
    if (!context.mounted) return;
    if (action == 'open' || action == 'transcribe') {
      if (action == 'transcribe') {
        await runWithProgress(context, tr('Transcribiendo y separando hablantes…'), () => services.transcribeRecording(rec));
      }
      if (context.mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => TranscriptDetailScreen(recordingId: rec.id)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rc = services.recorder;
    return ListenableBuilder(
      listenable: rc,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final active = rc.state == RecState.recording || rc.state == RecState.paused;
        final recording = rc.state == RecState.recording;
        return PageFrame(
          title: tr('Grabar conversación'),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(children: [
                const SizedBox(height: 12),
                // Permanent status indicators
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Row(children: [
                        Icon(Icons.fiber_manual_record, color: recording ? Colors.red : scheme.outline),
                        const SizedBox(width: 8),
                        Text(switch (rc.state) {
                          RecState.recording => tr('GRABANDO'),
                          RecState.paused => tr('EN PAUSA'),
                          _ => tr('Micrófono apagado'),
                        }, style: TextStyle(fontWeight: FontWeight.w700, color: recording ? Colors.red : null)),
                        const Spacer(),
                        Icon(rc.micPermission == false ? Icons.mic_off : (active ? Icons.mic : Icons.mic_none)),
                        const SizedBox(width: 6),
                        Text(rc.micPermission == false ? tr('Sin permiso') : (active ? tr('Micrófono en uso') : tr('Inactivo'))),
                      ]),
                      const SizedBox(height: 18),
                      Text(_fmt(rc.elapsed), style: Theme.of(context).textTheme.displayMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                      const SizedBox(height: 14),
                      Row(children: [
                        Text(tr('Nivel')),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(value: rc.level, minHeight: 12),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        const Icon(Icons.sd_storage_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(active ? tr('Archivo: {0} · guardando en el dispositivo', [formatBytes(rc.fileBytes)]) : tr('Las grabaciones se guardan solo en este dispositivo.'))),
                      ]),
                    ]),
                  ),
                ),
                if (rc.error != null)
                  Padding(padding: const EdgeInsets.all(8), child: Text(rc.error!, style: TextStyle(color: scheme.error))),
                const SizedBox(height: 24),
                Wrap(alignment: WrapAlignment.center, spacing: 16, runSpacing: 16, children: [
                  if (!active)
                    SizedBox(
                      width: 220,
                      height: 72,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                        onPressed: rc.start,
                        icon: const Icon(Icons.mic, size: 30),
                        label: Text(tr('Iniciar grabación'), style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  if (active) ...[
                    SizedBox(
                      height: 64,
                      child: FilledButton.tonalIcon(
                        onPressed: recording ? rc.pause : rc.resume,
                        icon: Icon(recording ? Icons.pause : Icons.play_arrow),
                        label: Text(recording ? tr('Pausar') : 'Continuar'),
                      ),
                    ),
                    SizedBox(
                      height: 64,
                      child: FilledButton.icon(
                        onPressed: () async {
                          if (recording) await rc.pause();
                          if (context.mounted) await _finish(context);
                        },
                        icon: const Icon(Icons.stop),
                        label: Text(tr('Finalizar y guardar')),
                      ),
                    ),
                    SizedBox(
                      height: 64,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          if (await confirm(context, tr('Descartar grabación'), tr('Se eliminará el audio grabado.'), action: tr('Descartar'))) {
                            await rc.discard();
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: Text(tr('Descartar')),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 28),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.gavel_outlined),
                    title: Text(tr('Consentimiento')),
                    subtitle: Text(tr('Informa a las personas presentes y obtén su consentimiento antes de grabar, según la ley aplicable.')),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => appSection.value = Section.library,
                  icon: const Icon(Icons.library_music_outlined),
                  label: Text(tr('Ver biblioteca de grabaciones')),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Small helper reused by other screens.
String recordingKindLabel(RecordingKind k) => switch (k) {
      RecordingKind.recording => tr('Grabación'),
      RecordingKind.imported => tr('Importada'),
      RecordingKind.live => tr('En directo'),
    };
