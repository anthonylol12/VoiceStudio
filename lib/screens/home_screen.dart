import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../widgets/common.dart';
import 'documents_screen.dart';
import 'shell.dart';
import 'transcripts_screen.dart';
import '../core/i18n.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: services.dataVersion,
      builder: (context, _, _) => PageFrame(
        title: tr('Inicio'),
        child: FutureBuilder(
          future: Future.wait([
            services.documents.list(limit: 5),
            services.recordings.list(limit: 5),
            services.documents.get(services.settings.lastReadDocumentId),
          ]),
          builder: (context, snap) {
            if (!snap.hasData) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
            final docs = snap.data![0] as List<VsDocument>;
            final recs = snap.data![1] as List<Recording>;
            final last = snap.data![2] as VsDocument?;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 12, runSpacing: 12, children: [
                _QuickAction(
                  icon: Icons.mic,
                  label: tr('Grabar'),
                  color: Theme.of(context).colorScheme.errorContainer,
                  onTap: () => appSection.value = Section.recorder,
                ),
                _QuickAction(
                  icon: Icons.upload_file,
                  label: tr('Importar documento'),
                  color: Theme.of(context).colorScheme.primaryContainer,
                  onTap: () => importDocumentsFlow(context),
                ),
                _QuickAction(
                  icon: Icons.subtitles,
                  label: tr('Transcribir en directo'),
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  onTap: () => appSection.value = Section.live,
                ),
                if (last != null)
                  _QuickAction(
                    icon: Icons.play_circle,
                    label: tr('Continuar: {0}', [last.title]),
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    onTap: () {
                      if (services.reader.document?.id != last.id) services.reader.load(last);
                      appSection.value = Section.player;
                      services.reader.play();
                    },
                  ),
              ]),
              SectionHeader(tr('Estado de sincronización')),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_sync_outlined),
                  title: Text(services.settings.lastSyncAt == 0
                      ? tr('Nunca sincronizado (solo almacenamiento local)')
                      : tr('Última sincronización: {0}', [DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(services.settings.lastSyncAt))])),
                  subtitle: Text(services.sync.lastReport?.toString() ?? tr('Los datos se guardan en este dispositivo.')),
                  trailing: TextButton(onPressed: () => appSection.value = Section.sync, child: Text(tr('Abrir'))),
                ),
              ),
              SectionHeader(tr('Documentos recientes'),
                  trailing: TextButton(onPressed: () => appSection.value = Section.documents, child: Text(tr('Ver todos')))),
              if (docs.isEmpty)
                Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text(tr('Aún no hay documentos. Importa un PDF, imagen, Excel o texto.'))))
              else
                Card(child: Column(children: [for (final d in docs) DocumentTile(doc: d)])),
              SectionHeader(tr('Grabaciones recientes'),
                  trailing: TextButton(onPressed: () => appSection.value = Section.library, child: Text(tr('Ver todas')))),
              if (recs.isEmpty)
                Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text(tr('Aún no hay grabaciones.'))))
              else
                Card(child: Column(children: [for (final r in recs) RecordingTile(recording: r)])),
              const SizedBox(height: 24),
            ]);
          },
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        height: 110,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Icon(icon, size: 32),
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      );
}
