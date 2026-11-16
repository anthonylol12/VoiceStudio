import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../services/text/language_detector.dart';
import '../services/translation/translation_service.dart';
import '../widgets/common.dart';
import 'shell.dart';
import '../core/i18n.dart';

/// Shows an offline translation next to the original. The translation is
/// stored separately (derived_texts) and never replaces the original text.
class TranslationScreen extends StatefulWidget {
  const TranslationScreen({super.key, required this.document});
  final VsDocument document;
  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  TranslationService get svc => services.translation;
  late Lang _target = svc.suggestedTarget(widget.document);
  Translation? _translation;
  bool _loading = true;
  bool _onlyWarnings = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    setState(() => _loading = true);
    final saved = await services.documents.latestDerived(widget.document.id, Translation.kindFor(_target));
    if (!mounted) return;
    setState(() {
      _translation = saved == null
          ? null
          : Translation.decode(saved.content, saved.engine, DateTime.fromMillisecondsSinceEpoch(saved.createdAt));
      _loading = false;
    });
  }

  Future<void> _translate() async {
    final source = _target == Lang.es ? Lang.en : Lang.es;
    try {
      if (!await svc.engine.isReady(source, _target)) {
        if (!mounted) return;
        final ok = await confirm(
          context,
          tr('Descargar modelo de traducción'),
          tr('Para traducir sin conexión hay que descargar una vez los modelos de español e inglés (unos 30 MB por idioma, de Google). Después la traducción funciona sin Internet.'),
          action: tr('Descargar'),
        );
        if (!ok || !mounted) return;
        await runWithProgress(context, tr('Descargando modelos de traducción…'), () => svc.engine.prepare(source, _target));
        if (!await svc.engine.isReady(source, _target)) return;
      }
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
      return;
    }
    if (!mounted) return;
    final result = await runWithProgress(context, tr('Traduciendo párrafo a párrafo…'), () async {
      final t = await svc.translate(widget.document, _target);
      await services.documents.addDerived(DerivedText(
        documentId: widget.document.id,
        kind: Translation.kindFor(_target),
        content: t.encode(),
        engine: t.engine,
      ));
      return t;
    });
    if (result != null && mounted) setState(() => _translation = result);
  }

  void _listen() {
    final t = _translation!;
    final virtual = VsDocument(
      id: '${widget.document.id}::translation-${t.target.code}',
      title: tr('{0} · traducción {1}', [widget.document.title, t.target.code.toUpperCase()]),
      sourceType: 'translation',
      originalText: t.text,
      language: t.target.code,
    );
    services.reader.load(virtual, startIndex: 0);
    appSection.value = Section.player;
    Navigator.of(context).pop();
    services.reader.play();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = _translation;
    final visible = t == null ? <TranslatedParagraph>[] : t.paragraphs.where((p) => !_onlyWarnings || !p.ok).toList();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Traducción · {0}', [widget.document.title]))),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<Lang>(
              segments: [
                ButtonSegment(value: Lang.en, label: Text(tr('Al inglés'))),
                ButtonSegment(value: Lang.es, label: Text(tr('Al español'))),
              ],
              selected: {_target},
              onSelectionChanged: (v) {
                _target = v.first;
                _loadSaved();
              },
            ),
            FilledButton.icon(
              onPressed: _loading ? null : _translate,
              icon: const Icon(Icons.translate),
              label: Text(t == null ? tr('Traducir') : 'Volver a traducir'),
            ),
            if (t != null)
              FilledButton.tonalIcon(onPressed: _listen, icon: const Icon(Icons.headphones), label: Text(tr('Escuchar traducción'))),
          ]),
        ),
        if (t != null)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            color: t.warnings > 0 ? scheme.errorContainer : scheme.secondaryContainer,
            child: ListTile(
              leading: Icon(t.warnings > 0 ? Icons.warning_amber : Icons.info_outline),
              title: Text(t.warnings > 0
                  ? tr('{0} párrafo(s) con números o términos técnicos distintos al original. Compruébalos antes de actuar.', [t.warnings])
                  : tr('Traducción automática. El documento original no se ha modificado.')),
              subtitle: Text('${t.engine} · ${DateFormat('dd/MM/yyyy HH:mm').format(t.createdAt)}'),
              trailing: t.warnings > 0
                  ? FilterChip(label: Text(tr('Solo avisos')), selected: _onlyWarnings, onSelected: (v) => setState(() => _onlyWarnings = v))
                  : null,
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : t == null
                  ? EmptyState(
                      icon: Icons.translate,
                      title: tr('Sin traducción'),
                      message: tr('Se traduce párrafo a párrafo y se guarda aparte; el original no cambia. En Windows usa el backend (Argos); en Android, ML Kit en el dispositivo.'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                      itemCount: visible.length,
                      itemBuilder: (_, i) {
                        final p = visible[i];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(child: Text(p.translation, style: const TextStyle(fontSize: 18))),
                                if (!p.ok)
                                  Tooltip(
                                    message: [
                                      if (!p.numbersMatch) tr('Números distintos: {0} → {1}', [numberTokens(p.original).join(' '), numberTokens(p.translation).join(' ')]),
                                      if (p.lostTerms.isNotEmpty) tr('Términos perdidos: {0}', [p.lostTerms.join(', ')]),
                                    ].join('\n'),
                                    child: Icon(Icons.warning_amber, color: scheme.error),
                                  ),
                              ]),
                              const SizedBox(height: 8),
                              Text(tr('Original: {0}', [p.original]), style: TextStyle(color: scheme.outline)),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
