// PARKFASO — application gardien (entrée des véhicules, plaques, tickets
// Bluetooth, scan de sortie).
//
// Démarrage en deux temps : l'écran s'affiche immédiatement (logo + chargement),
// puis la base, l'imprimante et les photos sont préparées. Une erreur à cette
// étape s'affiche en clair (avec « Réessayer ») au lieu de fermer l'application.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app/home_screen.dart';
import 'app/parkfaso_theme.dart';
import 'plaque/plate_database.dart';
import 'plaque/plate_models.dart';
import 'plaque/plate_ocr_service.dart';
import 'plaque/plate_photo_store.dart';
import 'tickets/bluetooth_printer.dart';

const kSettings = ParkingSettings(parkingName: 'Parking Central');

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('PARKFASO erreur : ${details.exceptionAsString()}');
    };
    runApp(const ParkfasoApp(home: StartupGate()));
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
      );
}

/// Services prêts après le démarrage.
class AppServices {
  AppServices(this.repository, this.printer, this.photoStore, this.ocr);
  final SessionRepository repository;
  final BluetoothThermalPrinter printer;
  final PlatePhotoStore photoStore;
  final PlateOcrService ocr;
}

Future<AppServices> initServices() async {
  final db = await openDatabase(
    p.join(await getDatabasesPath(), 'parkfaso.db'),
    version: 1,
    onCreate: (db, _) => db.execute('''
      CREATE TABLE parking_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticket_number TEXT NOT NULL,
        vehicle_type TEXT NOT NULL,
        entered_at TEXT NOT NULL,
        helmet_count INTEGER NOT NULL DEFAULT 0,
        amount INTEGER NOT NULL DEFAULT 0
      )'''),
  );
  await const PlateColumnsMigration().apply(db);

  final photoStore = PlatePhotoStore(
      keepPhotos: kSettings.keepPlatePhotos, retentionDays: kSettings.platePhotoRetentionDays);
  // Nettoyage des photos : jamais bloquant.
  unawaited(photoStore.purgeExpired().catchError((_) => 0));

  final printer = BluetoothThermalPrinter();
  try {
    await printer.load().timeout(const Duration(seconds: 3));
  } catch (_) {
    // Imprimante injoignable au démarrage : on la configurera depuis l'écran.
  }

  return AppServices(
    SqfliteSessionRepository(db, helmetPrice: kSettings.helmetPrice),
    printer,
    photoStore,
    PlateOcrService(),
  );
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late Future<AppServices> _init = initServices()..ignore();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppServices>(
      future: _init,
      builder: (context, snap) {
        if (snap.hasData) {
          final s = snap.data!;
          return ParkHomeScreen(
            settings: kSettings,
            ocr: s.ocr,
            repository: s.repository,
            printer: s.printer,
            photoStore: s.photoStore,
          );
        }
        return Scaffold(
          backgroundColor: ParkColors.navy,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Image.asset('assets/logo/parkfaso_logo.png', width: 120, height: 120),
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
                        // ignore() : l'erreur est affichée par le FutureBuilder,
                        // elle ne doit pas remonter comme erreur non gérée.
                        final next = initServices()..ignore();
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
        );
      },
    );
  }
}
