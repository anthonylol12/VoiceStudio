import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart';

enum TtsEngineKind { system, backend }

enum LiveEngineKind { backend, system }

enum ReadLanguageMode { auto, es, en }

/// User preferences, persisted with shared_preferences.
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async {
    final s = AppSettings(await SharedPreferences.getInstance());
    I18n.setting = s.uiLanguage;
    return s;
  }

  static const speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  UiLanguage get uiLanguage => UiLanguage.values.byName(_prefs.getString('uiLanguage') ?? 'system');
  set uiLanguage(UiLanguage v) {
    I18n.setting = v;
    _set('uiLanguage', v.name);
  }

  ThemeMode get themeMode => ThemeMode.values.byName(_prefs.getString('themeMode') ?? 'system');
  set themeMode(ThemeMode v) => _set('themeMode', v.name);

  TtsEngineKind get ttsEngine => TtsEngineKind.values.byName(_prefs.getString('ttsEngine') ?? 'system');
  set ttsEngine(TtsEngineKind v) => _set('ttsEngine', v.name);

  LiveEngineKind get liveEngine => LiveEngineKind.values.byName(_prefs.getString('liveEngine') ?? 'backend');
  set liveEngine(LiveEngineKind v) => _set('liveEngine', v.name);

  ReadLanguageMode get readLanguage => ReadLanguageMode.values.byName(_prefs.getString('readLanguage') ?? 'auto');
  set readLanguage(ReadLanguageMode v) => _set('readLanguage', v.name);

  double get speed => _prefs.getDouble('speed') ?? 1.0;
  set speed(double v) => _set('speed', v);

  double get volume => _prefs.getDouble('volume') ?? 1.0;
  set volume(double v) => _set('volume', v);

  /// Voice name per language for the system engine ("" = engine default).
  String voiceFor(String lang) => _prefs.getString('voice_$lang') ?? '';
  void setVoiceFor(String lang, String voice) => _set('voice_$lang', voice);

  /// Piper/Azure voice identifiers for the backend engine.
  String backendVoiceFor(String lang) => _prefs.getString('bvoice_$lang') ?? '';
  void setBackendVoiceFor(String lang, String voice) => _set('bvoice_$lang', voice);

  String get backendUrl => _prefs.getString('backendUrl') ?? 'http://127.0.0.1:8765';
  set backendUrl(String v) => _set('backendUrl', v.trim().replaceAll(RegExp(r'/+$'), ''));

  bool get diarizeByDefault => _prefs.getBool('diarize') ?? true;
  set diarizeByDefault(bool v) => _set('diarize', v);

  /// Push-to-talk is the only activation mode offered; this toggles whether
  /// the button is shown in the player.
  bool get voiceCommandsEnabled => _prefs.getBool('voiceCommands') ?? true;
  set voiceCommandsEnabled(bool v) => _set('voiceCommands', v);

  /// Consent to send audio/documents to the configured backend.
  bool get backendConsent => _prefs.getBool('backendConsent') ?? false;
  set backendConsent(bool v) => _set('backendConsent', v);

  /// Sync settings
  bool get syncAudio => _prefs.getBool('syncAudio') ?? false;
  set syncAudio(bool v) => _set('syncAudio', v);
  int get lastSyncAt => _prefs.getInt('lastSyncAt') ?? 0;
  set lastSyncAt(int v) => _set('lastSyncAt', v);
  String get lastReadDocumentId => _prefs.getString('lastReadDoc') ?? '';
  set lastReadDocumentId(String v) => _set('lastReadDoc', v);

  void _set(String key, Object v) {
    switch (v) {
      case String s:
        _prefs.setString(key, s);
      case double d:
        _prefs.setDouble(key, d);
      case int i:
        _prefs.setInt(key, i);
      case bool b:
        _prefs.setBool(key, b);
    }
    notifyListeners();
  }
}
