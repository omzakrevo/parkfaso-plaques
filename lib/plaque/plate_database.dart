// PARKFASO — Base de données : colonnes d'immatriculation + enregistrement moto.
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

/// Enregistrement des sessions moto. Branchez ici votre dépôt PARKFASO existant
/// si vous en avez déjà un (il suffit d'implémenter ces deux méthodes).
abstract class MotoSessionRepository {
  /// Prochain numéro de ticket, ex. « PK-000125 ».
  Future<String> nextTicketBase();

  /// Enregistre la session et renvoie son identifiant.
  Future<int> save(MotoParkingSession session);
}

/// Noms des colonnes déjà présentes dans votre table des sessions.
class SessionColumns {
  const SessionColumns({
    this.ticketNumber = 'ticket_number',
    this.vehicleType = 'vehicle_type',
    this.enteredAt = 'entered_at',
    this.helmetCount = 'helmet_count',
    this.amount = 'amount',
  });

  final String ticketNumber;
  final String vehicleType;
  final String enteredAt;
  final String helmetCount;
  final String amount;
}

class SqfliteMotoSessionRepository implements MotoSessionRepository {
  SqfliteMotoSessionRepository(
    this.db, {
    this.table = 'parking_sessions',
    this.columns = const SessionColumns(),
    this.ticketPrefix = 'PK',
  });

  final Database db;
  final String table;
  final SessionColumns columns;
  final String ticketPrefix;

  @override
  Future<String> nextTicketBase() async {
    final rows = await db.rawQuery('SELECT COALESCE(MAX(rowid), 0) + 1 AS n FROM $table');
    final n = (rows.first['n'] as int?) ?? 1;
    return '$ticketPrefix-${n.toString().padLeft(6, '0')}';
  }

  @override
  Future<int> save(MotoParkingSession s) {
    return db.insert(table, {
      columns.ticketNumber: s.ticketBase,
      columns.vehicleType: 'MOTO',
      columns.enteredAt: s.enteredAt.toIso8601String(),
      columns.helmetCount: s.helmetCount,
      columns.amount: s.total,
      ...s.plateColumns(),
    });
  }
}
