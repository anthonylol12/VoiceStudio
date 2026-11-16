import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../core/settings.dart';
import '../models/models.dart';
import '../player/reader_controller.dart';
import '../services/voice_commands/voice_command_service.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'translation_screen.dart';
import '../core/i18n.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _recognizers = <int, TapGestureRecognizer>{};
  final _paragraphKeys = <int, GlobalKey>{};
  int _lastParagraph = -1;
  late final VoiceCommandService _voice =
      VoiceCommandService(backend: services.backend, ensureConsent: services.ensureBackendConsent);
  ReaderController get r => services.reader;

  @override
  void initState() {
    super.initState();
    r.addListener(_followCurrent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _followCurrent(force: true));
  }

  @override
  void dispose() {
    r.removeListener(_followCurrent);
    for (final g in _recognizers.values) {
      g.dispose();
    }
    _voice.dispose();
    super.dispose();
  }

  void _followCurrent({bool force = false}) {
    final p = r.current?.unit.paragraph ?? -1;
    if (p == _lastParagraph && !force) return;
    _lastParagraph = p;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _paragraphKeys[p]?.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.3);
    });
  }

  TapGestureRecognizer _tap(int i) => _recognizers.putIfAbsent(
        i,
        () => TapGestureRecognizer()..onTap = () => r.play(from: i),
      );

  Future<void> _voiceCommand() async {
    final cmd = await _voice.listenOnce();
    if (!mounted) return;
    if (cmd != null) {
      showMessage(context, tr('Comando: {0}', [_voice.lastHeard]));
      await r.handleCommand(cmd);
    } else if (_voice.error != null) {
      showMessage(context, _voice.error!, error: true);
    }
  }

  Future<void> _addBookmark() async {
    final u = r.current;
    if (u == null) return;
    if (r.document!.sourceType == 'translation') {
      showMessage(context, tr('Los marcadores se guardan en el documento original, no en la traducción.'));
      return;
    }
    final label = await promptText(context, title: tr('Guardar marcador'), initial: u.unit.text.length > 60 ? '${u.unit.text.substring(0, 60)}…' : u.unit.text);
    if (label == null) return;
    await services.documents.addBookmark(Bookmark(documentId: r.document!.id, unitIndex: r.index, label: label));
    if (mounted) showMessage(context, tr('Marcador guardado.'));
  }

  Future<void> _showBookmarks() async {
    final list = r.document!.sourceType == 'translation' ? <Bookmark>[] : await services.documents.bookmarks(r.document!.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => list.isEmpty
          ? SizedBox(height: 160, child: Center(child: Text(tr('No hay marcadores en este documento.'))))
          : ListView(children: [
              for (final b in list)
                ListTile(
                  leading: const Icon(Icons.bookmark),
                  title: Text(b.label),
                  subtitle: Text(tr('Frase {0}', [b.unitIndex + 1])),
                  onTap: () {
                    Navigator.pop(ctx);
                    r.play(from: b.unitIndex);
                  },
                  trailing: IconButton(
                    tooltip: tr('Eliminar marcador'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await services.documents.deleteBookmark(b.id!);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                ),
            ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([r, _voice]),
      builder: (context, _) {
        if (!r.hasDocument) {
          return EmptyState(
            icon: Icons.headphones_outlined,
            title: tr('Nada que reproducir'),
            message: tr('Abre un documento para escucharlo en voz alta.'),
            action: FilledButton(onPressed: () => appSection.value = Section.documents, child: Text(tr('Ir a Documentos'))),
          );
        }
        final scheme = Theme.of(context).colorScheme;
        final pages = r.units.map((u) => u.unit.page).whereType<int>().toSet().toList()..sort();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(children: [
              Expanded(
                child: Text(r.document!.title,
                    style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Text('${r.index + 1} / ${r.units.length}'),
              if (pages.length > 1)
                PopupMenuButton<int>(
                  tooltip: tr('Leer página'),
                  icon: const Icon(Icons.find_in_page_outlined),
                  onSelected: r.playPage,
                  itemBuilder: (_) => [for (final p in pages) PopupMenuItem(value: p, child: Text(tr('Leer solo página {0}', [p])))],
                ),
              if (r.document!.sourceType != 'translation')
                IconButton(
                  tooltip: tr('Traducir (se guarda aparte del original)'),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TranslationScreen(document: r.document!))),
                  icon: const Icon(Icons.translate),
                ),
              IconButton(tooltip: tr('Marcadores'), onPressed: _showBookmarks, icon: const Icon(Icons.bookmarks_outlined)),
              IconButton(tooltip: tr('Guardar marcador'), onPressed: _addBookmark, icon: const Icon(Icons.bookmark_add_outlined)),
            ]),
          ),
          if (r.error != null)
            MaterialBanner(
              content: Text(r.error!),
              leading: const Icon(Icons.error_outline),
              actions: [TextButton(onPressed: () => appSection.value = Section.settings, child: Text(tr('Configurar voz')))],
            ),
          Expanded(child: _text(scheme)),
          const Divider(height: 1),
          _controls(context, scheme),
        ]);
      },
    );
  }

  Widget _text(ColorScheme scheme) {
    final byParagraph = <int, List<int>>{};
    for (var i = 0; i < r.units.length; i++) {
      byParagraph.putIfAbsent(r.units[i].unit.paragraph, () => []).add(i);
    }
    final base = Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 19, height: 1.55);
    int? lastPage;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final entry in byParagraph.entries) ...[
          if (r.units[entry.value.first].unit.page != null && r.units[entry.value.first].unit.page != lastPage)
            Builder(builder: (_) {
              lastPage = r.units[entry.value.first].unit.page;
              return Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 4),
                child: Text(tr('Página {0}', [lastPage]), style: TextStyle(color: scheme.outline, fontWeight: FontWeight.w600)),
              );
            }),
          GestureDetector(
            key: _paragraphKeys.putIfAbsent(entry.key, () => GlobalKey()),
            onLongPress: () => r.playParagraph(entry.value.first),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text.rich(TextSpan(style: base, children: [
                for (final i in entry.value)
                  TextSpan(
                    text: '${r.units[i].unit.text} ',
                    recognizer: _tap(i),
                    style: i == r.index
                        ? TextStyle(backgroundColor: scheme.primaryContainer, color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600)
                        : null,
                  ),
              ])),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(tr('Toca una frase para leer desde ahí. Mantén pulsado un párrafo para leer solo ese párrafo.'),
            style: TextStyle(color: scheme.outline)),
      ]),
    );
  }

  Widget _controls(BuildContext context, ColorScheme scheme) {
    final playing = r.state == PlayerState.playing;
    final s = services.settings;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
            IconButton(tooltip: tr('Párrafo anterior'), iconSize: 30, onPressed: r.previousParagraph, icon: const Icon(Icons.keyboard_double_arrow_up)),
            IconButton(tooltip: tr('Frase anterior'), iconSize: 36, onPressed: r.previous, icon: const Icon(Icons.skip_previous)),
            IconButton(tooltip: tr('Repetir frase'), iconSize: 36, onPressed: r.repeatSentence, icon: const Icon(Icons.replay)),
            SizedBox(
              width: 76,
              height: 76,
              child: FilledButton(
                style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
                onPressed: r.togglePlay,
                child: Icon(playing ? Icons.pause : Icons.play_arrow, size: 44),
              ),
            ),
            IconButton(tooltip: tr('Detener'), iconSize: 36, onPressed: r.stop, icon: const Icon(Icons.stop)),
            IconButton(tooltip: tr('Frase siguiente'), iconSize: 36, onPressed: r.next, icon: const Icon(Icons.skip_next)),
            IconButton(tooltip: tr('Párrafo siguiente'), iconSize: 30, onPressed: r.nextParagraph, icon: const Icon(Icons.keyboard_double_arrow_down)),
            if (s.voiceCommandsEnabled)
              IconButton.filledTonal(
                tooltip: tr('Comando de voz (pulsa y habla)'),
                iconSize: 30,
                onPressed: _voice.listening ? null : _voiceCommand,
                icon: Icon(_voice.listening ? Icons.hearing : Icons.keyboard_voice),
              ),
          ]),
          const SizedBox(height: 6),
          Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 6, children: [
            SegmentedButton<double>(
              showSelectedIcon: false,
              segments: [for (final v in AppSettings.speeds) ButtonSegment(value: v, label: Text('${v}x'))],
              selected: {s.speed},
              onSelectionChanged: (v) => r.setSpeed(v.first),
            ),
            SegmentedButton<ReadLanguageMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: ReadLanguageMode.auto, label: Text(tr('Auto'))),
                ButtonSegment(value: ReadLanguageMode.es, label: Text(tr('ES'))),
                ButtonSegment(value: ReadLanguageMode.en, label: Text(tr('EN'))),
              ],
              selected: {s.readLanguage},
              onSelectionChanged: (v) => r.setLanguageMode(v.first),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.volume_up_outlined),
              SizedBox(width: 160, child: Slider(value: s.volume, onChanged: r.setVolume)),
            ]),
            DropdownButton<TtsEngineKind>(
              value: s.ttsEngine,
              items: [
                DropdownMenuItem(value: TtsEngineKind.system, child: Text(tr('Voz local (sistema)'))),
                DropdownMenuItem(value: TtsEngineKind.backend, child: Text(tr('Voz Piper / nube (backend)'))),
              ],
              onChanged: (v) async {
                if (v == null) return;
                if (v == TtsEngineKind.backend && !await services.ensureBackendConsent()) return;
                await r.stop();
                s.ttsEngine = v;
              },
            ),
          ]),
        ]),
      ),
    );
  }
}
