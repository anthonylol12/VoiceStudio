import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../widgets/common.dart';
import 'dictionary_screen.dart';
import 'documents_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'live_transcription_screen.dart';
import 'orders_screen.dart';
import 'player_screen.dart';
import 'recorder_screen.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';
import 'transcripts_screen.dart';
import '../core/i18n.dart';

class Destination {
  const Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

enum Section { home, orders, documents, player, recorder, live, library, transcripts, dictionary, sync, settings }

Map<Section, Destination> get destinations => {
  Section.home: Destination(tr('Inicio'), Icons.home_outlined, Icons.home),
  Section.orders: Destination(tr('Pedidos'), Icons.assignment_outlined, Icons.assignment),
  Section.documents: Destination(tr('Documentos'), Icons.description_outlined, Icons.description),
  Section.player: Destination(tr('Reproductor'), Icons.headphones_outlined, Icons.headphones),
  Section.recorder: Destination(tr('Grabar conversación'), Icons.mic_none, Icons.mic),
  Section.live: Destination(tr('Transcripción en directo'), Icons.subtitles_outlined, Icons.subtitles),
  Section.library: Destination(tr('Biblioteca de grabaciones'), Icons.library_music_outlined, Icons.library_music),
  Section.transcripts: Destination(tr('Transcripciones'), Icons.notes_outlined, Icons.notes),
  Section.dictionary: Destination(tr('Diccionario técnico'), Icons.spellcheck_outlined, Icons.spellcheck),
  Section.sync: Destination(tr('Sincronización'), Icons.cloud_sync_outlined, Icons.cloud_sync),
  Section.settings: Destination(tr('Configuración'), Icons.settings_outlined, Icons.settings),
};

/// Global navigation entry point used by screens ("go to recorder").
final appSection = ValueNotifier<Section>(Section.home);

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  StreamSubscription? _shareSub;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      // "Share with Voice Studio" from WhatsApp, e-mail, files, browser...
      _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(_onShared);
      ReceiveSharingIntent.instance.getInitialMedia().then((files) {
        _onShared(files);
        ReceiveSharingIntent.instance.reset();
      });
    }
  }

  Future<void> _onShared(List<SharedMediaFile> files) async {
    if (files.isEmpty || !mounted) return;
    for (final f in files) {
      await runWithProgress(context, tr('Importando contenido compartido…'), () async {
        final doc = (f.type == SharedMediaType.text || f.type == SharedMediaType.url)
            ? (f.type == SharedMediaType.url || f.path.startsWith('http')
                ? await services.importer.importUrl(f.path)
                : await services.importer.importText(f.path, title: tr('Compartido'), type: 'whatsapp'))
            : await services.importer.importFile(File(f.path));
        await services.documents.insert(doc);
        services.refresh();
      });
    }
    appSection.value = Section.documents;
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  Widget _screen(Section s) => switch (s) {
        Section.home => const HomeScreen(),
        Section.orders => const OrdersScreen(),
        Section.documents => const DocumentsScreen(),
        Section.player => const PlayerScreen(),
        Section.recorder => const RecorderScreen(),
        Section.live => const LiveTranscriptionScreen(),
        Section.library => const LibraryScreen(),
        Section.transcripts => const TranscriptsScreen(),
        Section.dictionary => const DictionaryScreen(),
        Section.sync => const SyncScreen(),
        Section.settings => const SettingsScreen(),
      };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Section>(
      valueListenable: appSection,
      builder: (context, section, _) {
        final wide = MediaQuery.sizeOf(context).width >= 840;
        final body = Column(children: [
          Expanded(child: KeyedSubtree(key: ValueKey(section), child: _screen(section))),
          if (section != Section.player) MiniPlayer(onOpen: () => appSection.value = Section.player),
        ]);
        final d = destinations[section]!;
        if (wide) {
          final extended = MediaQuery.sizeOf(context).width >= 1200;
          return Scaffold(
            body: Row(children: [
              _SideBar(section: section, extended: extended),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ]),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(d.label)),
          drawer: NavigationDrawer(
            selectedIndex: section.index,
            onDestinationSelected: (i) {
              Navigator.pop(context);
              appSection.value = Section.values[i];
            },
            children: [
              const Padding(padding: EdgeInsets.fromLTRB(28, 16, 16, 10), child: _Brand()),
              for (final s in Section.values)
                NavigationDrawerDestination(
                  icon: Icon(destinations[s]!.icon),
                  selectedIcon: Icon(destinations[s]!.selectedIcon),
                  label: Text(destinations[s]!.label),
                ),
            ],
          ),
          body: body,
        );
      },
    );
  }
}

class _SideBar extends StatelessWidget {
  const _SideBar({required this.section, required this.extended});
  final Section section;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: extended ? 260 : 76,
      color: scheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
            child: extended ? const _Brand() : Icon(Icons.graphic_eq, color: scheme.primary, size: 32),
          ),
          for (final s in Section.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Tooltip(
                message: extended ? '' : destinations[s]!.label,
                child: Material(
                  color: s == section ? scheme.secondaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => appSection.value = s,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: extended ? 16 : 0, vertical: 12),
                      child: Row(
                        mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
                        children: [
                          Icon(s == section ? destinations[s]!.selectedIcon : destinations[s]!.icon,
                              color: s == section ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
                          if (extended) ...[
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(destinations[s]!.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: s == section ? FontWeight.w600 : FontWeight.w400,
                                    color: s == section ? scheme.onSecondaryContainer : scheme.onSurface,
                                  )),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.graphic_eq, color: Theme.of(context).colorScheme.primary, size: 30),
        const SizedBox(width: 10),
        Text(tr('Voice Studio'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      ]);
}

/// Standard page scaffold for wide layouts (title row + content).
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.title, required this.child, this.actions = const [], this.scroll = true});
  final String title;
  final Widget child;
  final List<Widget> actions;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 12, vertical: 8),
      child: child,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (wide || actions.isNotEmpty)
        Padding(
          padding: EdgeInsets.fromLTRB(wide ? 28 : 12, wide ? 20 : 8, wide ? 20 : 8, 4),
          child: Row(children: [
            if (wide) Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600))),
            if (!wide) const Spacer(),
            ...actions,
          ]),
        ),
      Expanded(child: scroll ? SingleChildScrollView(child: content) : content),
    ]);
  }
}
