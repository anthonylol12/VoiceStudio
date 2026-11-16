import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'transcripts_screen.dart';
import '../core/i18n.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _query = '';
  String _sort = 'date';
  String? _tag;
  bool _favorites = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: services.dataVersion,
      builder: (context, _, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: tr('Buscar por nombre, notas o palabras de la transcripción')),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(tooltip: tr('Importar audio'), onPressed: () => importAudioFlow(context), icon: const Icon(Icons.audio_file)),
            const SizedBox(width: 6),
            IconButton.filled(tooltip: tr('Nueva grabación'), onPressed: () => appSection.value = Section.recorder, icon: const Icon(Icons.mic)),
          ]),
        ),
        FutureBuilder<List<String>>(
          future: services.recordings.allTags(),
          builder: (context, snap) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              DropdownButton<String>(
                value: _sort,
                items: [
                  DropdownMenuItem(value: 'date', child: Text(tr('Ordenar: fecha'))),
                  DropdownMenuItem(value: 'name', child: Text(tr('Ordenar: nombre'))),
                  DropdownMenuItem(value: 'type', child: Text(tr('Ordenar: tipo'))),
                  DropdownMenuItem(value: 'language', child: Text(tr('Ordenar: idioma'))),
                  DropdownMenuItem(value: 'duration', child: Text(tr('Ordenar: duración'))),
                ],
                onChanged: (v) => setState(() => _sort = v!),
              ),
              const SizedBox(width: 12),
              FilterChip(label: Text(tr('Favoritos')), selected: _favorites, onSelected: (v) => setState(() => _favorites = v)),
              for (final t in snap.data ?? const <String>[])
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: FilterChip(label: Text('#$t'), selected: _tag == t, onSelected: (v) => setState(() => _tag = v ? t : null)),
                ),
            ]),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Recording>>(
            future: services.recordings.list(query: _query, sort: _sort, tag: _tag, favoritesOnly: _favorites),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final list = snap.data!;
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.library_music_outlined,
                  title: tr('La biblioteca está vacía'),
                  message: tr('Graba una conversación o importa un archivo de audio.'),
                  action: FilledButton.icon(onPressed: () => appSection.value = Section.recorder, icon: const Icon(Icons.mic), label: Text(tr('Grabar'))),
                );
              }
              return ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => RecordingTile(recording: list[i]),
              );
            },
          ),
        ),
      ]),
    );
  }
}
