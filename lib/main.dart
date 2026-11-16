import 'package:material_ui/material_ui.dart';

import 'core/app_services.dart';
import 'core/theme.dart';
import 'screens/shell.dart';
import 'core/i18n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Bootstrap());
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<AppServices> _init = AppServices.init();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppServices>(
      future: _init,
      builder: (context, snap) {
        if (snap.hasError) {
          return MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('No se pudo iniciar Voice Studio:\n{0}', [snap.error]), textAlign: TextAlign.center),
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return MaterialApp(
            theme: buildTheme(Brightness.light),
            home: const Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        return VoiceStudioApp(services: snap.data!);
      },
    );
  }
}

class VoiceStudioApp extends StatelessWidget {
  const VoiceStudioApp({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: services.settings,
      builder: (context, _) => MaterialApp(
        title: tr('Voice Studio'),
        debugShowCheckedModeBanner: false,
        navigatorKey: services.navigatorKey,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: services.settings.themeMode,
        // A new key per language rebuilds every screen with the new strings.
        home: AppShell(key: ValueKey('ui-${I18n.code}')),
      ),
    );
  }
}
