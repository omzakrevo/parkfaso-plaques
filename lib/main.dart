// PARKFASO — application gardien (entrée des véhicules, plaques, tickets
// Bluetooth, scan de sortie). Dans le projet PARKFASO complet, reprenez la
// construction de ParkHomeScreen ci-dessous dans votre propre démarrage.

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  const settings = ParkingSettings(parkingName: 'Parking Central');
  final photoStore = PlatePhotoStore(
      keepPhotos: settings.keepPlatePhotos, retentionDays: settings.platePhotoRetentionDays);
  await photoStore.purgeExpired();

  final printer = BluetoothThermalPrinter();
  await printer.load();

  runApp(ParkfasoApp(
    home: ParkHomeScreen(
      settings: settings,
      ocr: PlateOcrService(),
      repository: SqfliteSessionRepository(db, helmetPrice: settings.helmetPrice),
      printer: printer,
      photoStore: photoStore,
    ),
  ));
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
