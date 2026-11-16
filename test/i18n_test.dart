import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_studio/core/i18n.dart';
import 'package:voice_studio/core/i18n_en.dart';

/// Extracts the first single-quoted literal of every tr('…') call, keeping
/// Dart escapes exactly as written in the source (matches the map keys).
Set<String> trKeysInSource() {
  final keys = <String>{};
  final call = RegExp(r"\btr\('((?:[^'\\]|\\.)*)'");
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    // Ignore comments (documentation examples).
    final code = f.readAsStringSync().split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    for (final m in call.allMatches(code)) {
      keys.add(m.group(1)!);
    }
  }
  return keys;
}

/// The map literal source, to compare keys in their escaped form.
Set<String> mapKeysInSource() {
  final src = File('lib/core/i18n_en.dart').readAsStringSync();
  return RegExp(r"^\s*'((?:[^'\\]|\\.)*)':", multiLine: true).allMatches(src).map((m) => m.group(1)!).toSet();
}

void main() {
  tearDown(() => I18n.setting = UiLanguage.system);

  test('every tr() string has an English translation', () {
    final missing = trKeysInSource().difference(mapKeysInSource());
    expect(missing, isEmpty, reason: 'Add these to lib/core/i18n_en.dart');
  });

  test('English translations keep the same {n} placeholders', () {
    final ph = RegExp(r'\{\d+\}');
    for (final e in enStrings.entries) {
      final a = ph.allMatches(e.key).map((m) => m.group(0)).toSet();
      final b = ph.allMatches(e.value).map((m) => m.group(0)).toSet();
      expect(b, a, reason: e.key);
    }
  });

  test('tr() switches language and fills arguments', () {
    I18n.setting = UiLanguage.es;
    expect(tr('Importados: {0}. Errores: {1}', [3, 'x']), 'Importados: 3. Errores: x');
    I18n.setting = UiLanguage.en;
    expect(tr('Importados: {0}. Errores: {1}', [3, 'x']), 'Imported: 3. Errors: x');
    expect(tr('Texto sin traducir'), 'Texto sin traducir', reason: 'falls back to Spanish');
  });
}
