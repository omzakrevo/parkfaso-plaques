import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parkfaso_plaque/plaque/plate_database.dart';
import 'package:parkfaso_plaque/plaque/plate_models.dart';
import 'package:parkfaso_plaque/plaque/plate_photo_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  Future<Database> legacyDb() async {
    final db = await factory.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(singleInstance: false));
    // Table telle qu'elle existe déjà dans PARKFASO (avant la mise à jour).
    await db.execute('''CREATE TABLE parking_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT, ticket_number TEXT, vehicle_type TEXT,
      entered_at TEXT, helmet_count INTEGER, amount INTEGER)''');
    await db.insert('parking_sessions', {
      'ticket_number': 'PK-000001', 'vehicle_type': 'VOITURE',
      'entered_at': '2026-10-01T10:00:00', 'helmet_count': 0, 'amount': 300,
    });
    return db;
  }

  group('Migration de la base', () {
    test('ajoute les colonnes plaque + sortie sans toucher aux données existantes', () async {
      final db = await legacyDb();
      final added = await const PlateColumnsMigration().apply(db);
      expect(added, kPlateColumns.keys.toList());
      final rows = await db.query('parking_sessions');
      expect(rows.single['ticket_number'], 'PK-000001');
      expect(rows.single['amount'], 300);
      expect(rows.single['plate_capture_method'], 'AUCUN');
      expect(rows.single['plate_verified'], 0);
      expect(rows.single['license_plate'], isNull);
    });

    test('idempotente : peut tourner à chaque démarrage', () async {
      final db = await legacyDb();
      await const PlateColumnsMigration().apply(db);
      expect(await const PlateColumnsMigration().apply(db), isEmpty);
    });

    test('nom de table erroné : erreur explicite', () async {
      final db = await factory.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(singleInstance: false));
      expect(() => const PlateColumnsMigration(table: 'sessions').apply(db), throwsStateError);
    });

    test('purge des textes OCR et photos temporaires', () async {
      final db = await legacyDb();
      await const PlateColumnsMigration().apply(db);
      await db.update('parking_sessions', {'plate_ocr_raw_text': 'BURKINA\n11 AB 2345', 'plate_photo_path': '/x.jpg'});
      final n = await const PlateColumnsMigration()
          .purgeTemporaryData(db, enteredAtColumn: 'entered_at', olderThan: DateTime(2026, 10, 2));
      expect(n, 1);
      final row = (await db.query('parking_sessions')).single;
      expect(row['plate_ocr_raw_text'], isNull);
      expect(row['plate_photo_path'], isNull);
    });
  });

  group('Enregistrement d\'une session moto', () {
    test('numéro, méthode et vérification enregistrés', () async {
      final db = await legacyDb();
      await const PlateColumnsMigration().apply(db);
      final repo = SqfliteSessionRepository(db);
      final base = await repo.nextTicketBase();
      expect(base, 'PK-000002');
      final id = await repo.save(ParkingSession(
        vehicleType: VehicleType.moto,
        ticketBase: base, enteredAt: DateTime(2026, 10, 21, 8, 35), helmetCount: 1,
        vehiclePrice: 100, helmetPrice: 0, licensePlate: '11 AB 2345',
        plateCaptureMethod: PlateCaptureMethod.ocr, plateVerified: true,
      ));
      final row = (await db.query('parking_sessions', where: 'id = ?', whereArgs: [id])).single;
      expect(row['vehicle_type'], 'MOTO');
      expect(row['license_plate'], '11 AB 2345');
      expect(row['plate_capture_method'], 'OCR');
      expect(row['plate_verified'], 1);
      expect(row['plate_ocr_raw_text'], isNull, reason: 'texte brut non conservé par défaut');
      expect(row['amount'], 100);
    });

    test('plaque vide : NULL en base, méthode AUCUN', () async {
      final db = await legacyDb();
      await const PlateColumnsMigration().apply(db);
      final repo = SqfliteSessionRepository(db);
      final id = await repo.save(ParkingSession(
        vehicleType: VehicleType.moto,
        ticketBase: 'PK-000002', enteredAt: DateTime(2026), helmetCount: 0, vehiclePrice: 100,
        helmetPrice: 0, licensePlate: '', plateCaptureMethod: PlateCaptureMethod.none, plateVerified: false,
      ));
      final row = (await db.query('parking_sessions', where: 'id = ?', whereArgs: [id])).single;
      expect(row['license_plate'], isNull);
      expect(row['plate_capture_method'], 'AUCUN');
    });
  });

  group('Sortie (scan du ticket)', () {
    test('retrouver une session par ticket puis valider la sortie', () async {
      final db = await legacyDb();
      await const PlateColumnsMigration().apply(db);
      final repo = SqfliteSessionRepository(db);
      await repo.save(ParkingSession(
        vehicleType: VehicleType.voiture, ticketBase: 'PK-000002',
        enteredAt: DateTime(2026, 10, 21, 8, 35), helmetCount: 0, vehiclePrice: 300,
        helmetPrice: 0, licensePlate: '11 AB 2345',
        plateCaptureMethod: PlateCaptureMethod.ocr, plateVerified: true,
      ));
      final found = (await repo.findByTicket('PK-000002'))!;
      expect(found.vehicleType, VehicleType.voiture);
      expect(found.licensePlate, '11 AB 2345');
      expect(found.total, 300);
      expect(found.isInside, isTrue);
      await repo.markExited(found.id!, DateTime(2026, 10, 21, 10, 0));
      final after = (await repo.findByTicket('PK-000002'))!;
      expect(after.isInside, isFalse);
      expect(after.exitedAt, DateTime(2026, 10, 21, 10, 0));
      expect(await repo.findByTicket('PK-999999'), isNull);
    });
  });

  group('Photos de plaques', () {
    late Directory base;
    setUp(() => base = Directory.systemTemp.createTempSync('pk_photo_'));
    tearDown(() => base.deleteSync(recursive: true));

    File tempPhoto() => File('${base.path}/capture.jpg')..writeAsBytesSync([1, 2, 3]);

    test('par défaut : photo supprimée après extraction du numéro', () async {
      final store = PlatePhotoStore(keepPhotos: false, retentionDays: 7, baseDir: () async => base);
      final f = tempPhoto();
      expect(await store.finalize(f.path, ticketBase: 'PK-1'), isNull);
      expect(f.existsSync(), isFalse);
    });

    test('conservation activée : dossier privé, caché de la galerie', () async {
      final store = PlatePhotoStore(keepPhotos: true, retentionDays: 7, baseDir: () async => base);
      final kept = await store.finalize(tempPhoto().path, ticketBase: 'PK-1');
      expect(kept, isNotNull);
      expect(File(kept!).existsSync(), isTrue);
      expect(kept, startsWith('${base.path}/plaques/'));
      expect(File('${base.path}/plaques/.nomedia').existsSync(), isTrue);
    });

    test('rétention : photos expirées supprimées', () async {
      final store = PlatePhotoStore(keepPhotos: true, retentionDays: 7, baseDir: () async => base);
      final kept = await store.finalize(tempPhoto().path, ticketBase: 'PK-1');
      File(kept!).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 8)));
      expect(await store.purgeExpired(), 1);
      expect(File(kept).existsSync(), isFalse);
    });

    test('accès limité aux rôles autorisés', () {
      final store = PlatePhotoStore(keepPhotos: true, retentionDays: 7, baseDir: () async => base);
      expect(store.canView('proprietaire'), isTrue);
      expect(store.canView('gardien'), isFalse);
      expect(PlatePhotoStore(keepPhotos: false, retentionDays: 7, baseDir: () async => base)
          .canView('proprietaire'), isFalse);
    });
  });
}
