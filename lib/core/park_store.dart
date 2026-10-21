// PARKFASO — Base de données locale de l'application (hors ligne).
//
// Tables : parkings, users, parking_sessions, app_meta.
// Version 1 → 2 : les anciennes installations gardent leurs sessions.

import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../plaque/plate_database.dart';
import '../plaque/plate_models.dart';
import 'models.dart';

const kDbVersion = 2;

Future<Database> openParkDatabase(String path, {DatabaseFactory? factory, bool singleInstance = true}) async {
  final f = factory ?? databaseFactory;
  return f.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: kDbVersion,
      singleInstance: singleInstance,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE parking_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ticket_number TEXT NOT NULL,
            vehicle_type TEXT NOT NULL,
            entered_at TEXT NOT NULL,
            helmet_count INTEGER NOT NULL DEFAULT 0,
            amount INTEGER NOT NULL DEFAULT 0
          )''');
        await _createV2(db);
      },
      onUpgrade: (db, from, to) async {
        if (from < 2) await _createV2(db);
      },
    ),
  );
}

Future<void> _createV2(DatabaseExecutor db) async {
  await const PlateColumnsMigration().apply(db);
  final cols = (await db.rawQuery('PRAGMA table_info(parking_sessions)'))
      .map((r) => r['name'] as String)
      .toSet();
  for (final c in ['parking_id', 'entered_by', 'exited_by', 'device_id']) {
    if (!cols.contains(c)) await db.execute('ALTER TABLE parking_sessions ADD COLUMN $c TEXT');
  }
  await db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_parking_date '
      'ON parking_sessions(parking_id, entered_at)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_ticket ON parking_sessions(ticket_number)');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS parkings (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      code TEXT NOT NULL,
      prices_json TEXT NOT NULL,
      helmet_price INTEGER NOT NULL DEFAULT 0,
      allow_empty_plate INTEGER NOT NULL DEFAULT 1,
      vehicles TEXT,
      created_at TEXT NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      role TEXT NOT NULL,
      pin_hash TEXT NOT NULL,
      salt TEXT NOT NULL,
      active INTEGER NOT NULL DEFAULT 1
    )''');
  await db.execute('CREATE TABLE IF NOT EXISTS app_meta (key TEXT PRIMARY KEY, value TEXT)');
}

String randomId([int length = 10]) {
  const chars = 'abcdefghijkmnpqrstuvwxyz23456789';
  final r = Random.secure();
  return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Paramètres, parkings et comptes.
class ParkStore {
  ParkStore(this.db);

  final Database db;

  // --- Réglages clé/valeur -------------------------------------------------
  Future<String?> meta(String key) async {
    final r = await db.query('app_meta', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setMeta(String key, String? value) async {
    if (value == null) {
      await db.delete('app_meta', where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert('app_meta', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Identifiant de ce téléphone (stable).
  Future<String> deviceId() async {
    var id = await meta('device_id');
    if (id == null) {
      id = randomId(8);
      await setMeta('device_id', id);
    }
    return id;
  }

  /// Lettre de ce téléphone dans les n° de ticket (A, B, C…), pour éviter que
  /// deux téléphones d'un même parking produisent le même numéro.
  Future<String> deviceLetter() async => (await meta('device_letter')) ?? 'A';
  Future<void> setDeviceLetter(String l) => setMeta('device_letter', l.toUpperCase().substring(0, 1));

  // --- Parkings ------------------------------------------------------------
  Future<List<Parking>> parkings() async =>
      (await db.query('parkings', orderBy: 'created_at')).map(Parking.fromRow).toList();

  Future<Parking?> parking(String id) async {
    final r = await db.query('parkings', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Parking.fromRow(r.first);
  }

  Future<Parking> createParking(String name, {Map<VehicleType, int>? prices, int helmetPrice = 0,
      DateTime? now}) async {
    final p = Parking(
      id: randomId(),
      name: name.trim(),
      code: Parking.codeFromName(name),
      prices: prices ?? Parking.defaultPrices,
      helmetPrice: helmetPrice,
      createdAt: now ?? DateTime.now(),
    );
    await db.insert('parkings', p.toRow());
    return p;
  }

  Future<void> saveParking(Parking p) =>
      db.update('parkings', p.toRow(), where: 'id = ?', whereArgs: [p.id]);

  Future<void> deleteParking(String id) => db.delete('parkings', where: 'id = ?', whereArgs: [id]);

  Future<String?> activeParkingId() => meta('active_parking');
  Future<void> setActiveParking(String id) => setMeta('active_parking', id);

  // --- Comptes -------------------------------------------------------------
  Future<List<AppUser>> users({bool includeInactive = false}) async => (await db.query('users',
          where: includeInactive ? null : 'active = 1', orderBy: "role = 'ADMIN' DESC, name"))
      .map(AppUser.fromRow)
      .toList();

  Future<void> saveUser(AppUser u) =>
      db.insert('users', u.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteUser(String id) => db.update('users', {'active': 0}, where: 'id = ?', whereArgs: [id]);

  Future<bool> hasAdmin() async =>
      Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM users WHERE role = 'ADMIN' AND active = 1"))! > 0;
}

/// Sessions de stationnement d'un parking : entrée, sortie, historique, stats.
class ParkSessionStore implements SessionRepository {
  ParkSessionStore(this.db, {required this.parking, this.deviceId, this.deviceLetter = 'A',
      this.currentUser});

  final Database db;
  final Parking parking;
  final String? deviceId;
  final String deviceLetter;

  /// Gardien connecté (renseigné dans entered_by / exited_by).
  String? currentUser;

  static const _t = 'parking_sessions';

  @override
  Future<String> nextTicketBase() async {
    final prefix = '${parking.code}$deviceLetter';
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM $_t WHERE ticket_number LIKE ?', ['$prefix-%']);
    final n = ((rows.first['n'] as int?) ?? 0) + 1;
    return '$prefix-${n.toString().padLeft(6, '0')}';
  }

  @override
  Future<int> save(ParkingSession s) => db.insert(_t, {
        'ticket_number': s.ticketBase,
        'vehicle_type': s.vehicleType.dbValue,
        'entered_at': s.enteredAt.toIso8601String(),
        'helmet_count': s.helmetCount,
        'amount': s.total,
        ...s.plateColumns(),
        'exited_at': s.exitedAt?.toIso8601String(),
        'parking_id': parking.id,
        'entered_by': s.enteredBy ?? currentUser,
        'device_id': deviceId,
      });

  @override
  Future<ParkingSession?> findByTicket(String ticketBase) async {
    final r = await db.query(_t, where: 'ticket_number = ?', whereArgs: [ticketBase], limit: 1);
    return r.isEmpty ? null : sessionFromRow(r.first, helmetPrice: parking.helmetPrice);
  }

  @override
  Future<void> markExited(int id, DateTime at, {String? by}) => db.update(
      _t, {'exited_at': at.toIso8601String(), 'exited_by': by ?? currentUser},
      where: 'id = ?', whereArgs: [id]);

  static ParkingSession sessionFromRow(Map<String, Object?> r, {int helmetPrice = 0}) {
    final helmets = (r['helmet_count'] as int?) ?? 0;
    final amount = (r['amount'] as int?) ?? 0;
    return ParkingSession(
      id: r['id'] as int?,
      vehicleType: VehicleType.fromDb(r['vehicle_type'] as String?),
      ticketBase: r['ticket_number'] as String,
      enteredAt: DateTime.parse(r['entered_at'] as String),
      helmetCount: helmets,
      vehiclePrice: amount - helmetPrice * helmets,
      helmetPrice: helmetPrice,
      licensePlate: (r['license_plate'] as String?) ?? '',
      plateCaptureMethod: PlateCaptureMethod.fromDb(r['plate_capture_method'] as String?),
      plateVerified: r['plate_verified'] == 1,
      platePhotoPath: r['plate_photo_path'] as String?,
      exitedAt: r['exited_at'] == null ? null : DateTime.parse(r['exited_at'] as String),
      parkingId: r['parking_id'] as String?,
      enteredBy: r['entered_by'] as String?,
      exitedBy: r['exited_by'] as String?,
    );
  }

  // --- Historique ------------------------------------------------------------
  (String, List<Object?>) _where(HistoryFilter f) {
    final w = <String>['parking_id = ?', 'entered_at >= ?', 'entered_at <= ?'];
    final a = <Object?>[f.parkingId ?? parking.id, f.from.toIso8601String(), f.to.toIso8601String()];
    if (f.vehicleType != null) {
      w.add('vehicle_type = ?');
      a.add(f.vehicleType!.dbValue);
    }
    if (f.status == StatusFilter.inside) w.add('exited_at IS NULL');
    if (f.status == StatusFilter.exited) w.add('exited_at IS NOT NULL');
    final q = f.query.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (q.isNotEmpty) {
      w.add("(REPLACE(UPPER(COALESCE(license_plate, '')), ' ', '') LIKE ? OR UPPER(ticket_number) LIKE ?)");
      a
        ..add('%$q%')
        ..add('%$q%');
    }
    return (w.join(' AND '), a);
  }

  Future<List<ParkingSession>> history(HistoryFilter f, {int limit = 500}) async {
    final (where, args) = _where(f);
    final rows = await db.query(_t, where: where, whereArgs: args, orderBy: 'entered_at DESC', limit: limit);
    return rows.map((r) => sessionFromRow(r, helmetPrice: parking.helmetPrice)).toList();
  }

  /// Recherche d'une plaque ou d'un ticket sur toute la durée.
  Future<List<ParkingSession>> search(String query, {int limit = 100}) => history(
      HistoryFilter(from: DateTime(2000), to: DateTime(2100), query: query, parkingId: parking.id),
      limit: limit);

  /// Véhicules encore au parking, du plus ancien au plus récent.
  Future<List<ParkingSession>> inside({VehicleType? type}) async {
    final rows = await db.query(_t,
        where: 'parking_id = ? AND exited_at IS NULL${type == null ? '' : ' AND vehicle_type = ?'}',
        whereArgs: [parking.id, if (type != null) type.dbValue],
        orderBy: 'entered_at ASC');
    return rows.map((r) => sessionFromRow(r, helmetPrice: parking.helmetPrice)).toList();
  }

  // --- Rapports --------------------------------------------------------------
  Future<ParkingStats> stats(DateTime now) async {
    final day = HistoryFilter.dayStart(now).toIso8601String();
    final month = DateTime(now.year, now.month).toIso8601String();
    final r = await db.rawQuery('''
      SELECT
        SUM(CASE WHEN exited_at IS NULL THEN 1 ELSE 0 END) AS inside,
        SUM(CASE WHEN entered_at >= ? THEN 1 ELSE 0 END) AS today_count,
        SUM(CASE WHEN entered_at >= ? THEN amount ELSE 0 END) AS today_total,
        SUM(CASE WHEN entered_at >= ? THEN amount ELSE 0 END) AS month_total
      FROM $_t WHERE parking_id = ?''', [day, day, month, parking.id]);
    final x = r.first;
    return ParkingStats(
      inside: (x['inside'] as int?) ?? 0,
      todayCount: (x['today_count'] as int?) ?? 0,
      todayTotal: (x['today_total'] as int?) ?? 0,
      monthTotal: (x['month_total'] as int?) ?? 0,
    );
  }

  /// Chiffre d'affaires par jour entre deux dates (jours sans entrée inclus, à 0).
  Future<List<RevenuePoint>> revenueByDay(DateTime from, DateTime to) async {
    final rows = await db.rawQuery('''
      SELECT substr(entered_at, 1, 10) AS d, COUNT(*) AS n, SUM(amount) AS t
      FROM $_t WHERE parking_id = ? AND entered_at >= ? AND entered_at <= ?
      GROUP BY d''', [parking.id, HistoryFilter.dayStart(from).toIso8601String(),
      HistoryFilter.dayEnd(to).toIso8601String()]);
    final byDay = {for (final r in rows) r['d'] as String: r};
    final out = <RevenuePoint>[];
    for (var d = HistoryFilter.dayStart(from); !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
      final key = d.toIso8601String().substring(0, 10);
      final r = byDay[key];
      out.add(RevenuePoint(d, (r?['n'] as int?) ?? 0, (r?['t'] as int?) ?? 0));
    }
    return out;
  }

  /// Chiffre d'affaires par mois sur une année.
  Future<List<RevenuePoint>> revenueByMonth(int year) async {
    final rows = await db.rawQuery('''
      SELECT substr(entered_at, 1, 7) AS m, COUNT(*) AS n, SUM(amount) AS t
      FROM $_t WHERE parking_id = ? AND substr(entered_at, 1, 4) = ?
      GROUP BY m''', [parking.id, '$year']);
    final byMonth = {for (final r in rows) r['m'] as String: r};
    return [
      for (var m = 1; m <= 12; m++)
        () {
          final key = '$year-${m.toString().padLeft(2, '0')}';
          final r = byMonth[key];
          return RevenuePoint(DateTime(year, m), (r?['n'] as int?) ?? 0, (r?['t'] as int?) ?? 0);
        }(),
    ];
  }

  /// Répartition par type de véhicule sur une période.
  Future<Map<VehicleType, RevenuePoint>> byVehicle(DateTime from, DateTime to) async {
    final rows = await db.rawQuery('''
      SELECT vehicle_type AS v, COUNT(*) AS n, SUM(amount) AS t
      FROM $_t WHERE parking_id = ? AND entered_at >= ? AND entered_at <= ?
      GROUP BY v''', [parking.id, from.toIso8601String(), to.toIso8601String()]);
    return {
      for (final r in rows)
        VehicleType.fromDb(r['v'] as String?):
            RevenuePoint(from, (r['n'] as int?) ?? 0, (r['t'] as int?) ?? 0),
    };
  }

  /// Toutes les sessions d'un mois (pour la synchronisation).
  Future<List<Map<String, Object?>>> monthRows(int year, int month) async {
    final from = DateTime(year, month).toIso8601String();
    final to = DateTime(year, month + 1).toIso8601String();
    return db.query(_t,
        where: 'parking_id = ? AND entered_at >= ? AND entered_at < ?',
        whereArgs: [parking.id, from, to],
        orderBy: 'entered_at');
  }
}
