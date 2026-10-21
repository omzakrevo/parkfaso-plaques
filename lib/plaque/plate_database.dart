// PARKFASO — Base de données : colonnes d'immatriculation, sortie, enregistrement.
//
// La migration est idempotente : elle n'ajoute que les colonnes absentes et ne
// touche à aucune donnée existante. Elle peut donc tourner à chaque démarrage.

import 'package:sqflite/sqflite.dart';

import 'plate_models.dart';

/// Colonnes ajoutées aux sessions de stationnement.
const Map<String, String> kPlateColumns = {
  'license_plate': 'TEXT',
  'plate_capture_method': "TEXT NOT NULL DEFAULT 'AUCUN'",
  'plate_ocr_raw_text': 'TEXT',
  'plate_photo_path': 'TEXT',
  'plate_verified': 'INTEGER NOT NULL DEFAULT 0',
  // Scan du ticket à la sortie
  'exited_at': 'TEXT',
};

class PlateColumnsMigration {
  const PlateColumnsMigration({this.table = 'parking_sessions'});

  final String table;

  /// À appeler dans `onUpgrade` (ou au démarrage) de votre base sqflite.
  Future<List<String>> apply(DatabaseExecutor db) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    if (info.isEmpty) {
      throw StateError('Table "$table" introuvable : vérifiez le nom de la table des sessions.');
    }
    final existing = info.map((r) => (r['name'] as String).toLowerCase()).toSet();
    final added = <String>[];
    for (final e in kPlateColumns.entries) {
      if (!existing.contains(e.key)) {
        await db.execute('ALTER TABLE $table ADD COLUMN ${e.key} ${e.value}');
        added.add(e.key);
      }
    }
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${table}_license_plate ON $table(license_plate)');
    return added;
  }

  /// Efface les textes OCR bruts et chemins de photos expirés (données temporaires).
  Future<int> purgeTemporaryData(DatabaseExecutor db,
      {required String enteredAtColumn, required DateTime olderThan}) {
    return db.rawUpdate(
      'UPDATE $table SET plate_ocr_raw_text = NULL, plate_photo_path = NULL '
      'WHERE $enteredAtColumn < ? AND (plate_ocr_raw_text IS NOT NULL OR plate_photo_path IS NOT NULL)',
      [olderThan.toIso8601String()],
    );
  }
}

/// Enregistrement et lecture des sessions. Branchez ici votre dépôt PARKFASO
/// existant si vous en avez déjà un.
abstract class SessionRepository {
  /// Prochain numéro de ticket, ex. « PK-000125 ».
  Future<String> nextTicketBase();

  /// Enregistre la session et renvoie son identifiant.
  Future<int> save(ParkingSession session);

  /// Retrouve une session par son numéro de base (« PK-000125 »).
  Future<ParkingSession?> findByTicket(String ticketBase);

  /// Enregistre la sortie du véhicule ([by] : gardien qui valide).
  Future<void> markExited(int id, DateTime at, {String? by});
}

/// Noms des colonnes déjà présentes dans votre table des sessions.
class SessionColumns {
  const SessionColumns({
    this.id = 'id',
    this.ticketNumber = 'ticket_number',
    this.vehicleType = 'vehicle_type',
    this.enteredAt = 'entered_at',
    this.helmetCount = 'helmet_count',
    this.amount = 'amount',
  });

  final String id;
  final String ticketNumber;
  final String vehicleType;
  final String enteredAt;
  final String helmetCount;
  final String amount;
}

class SqfliteSessionRepository implements SessionRepository {
  SqfliteSessionRepository(
    this.db, {
    this.table = 'parking_sessions',
    this.columns = const SessionColumns(),
    this.ticketPrefix = 'PK',
    this.helmetPrice = 0,
  });

  final Database db;
  final String table;
  final SessionColumns columns;
  final String ticketPrefix;

  /// Prix casque actuel, pour reconstituer le détail d'une session lue en base.
  final int helmetPrice;

  @override
  Future<String> nextTicketBase() async {
    final rows = await db.rawQuery('SELECT COALESCE(MAX(rowid), 0) + 1 AS n FROM $table');
    final n = (rows.first['n'] as int?) ?? 1;
    return '$ticketPrefix-${n.toString().padLeft(6, '0')}';
  }

  @override
  Future<int> save(ParkingSession s) {
    return db.insert(table, {
      columns.ticketNumber: s.ticketBase,
      columns.vehicleType: s.vehicleType.dbValue,
      columns.enteredAt: s.enteredAt.toIso8601String(),
      columns.helmetCount: s.helmetCount,
      columns.amount: s.total,
      ...s.plateColumns(),
      'exited_at': s.exitedAt?.toIso8601String(),
    });
  }

  @override
  Future<ParkingSession?> findByTicket(String ticketBase) async {
    final rows = await db.query(table,
        where: '${columns.ticketNumber} = ?', whereArgs: [ticketBase], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final helmets = (r[columns.helmetCount] as int?) ?? 0;
    final amount = (r[columns.amount] as int?) ?? 0;
    return ParkingSession(
      id: r[columns.id] as int?,
      vehicleType: VehicleType.fromDb(r[columns.vehicleType] as String?),
      ticketBase: r[columns.ticketNumber] as String,
      enteredAt: DateTime.parse(r[columns.enteredAt] as String),
      helmetCount: helmets,
      vehiclePrice: amount - helmetPrice * helmets,
      helmetPrice: helmetPrice,
      licensePlate: (r['license_plate'] as String?) ?? '',
      plateCaptureMethod: PlateCaptureMethod.fromDb(r['plate_capture_method'] as String?),
      plateVerified: r['plate_verified'] == 1,
      platePhotoPath: r['plate_photo_path'] as String?,
      exitedAt: r['exited_at'] == null ? null : DateTime.parse(r['exited_at'] as String),
    );
  }

  @override
  Future<void> markExited(int id, DateTime at, {String? by}) async {
    await db.update(table, {'exited_at': at.toIso8601String()},
        where: '${columns.id} = ?', whereArgs: [id]);
  }
}
