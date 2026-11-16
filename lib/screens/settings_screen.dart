import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../core/settings.dart';
import '../services/backend/backend_client.dart';
import '../services/text/language_detector.dart';
import '../services/tts/tts_engine.dart';
import '../widgets/common.dart';
import '../core/i18n.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _url = TextEditingController(text: services.settings.backendUrl);
  Map<String, EngineStatus>? _engines;
  String? _backendError;
  bool _testing = false;
  List<TtsVoice> _systemVoices = [];
  List<String> _backendVoices = [];

  AppSettings get s => services.settings;

  @override
  void initState() {
    super.initState();
    SystemTtsEngine().voices().then((v) {
      if (mounted) setState(() => _systemVoices = v);
    }).catchError((_) {});
  }

  Future<void> _test() async {
    s.backendUrl = _url.text;
    setState(() {
      _testing = true;
      _backendError = null;
    });
    try {
      await services.backend.health();
      _engines = await services.backend.engines();
      _backendVoices = await services.backend.ttsVoices().catchError((_) => <String>[]);
    } catch (e) {
      _engines = null;
      _backendError = '$e';
    }
    if (mounted) setState(() => _testing = false);
  }

  Widget _voicePicker(String lang) {
    final voices = _systemVoices.where((v) => v.locale.toLowerCase().startsWith(lang)).toList();
    final current = s.voiceFor(lang);
    return DropdownButton<String>(
      isExpanded: true,
      value: voices.any((v) => v.name == current) ? current : '',
      items: [
        DropdownMenuItem(value: '', child: Text(tr('Predeterminada del sistema'))),
        for (final v in voices) DropdownMenuItem(value: v.name, child: Text('${v.name} (${v.locale})', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => setState(() => s.setVoiceFor(lang, v ?? '')),
    );
  }

  Widget _backendVoicePicker(String lang) {
    final voices = _backendVoices.where((v) => v.toLowerCase().startsWith(lang)).toList();
    final current = s.backendVoiceFor(lang);
    return DropdownButton<String>(
      isExpanded: true,
      value: voices.contains(current) ? current : '',
      items: [
        DropdownMenuItem(value: '', child: Text(tr('Predeterminada del servidor'))),
        for (final v in voices) DropdownMenuItem(value: v, child: Text(v)),
      ],
      onChanged: (v) => setState(() => s.setBackendVoiceFor(lang, v ?? '')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
        SectionHeader(tr('Apariencia')),
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(value: ThemeMode.system, label: Text(tr('Sistema')), icon: Icon(Icons.brightness_auto)),
            ButtonSegment(value: ThemeMode.light, label: Text(tr('Claro')), icon: Icon(Icons.light_mode)),
            ButtonSegment(value: ThemeMode.dark, label: Text(tr('Oscuro')), icon: Icon(Icons.dark_mode)),
          ],
          selected: {s.themeMode},
          onSelectionChanged: (v) => s.themeMode = v.first,
        ),
        const SizedBox(height: 12),
        Text(tr('Idioma de la interfaz')),
        const SizedBox(height: 6),
        SegmentedButton<UiLanguage>(
          segments: [
            ButtonSegment(value: UiLanguage.system, label: Text(tr('Sistema')), icon: const Icon(Icons.language)),
            ButtonSegment(value: UiLanguage.es, label: Text(tr('Español'))),
            ButtonSegment(value: UiLanguage.en, label: Text(tr('Inglés'))),
          ],
          selected: {s.uiLanguage},
          onSelectionChanged: (v) => s.uiLanguage = v.first,
        ),
        SectionHeader(tr('Voz y lectura')),
        Card(
          child: Column(children: [
            RadioGroup<TtsEngineKind>(
              groupValue: s.ttsEngine,
              onChanged: (v) async {
                if (v == TtsEngineKind.backend && !await services.ensureBackendConsent()) return;
                await services.reader.stop();
                s.ttsEngine = v!;
              },
              child: Column(children: [
                RadioListTile(value: TtsEngineKind.system, title: Text(tr('Motor local del sistema')), subtitle: Text(tr('Sin conexión. Usa las voces instaladas en el dispositivo.'))),
                RadioListTile(value: TtsEngineKind.backend, title: Text(tr('Piper / proveedor en la nube (backend)')), subtitle: Text(tr('Voces neuronales. Requiere el backend en marcha.'))),
              ]),
            ),
            ListTile(title: Text(tr('Voz en español (sistema)')), subtitle: _voicePicker('es')),
            ListTile(title: Text(tr('Voz en inglés (sistema)')), subtitle: _voicePicker('en')),
            if (_backendVoices.isNotEmpty) ...[
              ListTile(title: Text(tr('Voz en español (backend)')), subtitle: _backendVoicePicker('es')),
              ListTile(title: Text(tr('Voz en inglés (backend)')), subtitle: _backendVoicePicker('en')),
            ],
            ListTile(
              title: Text(tr('Probar voz')),
              trailing: Wrap(spacing: 8, children: [
                OutlinedButton(
                  onPressed: () => services.reader.engine
                      .speak('Necesitamos 12 cables THHN de 3/4" para el panel.', lang: Lang.es, speed: s.speed, volume: s.volume, voice: s.voiceFor('es'))
                      .catchError((Object e) { if (context.mounted) showMessage(context, '$e', error: true); }),
                  child: Text(tr('Español')),
                ),
                OutlinedButton(
                  onPressed: () => services.reader.engine
                      .speak('Pull two 12 AWG wires through the EMT conduit.', lang: Lang.en, speed: s.speed, volume: s.volume, voice: s.voiceFor('en'))
                      .catchError((Object e) { if (context.mounted) showMessage(context, '$e', error: true); }),
                  child: Text(tr('English')),
                ),
              ]),
            ),
            SwitchListTile(
              value: s.voiceCommandsEnabled,
              onChanged: (v) => s.voiceCommandsEnabled = v,
              title: Text(tr('Comandos de voz (pulsar para hablar)')),
              subtitle: Text(tr('El micrófono solo se activa al pulsar el botón, para evitar activaciones accidentales.')),
            ),
          ]),
        ),
        SectionHeader(tr('Backend de IA (transcripción, hablantes, OCR, Piper)')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _url,
                decoration: InputDecoration(labelText: tr('URL del backend'), hintText: 'http://127.0.0.1:8765'),
                onSubmitted: (_) => _test(),
              ),
              if (!Platform.isWindows)
                Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(tr('En Android usa la IP del PC en la red local (ej. http://192.168.1.20:8765) o un servidor HTTPS.')),
                ),
              const SizedBox(height: 10),
              Row(children: [
                FilledButton.tonal(onPressed: _testing ? null : _test, child: Text(tr('Guardar y probar conexión'))),
                if (_testing) const Padding(padding: EdgeInsets.only(left: 12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              ]),
              if (_backendError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_backendError!, style: TextStyle(color: scheme.error))),
              if (_engines != null)
                for (final e in _engines!.entries)
                  ListTile(
                    dense: true,
                    leading: Icon(e.value.available ? Icons.check_circle : Icons.cancel, color: e.value.available ? Colors.green : scheme.error),
                    title: Text('${e.key}: ${e.value.name}'),
                    subtitle: Text(e.value.detail),
                  ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.diarizeByDefault,
                onChanged: (v) => s.diarizeByDefault = v,
                title: Text(tr('Separar hablantes al transcribir')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.backendConsent,
                onChanged: (v) => s.backendConsent = v,
                title: Text(tr('Permitir enviar audio y documentos al backend')),
                subtitle: Text(tr('Si lo desactivas, se pedirá confirmación cada vez.')),
              ),
            ]),
          ),
        ),
        SectionHeader(tr('Datos')),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(tr('Ubicación de los datos locales')),
              subtitle: SelectableText(services.dataDir.path),
            ),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
              title: Text(tr('Eliminar todos los datos locales')),
              subtitle: Text(tr('Documentos, grabaciones, transcripciones y marcadores de este dispositivo.')),
              onTap: () async {
                if (!await confirm(context, tr('Eliminar todos los datos locales'),
                    tr('Se borrarán permanentemente todos los documentos, grabaciones y transcripciones de este dispositivo. No se puede deshacer.'))) {
                  return;
                }
                await services.reader.stop();
                services.reader
                  ..document = null
                  ..units = [];
                final db = services.database.db;
                for (final t in ['documents', 'recordings', 'tags', 'reading_queue', 'sync_state']) {
                  await db.delete(t);
                }
                if (await services.recordingsDir.exists()) await services.recordingsDir.delete(recursive: true);
                services.refresh();
                if (context.mounted) showMessage(context, tr('Datos locales eliminados.'));
              },
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Center(child: Text(tr('Voice Studio 0.1.0'), style: TextStyle(color: scheme.outline))),
      ]),
    );
  }
}
