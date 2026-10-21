// PARKFASO — Parkings, comptes et filtres d'historique.

import 'dart:convert';

import '../plaque/plate_models.dart';

/// Un parking géré par le propriétaire (mode SaaS : plusieurs parkings).
class Parking {
  const Parking({
    required this.id,
    required this.name,
    required this.code,
    required this.prices,
    this.helmetPrice = 0,
    this.allowEmptyPlate = true,
    this.enabledVehicles = VehicleType.values,
    required this.createdAt,
  });

  /// Identifiant unique (aussi utilisé comme dossier de synchronisation).
  final String id;
  final String name;

  /// Code à 2 lettres imprimé dans les n° de ticket (« PC » → PCA-000125).
  final String code;
  final Map<VehicleType, int> prices;
  final int helmetPrice;
  final bool allowEmptyPlate;
  final List<VehicleType> enabledVehicles;
  final DateTime createdAt;

  static const defaultPrices = {
    VehicleType.moto: 100,
    VehicleType.voiture: 300,
    VehicleType.tricycle: 200,
    VehicleType.velo: 50,
  };

  /// Code de ticket déduit du nom : « Parking Central » → « PC ».
  static String codeFromName(String name) {
    final words = name
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z ]'), ' ')
        .split(' ')
        .where((w) => w.isNotEmpty && !const {'DE', 'DU', 'LA', 'LE', 'DES'}.contains(w))
        .toList();
    if (words.isEmpty) return 'PK';
    if (words.length == 1) return (words.first.padRight(2, 'X')).substring(0, 2);
    return '${words[0][0]}${words[1][0]}';
  }

  ParkingSettings toSettings({String brandName = 'PARKFASO', PaperWidth paper = PaperWidth.mm58}) =>
      ParkingSettings(
        brandName: brandName,
        parkingName: name,
        prices: prices,
        helmetPrice: helmetPrice,
        allowEmptyPlate: allowEmptyPlate,
        enabledVehicles: enabledVehicles,
        paperWidth: paper,
      );

  Parking copyWith({
    String? name,
    Map<VehicleType, int>? prices,
    int? helmetPrice,
    bool? allowEmptyPlate,
    List<VehicleType>? enabledVehicles,
  }) =>
      Parking(
        id: id,
        name: name ?? this.name,
        code: code,
        prices: prices ?? this.prices,
        helmetPrice: helmetPrice ?? this.helmetPrice,
        allowEmptyPlate: allowEmptyPlate ?? this.allowEmptyPlate,
        enabledVehicles: enabledVehicles ?? this.enabledVehicles,
        createdAt: createdAt,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'code': code,
        'prices_json': jsonEncode({for (final e in prices.entries) e.key.dbValue: e.value}),
        'helmet_price': helmetPrice,
        'allow_empty_plate': allowEmptyPlate ? 1 : 0,
        'vehicles': enabledVehicles.map((v) => v.dbValue).join(','),
        'created_at': createdAt.toIso8601String(),
      };

  static Parking fromRow(Map<String, Object?> r) {
    final raw = jsonDecode(r['prices_json'] as String) as Map<String, dynamic>;
    final vehicles = ((r['vehicles'] as String?) ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .map(VehicleType.fromDb)
        .toList();
    return Parking(
      id: r['id'] as String,
      name: r['name'] as String,
      code: r['code'] as String,
      prices: {for (final e in raw.entries) VehicleType.fromDb(e.key): (e.value as num).toInt()},
      helmetPrice: (r['helmet_price'] as int?) ?? 0,
      allowEmptyPlate: r['allow_empty_plate'] != 0,
      enabledVehicles: vehicles.isEmpty ? VehicleType.values : vehicles,
      createdAt: DateTime.parse(r['created_at'] as String),
    );
  }

  Map<String, Object?> toJson() => {...toRow(), 'prices': jsonDecode(toRow()['prices_json'] as String)};
}

enum UserRole {
  admin('ADMIN', 'Administrateur'),
  gardien('GARDIEN', 'Gardien');

  const UserRole(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static UserRole fromDb(String? v) => v == 'ADMIN' ? UserRole.admin : UserRole.gardien;
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.role,
    required this.pinHash,
    required this.salt,
    this.active = true,
  });

  final String id;
  final String name;
  final UserRole role;
  final String pinHash;
  final String salt;
  final bool active;

  bool get isAdmin => role == UserRole.admin;

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'role': role.dbValue,
        'pin_hash': pinHash,
        'salt': salt,
        'active': active ? 1 : 0,
      };

  static AppUser fromRow(Map<String, Object?> r) => AppUser(
        id: r['id'] as String,
        name: r['name'] as String,
        role: UserRole.fromDb(r['role'] as String?),
        pinHash: r['pin_hash'] as String,
        salt: r['salt'] as String,
        active: r['active'] != 0,
      );
}

enum StatusFilter { all, inside, exited }

/// Critères de l'historique.
class HistoryFilter {
  const HistoryFilter({
    required this.from,
    required this.to,
    this.vehicleType,
    this.status = StatusFilter.all,
    this.query = '',
    this.parkingId,
  });

  /// Bornes incluses (début de journée → fin de journée).
  final DateTime from;
  final DateTime to;
  final VehicleType? vehicleType;
  final StatusFilter status;

  /// Recherche : plaque (avec ou sans espaces) ou n° de ticket.
  final String query;
  final String? parkingId;

  static DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime dayEnd(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  factory HistoryFilter.today(DateTime now, {String? parkingId}) =>
      HistoryFilter(from: dayStart(now), to: dayEnd(now), parkingId: parkingId);

  HistoryFilter copyWith({
    DateTime? from,
    DateTime? to,
    VehicleType? vehicleType,
    bool clearVehicle = false,
    StatusFilter? status,
    String? query,
  }) =>
      HistoryFilter(
        from: from ?? this.from,
        to: to ?? this.to,
        vehicleType: clearVehicle ? null : (vehicleType ?? this.vehicleType),
        status: status ?? this.status,
        query: query ?? this.query,
        parkingId: parkingId,
      );
}

/// Chiffres d'une période (jour, mois…).
class RevenuePoint {
  const RevenuePoint(this.period, this.count, this.total);

  /// Début de la période (jour à 00:00 ou 1er du mois).
  final DateTime period;
  final int count;
  final int total;
}

class ParkingStats {
  const ParkingStats({
    required this.inside,
    required this.todayCount,
    required this.todayTotal,
    required this.monthTotal,
  });

  final int inside;
  final int todayCount;
  final int todayTotal;
  final int monthTotal;

  static const empty = ParkingStats(inside: 0, todayCount: 0, todayTotal: 0, monthTotal: 0);
}
