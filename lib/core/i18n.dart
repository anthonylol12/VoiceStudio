/// Minimal UI localisation (Spanish source strings, English translations).
///
/// The Spanish text itself is the key, which keeps the code readable and
/// makes Spanish the guaranteed fallback. Arguments use {0}, {1}…:
///   tr('Importados: {0}', [count])
library;

import 'dart:ui' as ui;

import 'i18n_en.dart';

enum UiLanguage { system, es, en }

class I18n {
  static UiLanguage setting = UiLanguage.system;

  /// Effective language code ("es" or "en").
  static String get code {
    switch (setting) {
      case UiLanguage.es:
        return 'es';
      case UiLanguage.en:
        return 'en';
      case UiLanguage.system:
        final sys = ui.PlatformDispatcher.instance.locale.languageCode;
        return sys == 'es' ? 'es' : (sys == 'en' ? 'en' : 'es');
    }
  }
}

String tr(String es, [List<Object?> args = const []]) {
  var s = I18n.code == 'en' ? (enStrings[es] ?? es) : es;
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}
