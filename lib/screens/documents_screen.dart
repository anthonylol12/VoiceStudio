import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../readers/document_importer.dart';
import '../widgets/common.dart';
import 'shell.dart';
import '../core/i18n.dart';

bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

IconData docIcon(String type) => switch (type) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'image' => Icons.image_outlined,
      'excel' || 'csv' => Icons.table_chart_outlined,
      'email' => Icons.email_outlined,
      'whatsapp' => Icons.chat_outlined,
      'web' => Icons.language,
      _ => Icons.article_outlined,
    };

Future<void> _importFiles(BuildContext context, List<File> files) async {
  var ok = 0;
  final errors = <String>[];
  await runWithProgress(context, tr('Extrayendo texto de {0} archivo(s)…', [files.length]), () async {
    for (final f in files) {
      try {
        final doc = await services.importer.importFile(f);
        await services.documents.insert(doc);
        ok++;
      } catch (e) {
        errors.add('${f.uri.pathSegments.last}: $e');
      }
    }
  });
  services.refresh();
  if (context.mounted) {
    showMessage(context, errors.isEmpty ? tr('{0} documento(s) importado(s).', [ok]) : tr('Importados: {0}. Errores: {1}', [ok, errors.join(' | ')]),
        error: errors.isNotEmpty);
  }
}

/// Shows the import options available on the current platform.
Future<void> importDocumentsFlow(BuildContext context) async {
  final mobile = Platform.isAndroid || Platform.isIOS;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.folder_open), title: Text(tr('Archivos (PDF, imagen, Excel, CSV, texto, correo .eml, chat .txt/.zip)')), onTap: () => Navigator.pop(ctx, 'files')),
        if (_isDesktop) ListTile(leading: const Icon(Icons.drive_folder_upload), title: Text(tr('Importar carpeta')), onTap: () => Navigator.pop(ctx, 'folder')),
        if (mobile) ListTile(leading: const Icon(Icons.photo_camera), title: Text(tr('Cámara (OCR)')), onTap: () => Navigator.pop(ctx, 'camera')),
        if (mobile) ListTile(leading: const Icon(Icons.photo_library), title: Text(tr('Galería / capturas (OCR)')), onTap: () => Navigator.pop(ctx, 'gallery')),
        ListTile(leading: const Icon(Icons.link), title: Text(tr('Página web (enlace)')), onTap: () => Navigator.pop(ctx, 'url')),
        ListTile(leading: const Icon(Icons.content_paste), title: Text(tr('Pegar texto')), onTap: () => Navigator.pop(ctx, 'paste')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'files':
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: DocumentImporter.supportedExt.map((e) => e.substring(1)).toList(),
      );
      final files = picked.where((f) => f.path != null).map((f) => File(f.path!)).toList();
      if (files.isNotEmpty && context.mounted) await _importFiles(context, files);
    case 'folder':
      final dir = await FilePicker.getDirectoryPath(dialogTitle: tr('Selecciona una carpeta'));
      if (dir == null) return;
      final files = Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => DocumentImporter.isSupported(f.path))
          .toList();
      if (!context.mounted) return;
      if (files.isEmpty) {
        showMessage(context, tr('La carpeta no contiene archivos compatibles.'), error: true);
      } else {
        await _importFiles(context, files);
      }
    case 'camera':
    case 'gallery':
      final img = await ImagePicker().pickImage(source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery);
      if (img != null && context.mounted) await _importFiles(context, [File(img.path)]);
    case 'url':
      final url = await promptText(context, title: tr('Importar página web'), hint: 'https://…');
      if (url == null || url.trim().isEmpty || !context.mounted) return;
      await runWithProgress(context, tr('Descargando y extrayendo contenido…'), () async {
        await services.documents.insert(await services.importer.importUrl(url));
        services.refresh();
      });
    case 'paste':
      final text = await promptText(context, title: tr('Pegar texto'), hint: tr('Pega aquí la orden de trabajo, mensaje o texto'), maxLines: 10);
      if (text == null || text.trim().isEmpty || !context.mounted) return;
      final title = await promptText(context, title: tr('Título'), initial: tr('Texto {0}', [DateFormat('dd/MM HH:mm').format(DateTime.now())]));
      if (!context.mounted) return;
      await runWithProgress(context, tr('Guardando…'), () async {
        await services.documents.insert(await services.importer.importText(text, title: title ?? tr('Texto pegado')));
        services.refresh();
      });
  }
}

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key, this.category});
  final DocCategory? category;
  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  String _query = '';
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final list = ValueListenableBuilder<int>(
      valueListenable: services.dataVersion,
      builder: (context, _, _) => FutureBuilder<List<VsDocument>>(
        future: services.documents.list(query: _query, category: widget.category),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!;
          if (docs.isEmpty) {
            return EmptyState(
              icon: Icons.description_outlined,
              title: _query.isEmpty ? tr('No hay documentos') : tr('Sin resultados'),
              message: _isDesktop ? tr('Importa archivos o arrástralos a esta ventana.') : tr('Importa archivos o compártelos con Voice Studio.'),
              action: FilledButton.icon(onPressed: () => importDocumentsFlow(context), icon: const Icon(Icons.add), label: Text(tr('Importar'))),
            );
          }
          return ListView.builder(itemCount: docs.length, itemBuilder: (_, i) => DocumentTile(doc: docs[i]));
        },
      ),
    );
    final page = PageFrame(
      title: tr('Documentos'),
      scroll: false,
      actions: [FilledButton.icon(onPressed: () => importDocumentsFlow(context), icon: const Icon(Icons.add), label: Text(tr('Importar')))],
      child: Column(children: [
        TextField(
          decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: tr('Buscar en títulos y contenido')),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        const _QueueBar(),
        Expanded(child: list),
      ]),
    );
    if (!_isDesktop) return page;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        final files = <File>[];
        for (final x in detail.files) {
          final type = FileSystemEntity.typeSync(x.path);
          if (type == FileSystemEntityType.directory) {
            files.addAll(Directory(x.path).listSync(recursive: true).whereType<File>().where((f) => DocumentImporter.isSupported(f.path)));
          } else if (DocumentImporter.isSupported(x.path)) {
            files.add(File(x.path));
          }
        }
        if (files.isEmpty) {
          showMessage(context, tr('Ningún archivo compatible.'), error: true);
        } else {
          _importFiles(context, files);
        }
      },
      child: Stack(children: [
        page,
        if (_dragging)
          Positioned.fill(
            child: Container(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              child: Center(child: Text(tr('Suelta para importar'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600))),
            ),
          ),
      ]),
    );
  }
}

class _QueueBar extends StatelessWidget {
  const _QueueBar();
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: services.dataVersion,
      builder: (context, _, _) => FutureBuilder<List<String>>(
        future: services.documents.queue(),
        builder: (context, snap) {
          final q = snap.data ?? [];
          if (q.isEmpty) return const SizedBox.shrink();
          return Card(
            child: ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(tr('Cola de lectura: {0} documento(s)', [q.length])),
              trailing: FilledButton.tonal(
                onPressed: () async {
                  final doc = await services.documents.get(q.first);
                  if (doc == null) return;
                  await services.documents.dequeue(doc.id);
                  services.refresh();
                  services.reader.load(doc);
                  appSection.value = Section.player;
                  services.reader.play();
                },
                child: Text(tr('Reproducir siguiente')),
              ),
            ),
          );
        },
      ),
    );
  }
}

class DocumentTile extends StatelessWidget {
  const DocumentTile({super.key, required this.doc});
  final VsDocument doc;

  Future<void> _open() async {
    final full = await services.documents.get(doc.id);
    if (full == null) return;
    if (services.reader.document?.id != full.id) services.reader.load(full);
    appSection.value = Section.player;
  }

  Future<void> _menu(BuildContext context, String action) async {
    switch (action) {
      case 'queue':
        await services.documents.enqueue(doc.id);
        if (context.mounted) showMessage(context, tr('Añadido a la cola de lectura.'));
      case 'order':
        doc.category = doc.category == DocCategory.order ? DocCategory.document : DocCategory.order;
        await services.documents.update(doc);
      case 'fav':
        doc.favorite = !doc.favorite;
        await services.documents.update(doc);
      case 'sync':
        doc.syncEnabled = !doc.syncEnabled;
        await services.documents.update(doc);
      case 'rename':
        final t = await promptText(context, title: tr('Cambiar nombre'), initial: doc.title);
        if (t == null || t.trim().isEmpty) return;
        doc.title = t.trim();
        await services.documents.update(doc);
      case 'delete':
        if (!await confirm(context, tr('Eliminar documento'), tr('¿Eliminar "{0}"? Se borrarán también marcadores y progreso.', [doc.title]))) return;
        await services.deleteDocument(doc);
    }
    services.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(doc.updatedAt));
    return ListTile(
      leading: Icon(docIcon(doc.sourceType)),
      title: Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([
        date,
        (doc.language ?? '?').toUpperCase(),
        if (doc.category == DocCategory.order) tr('Pedido'),
        if (doc.syncEnabled) tr('Sincroniza'),
      ].join(' · ')),
      onTap: _open,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (doc.favorite) const Icon(Icons.star, size: 20),
        PopupMenuButton<String>(
          tooltip: tr('Opciones'),
          onSelected: (a) => _menu(context, a),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'queue', child: Text(tr('Añadir a la cola'))),
            PopupMenuItem(value: 'order', child: Text(doc.category == DocCategory.order ? tr('Quitar de pedidos') : tr('Marcar como pedido'))),
            PopupMenuItem(value: 'fav', child: Text(doc.favorite ? tr('Quitar de favoritos') : tr('Favorito'))),
            PopupMenuItem(value: 'sync', child: Text(doc.syncEnabled ? tr('No sincronizar') : tr('Sincronizar con la nube'))),
            PopupMenuItem(value: 'rename', child: Text(tr('Cambiar nombre'))),
            PopupMenuItem(value: 'delete', child: Text(tr('Eliminar'))),
          ],
        ),
      ]),
    );
  }
}
