import 'package:material_ui/material_ui.dart';

import '../services/text/language_detector.dart';
import '../services/text/speech_normalizer.dart';
import '../widgets/common.dart';
import 'shell.dart';
import '../core/i18n.dart';

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key});
  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  late Future<List<PronunciationEntry>> _future = services.pronunciations.all();

  Future<void> _reload() async {
    await services.reloadPronunciations();
    setState(() => _future = services.pronunciations.all());
  }

  Future<void> _edit([PronunciationEntry? e]) async {
    final term = TextEditingController(text: e?.term);
    final es = TextEditingController(text: e?.spokenEs);
    final en = TextEditingController(text: e?.spokenEn);
    var cs = e?.caseSensitive ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(e == null ? tr('Nuevo término') : tr('Editar término')),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: term, decoration: InputDecoration(labelText: tr('Término tal como aparece (ej. THHN)'))),
              const SizedBox(height: 10),
              TextField(controller: es, decoration: InputDecoration(labelText: tr('Pronunciación en español'))),
              const SizedBox(height: 10),
              TextField(controller: en, decoration: InputDecoration(labelText: tr('Pronunciation in English'))),
              CheckboxListTile(
                value: cs,
                onChanged: (v) => setD(() => cs = v ?? false),
                title: Text(tr('Distinguir mayúsculas')),
                contentPadding: EdgeInsets.zero,
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => services.reader.engine.speak(es.text, lang: Lang.es, speed: 1, volume: services.settings.volume),
              child: Text(tr('Probar ES')),
            ),
            TextButton(
              onPressed: () => services.reader.engine.speak(en.text, lang: Lang.en, speed: 1, volume: services.settings.volume),
              child: Text(tr('Probar EN')),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Guardar'))),
          ],
        ),
      ),
    );
    if (ok != true || term.text.trim().isEmpty) return;
    await services.pronunciations.upsert(PronunciationEntry(
      id: e?.id,
      term: term.text.trim(),
      spokenEs: es.text.trim().isEmpty ? term.text.trim() : es.text.trim(),
      spokenEn: en.text.trim().isEmpty ? term.text.trim() : en.text.trim(),
      caseSensitive: cs,
    ));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: tr('Diccionario técnico'),
      scroll: false,
      actions: [FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: Text(tr('Añadir término')))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Define cómo deben pronunciarse siglas y términos técnicos. Solo afecta a la voz: el texto original no se modifica.')),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<List<PronunciationEntry>>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              return ListView(children: [
                for (final e in snap.data!)
                  ListTile(
                    leading: const Icon(Icons.record_voice_over_outlined),
                    title: Text(e.term),
                    subtitle: Text(tr('ES: {0}   ·   EN: {1}', [e.spokenEs, e.spokenEn])),
                    onTap: () => _edit(e),
                    trailing: IconButton(
                      tooltip: tr('Eliminar'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirm(context, tr('Eliminar término'), tr('¿Eliminar "{0}" del diccionario?', [e.term]))) {
                          await services.pronunciations.delete(e.id!);
                          await _reload();
                        }
                      },
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
