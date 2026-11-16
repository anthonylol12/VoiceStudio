import 'package:material_ui/material_ui.dart';

import '../core/app_services.dart';
import '../player/reader_controller.dart';
import '../core/i18n.dart';

AppServices get services => AppServices.instance;

void showMessage(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    duration: Duration(seconds: error ? 6 : 3),
  ));
}

/// Runs [task] showing a blocking progress dialog and reporting errors.
Future<T?> runWithProgress<T>(BuildContext context, String label, Future<T> Function() task) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(label)),
        ]),
      ),
    ),
  );
  try {
    final r = await task();
    nav.pop();
    return r;
  } catch (e) {
    nav.pop();
    if (context.mounted) showMessage(context, '$e', error: true);
    return null;
  }
}

Future<String?> promptText(BuildContext context, {required String title, String initial = '', String? hint, int maxLines = 1}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: c,
          autofocus: true,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: maxLines == 1 ? (v) => Navigator.pop(ctx, v) : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('Aceptar'))),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body, {String? action}) async {
  final label = action ?? tr('Eliminar');
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(label)),
      ],
    ),
  );
  return r == true;
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: t.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline), textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
          ?trailing,
        ]),
      );
}

/// Persistent mini player shown at the bottom while a document is loaded.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final r = services.reader;
    return ListenableBuilder(
      listenable: r,
      builder: (context, _) {
        if (!r.hasDocument) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Material(
          color: scheme.surfaceContainerHigh,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                Icon(Icons.record_voice_over, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(r.document!.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(r.current?.unit.text ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
                IconButton(tooltip: tr('Anterior'), onPressed: r.previous, icon: const Icon(Icons.skip_previous)),
                IconButton.filled(
                  tooltip: r.state == PlayerState.playing ? tr('Pausar') : 'Reproducir',
                  onPressed: r.togglePlay,
                  icon: Icon(r.state == PlayerState.playing ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(tooltip: tr('Siguiente'), onPressed: r.next, icon: const Icon(Icons.skip_next)),
              ]),
            ),
          ),
        );
      },
    );
  }
}
