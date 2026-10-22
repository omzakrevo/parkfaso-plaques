// PARKFASO — application de gestion de parkings.
//
// Démarrage en deux temps : l'écran s'affiche immédiatement (logo + chargement),
// puis la base, l'imprimante et les services sont préparés. Une erreur à cette
// étape s'affiche en clair (avec « Réessayer ») au lieu de fermer l'application.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi, sqfliteFfiInit;

import 'app/app_controller.dart';
import 'app/login_screen.dart';
import 'app/main_shell.dart';
import 'app/parkfaso_theme.dart';
import 'app/setup_wizard.dart';
import 'core/auth.dart';
import 'core/github_sync.dart';
import 'core/licence.dart';
import 'core/park_store.dart';
import 'core/platform.dart';
import 'plaque/plate_ocr_service.dart';
import 'plaque/plate_photo_store.dart';
import 'tickets/bluetooth_printer.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('PARKFASO erreur : ${details.exceptionAsString()}');
    };
    runApp(const StartupGate());
  }, (error, stack) => debugPrint('PARKFASO erreur non gérée : $error\n$stack'));
}

class ParkfasoApp extends StatelessWidget {
  const ParkfasoApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PARKFASO',
        debugShowCheckedModeBanner: false,
        theme: buildParkTheme(),
        home: home,
        builder: (context, child) => LayoutBuilder(
          builder: (context, box) => box.maxWidth <= 720
              ? child!
              : ColoredBox(
                  color: ParkColors.navyDark,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: ClipRect(child: child),
                    ),
                  ),
                ),
        ),
      );
}

Future<AppController> initServices() async {
  final Database db;
  if (isDesktop) {
    // PC : SQLite « bureau », base dans %APPDATA% (dossier inscriptible même si
    // l'application est installée dans Program Files).
    sqfliteFfiInit();
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    db = await openParkDatabase(p.join(dir.path, 'parkfaso.db'), factory: databaseFactoryFfi);
  } else {
    db = await openParkDatabase(p.join(await getDatabasesPath(), 'parkfaso.db'));
  }
  final store = ParkStore(db);
  final photoStore = PlatePhotoStore(keepPhotos: false, retentionDays: 7);
  unawaited(photoStore.purgeExpired().catchError((_) => 0));

  final printer = BluetoothThermalPrinter();
  try {
    await printer.load().timeout(const Duration(seconds: 3));
  } catch (_) {
    // Imprimante injoignable au démarrage : on la configurera depuis l'écran.
  }

  final app = AppController(
    store: store,
    auth: AuthService(store),
    licences: LicenceService(store),
    sync: SyncService(store),
    printer: printer,
    ocr: PlateOcrService(),
    photoStore: photoStore,
  );
  await app.load();
  return app;
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key, this.init = initServices});

  final Future<AppController> Function() init;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late Future<AppController> _init = widget.init()..ignore();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppController>(
      future: _init,
      builder: (context, snap) {
        // L'état est placé AU-DESSUS de l'application : tous les écrans ouverts
        // (licence, imprimante, réglages…) y ont accès.
        if (snap.hasData) {
          return AppScope(controller: snap.data!, child: const ParkfasoApp(home: AppRoot()));
        }
        return ParkfasoApp(home: Scaffold(
          body: Container(
            decoration: const BoxDecoration(gradient: ParkColors.headerGradient),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.asset('assets/logo/parkfaso_logo.png', width: 120, height: 120),
                    ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
                    const SizedBox(height: 16),
                    const Text('PARKFASO',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800,
                            letterSpacing: 2)),
                    const SizedBox(height: 24),
                    if (snap.hasError) ...[
                      const Text('Démarrage impossible',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      SelectableText('${snap.error}',
                          textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 16),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: ParkColors.amber,
                            foregroundColor: ParkColors.navy),
                        onPressed: () {
                          // ignore() : l'erreur est affichée par le FutureBuilder.
                          final next = widget.init()..ignore();
                          setState(() {
                            _init = next;
                          });
                        },
                        child: const Text('Réessayer'),
                      ),
                    ] else
                      const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                  ]),
                ),
              ),
            ),
          ),
        ));
      },
    );
  }
}

/// Choisit l'écran : premier démarrage, connexion ou application.
class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final Widget child;
    if (app.needsSetup) {
      child = const SetupWizard(key: ValueKey('setup'));
    } else if (!app.auth.isLoggedIn) {
      child = const LoginScreen(key: ValueKey('login'));
    } else {
      child = MainShell(key: ValueKey('shell-${app.auth.user!.id}'));
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 350), child: child);
  }
}
