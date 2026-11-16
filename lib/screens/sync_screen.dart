import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../widgets/common.dart';
import 'shell.dart';
import '../core/i18n.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  Map<String, dynamic>? _me;
  bool _checking = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _refreshAccount();
  }

  Future<void> _refreshAccount() async {
    setState(() => _checking = true);
    try {
      _me = await services.backend.isLoggedIn ? await services.backend.me() : null;
      _status = null;
    } catch (e) {
      _me = null;
      _status = '$e';
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _login(bool register) async {
    await runWithProgress(context, register ? tr('Creando cuenta…') : tr('Iniciando sesión…'), () async {
      await services.backend.login(_email.text.trim(), _password.text, register: register);
    });
    _password.clear();
    await _refreshAccount();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: services.sync,
      builder: (context, _) => PageFrame(
        title: tr('Sincronización'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(tr('Servidor: {0}', [services.settings.backendUrl])),
              subtitle: Text(tr('Se cambia en Configuración. Usa HTTPS para servidores remotos.')),
              trailing: TextButton(onPressed: () => appSection.value = Section.settings, child: Text(tr('Cambiar'))),
            ),
          ),
          if (_checking)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (_me == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(tr('Cuenta en la nube'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(tr('La sincronización es opcional. Sin cuenta, todo funciona en local.')),
                  if (_status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_status!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: 12),
                  TextField(controller: _email, decoration: InputDecoration(labelText: tr('Correo electrónico')), keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 10),
                  TextField(controller: _password, decoration: InputDecoration(labelText: tr('Contraseña (mín. 10 caracteres)')), obscureText: true),
                  const SizedBox(height: 12),
                  Wrap(spacing: 12, children: [
                    FilledButton(onPressed: () => _login(false), child: Text(tr('Iniciar sesión'))),
                    OutlinedButton(onPressed: () => _login(true), child: Text(tr('Crear cuenta'))),
                  ]),
                ]),
              ),
            )
          else ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(tr('Sesión iniciada: {0}', [_me!['email']])),
                subtitle: Text(services.settings.lastSyncAt == 0
                    ? tr('Aún no sincronizado')
                    : tr('Última sincronización: {0}', [DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(services.settings.lastSyncAt))])),
                trailing: TextButton(
                  onPressed: () async {
                    await services.backend.logout();
                    await _refreshAccount();
                  },
                  child: Text(tr('Cerrar sesión')),
                ),
              ),
            ),
            SwitchListTile(
              value: services.settings.syncAudio,
              onChanged: (v) async {
                if (v && !await services.ensureBackendConsent()) return;
                setState(() => services.settings.syncAudio = v);
              },
              title: Text(tr('Subir también los archivos de audio')),
              subtitle: Text(tr('Solo de las grabaciones marcadas para sincronizar. Subida reanudable por bloques.')),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: services.sync.running
                  ? null
                  : () async {
                      final r = await services.sync.syncNow();
                      services.refresh();
                      if (context.mounted) showMessage(context, r.toString(), error: r.errors.isNotEmpty);
                    },
              icon: services.sync.running
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
              label: Text(tr('Sincronizar ahora')),
            ),
            if (services.sync.lastReport != null)
              Padding(padding: const EdgeInsets.all(8), child: Text(services.sync.lastReport.toString())),
          ],
          SectionHeader(tr('Elementos marcados para sincronizar')),
          Text(tr('Solo se envía lo que marques. Cambia la marca desde el menú de cada documento o grabación.')),
          ValueListenableBuilder<int>(
            valueListenable: services.dataVersion,
            builder: (context, _, _) => FutureBuilder(
              future: Future.wait([services.documents.list(), services.recordings.list()]),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                final docs = (snap.data![0] as List<VsDocument>);
                final recs = (snap.data![1] as List<Recording>);
                return Card(
                  child: Column(children: [
                    for (final d in docs)
                      SwitchListTile(
                        secondary: const Icon(Icons.description_outlined),
                        title: Text(d.title),
                        value: d.syncEnabled,
                        onChanged: (v) async {
                          d.syncEnabled = v;
                          await services.documents.update(d);
                          services.refresh();
                        },
                      ),
                    for (final r in recs)
                      SwitchListTile(
                        secondary: const Icon(Icons.graphic_eq),
                        title: Text(r.title),
                        value: r.syncEnabled,
                        onChanged: (v) async {
                          r.syncEnabled = v;
                          await services.recordings.update(r);
                          services.refresh();
                        },
                      ),
                    if (docs.isEmpty && recs.isEmpty) ListTile(title: Text(tr('No hay elementos.'))),
                  ]),
                );
              },
            ),
          ),
          if (_me != null) ...[
            SectionHeader(tr('Privacidad')),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: () async {
                if (!await confirm(context, tr('Eliminar cuenta y datos en la nube'),
                    tr('Se eliminarán tu cuenta y todos los datos sincronizados del servidor. Los datos locales se conservan. No se puede deshacer.'))) {
                  return;
                }
                if (!context.mounted) return;
                await runWithProgress(context, tr('Eliminando datos del servidor…'), services.backend.deleteAccount);
                await _refreshAccount();
              },
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(tr('Eliminar cuenta y datos del servidor')),
            ),
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
