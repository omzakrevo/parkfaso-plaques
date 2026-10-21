// PARKFASO — Modèles : types de véhicule, réglages, sessions de stationnement.

import 'package:flutter/material.dart';

/// Types de véhicule acceptés au parking.
enum VehicleType {
  moto('MOTO', 'Moto', 'la', 'M', Icons.two_wheeler, hasHelmet: true, hasPlate: true),
  voiture('VOITURE', 'Voiture', 'la', 'V', Icons.directions_car_filled, hasHelmet: false, hasPlate: true),
  tricycle('TRICYCLE', 'Tricycle', 'le', 'T', Icons.electric_rickshaw, hasHelmet: true, hasPlate: true),
  velo('VELO', 'Vélo', 'le', 'B', Icons.pedal_bike, hasHelmet: false, hasPlate: false);

  const VehicleType(this.dbValue, this.label, this.article, this.ticketSuffix, this.icon,
      {required this.hasHelmet, required this.hasPlate});

  final String dbValue;
  final String label;

  /// Article : « la moto », « le vélo ».
  final String article;

  /// « la moto », « le vélo ».
  String get withArticle => '$article ${label.toLowerCase()}';

  /// Suffixe du ticket posé sur le véhicule : PK-000125-M, -V, -T, -B.
  final String ticketSuffix;
  final IconData icon;

  /// Dépôt de casque possible (moto, tricycle).
  final bool hasHelmet;

  /// Immatriculation possible (le vélo n'en a pas).
  final bool hasPlate;

  static VehicleType fromDb(String? v) =>
      values.firstWhere((t) => t.dbValue == v, orElse: () => VehicleType.moto);
}

/// Comment le numéro a été obtenu (colonne `plate_capture_method`).
enum PlateCaptureMethod {
  /// Lu par la caméra et accepté tel quel par le gardien.
  ocr('OCR'),

  /// Tapé par le gardien, ou numéro OCR corrigé à la main.
  manual('MANUEL'),

  /// Champ laissé vide.
  none('AUCUN');

  const PlateCaptureMethod(this.dbValue);
  final String dbValue;

  static PlateCaptureMethod fromDb(String? v) =>
      values.firstWhere((m) => m.dbValue == v, orElse: () => PlateCaptureMethod.none);
}

enum PaperWidth {
  mm58(32, '58 mm'),
  mm80(48, '80 mm');

  const PaperWidth(this.charsPerLine, this.label);

  /// Caractères par ligne en police normale (police A, 12×24).
  final int charsPerLine;
  final String label;

  static PaperWidth fromName(String? n) =>
      values.firstWhere((p) => p.name == n, orElse: () => PaperWidth.mm58);
}

/// Réglages du parking. À alimenter depuis la configuration PARKFASO existante.
class ParkingSettings {
  const ParkingSettings({
    this.brandName = 'PARKFASO',
    required this.parkingName,
    this.prices = const {
      VehicleType.moto: 100,
      VehicleType.voiture: 300,
      VehicleType.tricycle: 200,
      VehicleType.velo: 50,
    },
    this.helmetPrice = 0,
    this.currency = 'FCFA',
    this.paperWidth = PaperWidth.mm58,
    this.allowEmptyPlate = true,
    this.maxHelmets = 3,
    this.enabledVehicles = VehicleType.values,
    this.keepPlatePhotos = false,
    this.platePhotoRetentionDays = 7,
    this.keepOcrRawText = false,
  });

  final String brandName;
  final String parkingName;
  final Map<VehicleType, int> prices;

  /// Prix par casque déposé (0 si gratuit).
  final int helmetPrice;
  final String currency;
  final PaperWidth paperWidth;

  /// Immatriculation facultative (par défaut) ou obligatoire.
  final bool allowEmptyPlate;
  final int maxHelmets;

  /// Types de véhicule proposés à l'accueil.
  final List<VehicleType> enabledVehicles;

  /// Conservation des photos de plaques : désactivée par défaut.
  final bool keepPlatePhotos;
  final int platePhotoRetentionDays;

  /// Conserver le texte OCR brut en base (désactivé : donnée temporaire).
  final bool keepOcrRawText;

  int priceOf(VehicleType t) => prices[t] ?? 0;

  ParkingSettings copyWith({
    Map<VehicleType, int>? prices,
    int? helmetPrice,
    PaperWidth? paperWidth,
    bool? allowEmptyPlate,
    bool? keepPlatePhotos,
    bool? keepOcrRawText,
  }) =>
      ParkingSettings(
        brandName: brandName,
        parkingName: parkingName,
        prices: prices ?? this.prices,
        helmetPrice: helmetPrice ?? this.helmetPrice,
        currency: currency,
        paperWidth: paperWidth ?? this.paperWidth,
        allowEmptyPlate: allowEmptyPlate ?? this.allowEmptyPlate,
        maxHelmets: maxHelmets,
        enabledVehicles: enabledVehicles,
        keepPlatePhotos: keepPlatePhotos ?? this.keepPlatePhotos,
        platePhotoRetentionDays: platePhotoRetentionDays,
        keepOcrRawText: keepOcrRawText ?? this.keepOcrRawText,
      );
}

/// Ce que l'écran caméra renvoie au formulaire d'entrée.
class PlateCaptureOutcome {
  const PlateCaptureOutcome({
    required this.plate,
    required this.method,
    required this.verified,
    required this.photoPath,
    this.ocrRawText,
    this.saveNow = false,
  });

  final String plate;
  final PlateCaptureMethod method;
  final bool verified;
  final String? photoPath;
  final String? ocrRawText;

  /// Le gardien a confirmé : enregistrer et imprimer le ticket client sans autre geste.
  final bool saveNow;
}

/// Une session de stationnement.
class ParkingSession {
  const ParkingSession({
    this.id,
    required this.vehicleType,
    required this.ticketBase,
    required this.enteredAt,
    required this.helmetCount,
    required this.vehiclePrice,
    required this.helmetPrice,
    required this.licensePlate,
    required this.plateCaptureMethod,
    required this.plateVerified,
    this.plateOcrRawText,
    this.platePhotoPath,
    this.exitedAt,
    this.parkingId,
    this.enteredBy,
    this.exitedBy,
  });

  final int? id;

  /// Parking concerné (mode multi-parkings).
  final String? parkingId;

  /// Gardien qui a enregistré l'entrée / validé la sortie.
  final String? enteredBy;
  final String? exitedBy;
  final VehicleType vehicleType;

  /// Numéro de base du ticket, ex. « PK-000125 » (suffixes -C, -M, -H1…).
  final String ticketBase;
  final DateTime enteredAt;
  final int helmetCount;
  final int vehiclePrice;

  /// Prix unitaire d'un casque.
  final int helmetPrice;

  /// Numéro validé, ex. « 11 AB 2345 ». Vide si non renseigné.
  final String licensePlate;
  final PlateCaptureMethod plateCaptureMethod;
  final bool plateVerified;
  final String? plateOcrRawText;
  final String? platePhotoPath;

  /// Heure de sortie (validée au scan du ticket). Null = encore au parking.
  final DateTime? exitedAt;

  int get total => vehiclePrice + helmetPrice * helmetCount;
  bool get hasPlate => licensePlate.trim().isNotEmpty;
  bool get isInside => exitedAt == null;

  /// Colonnes ajoutées par la migration (à fusionner avec vos colonnes existantes).
  Map<String, Object?> plateColumns() => {
        'license_plate': hasPlate ? licensePlate : null,
        'plate_capture_method': plateCaptureMethod.dbValue,
        'plate_ocr_raw_text': plateOcrRawText,
        'plate_photo_path': platePhotoPath,
        'plate_verified': plateVerified ? 1 : 0,
      };

  Duration stayAt(DateTime now) => (exitedAt ?? now).difference(enteredAt);

  ParkingSession copyWith({int? id, DateTime? exitedAt, String? exitedBy}) => ParkingSession(
        id: id ?? this.id,
        vehicleType: vehicleType,
        ticketBase: ticketBase,
        enteredAt: enteredAt,
        helmetCount: helmetCount,
        vehiclePrice: vehiclePrice,
        helmetPrice: helmetPrice,
        licensePlate: licensePlate,
        plateCaptureMethod: plateCaptureMethod,
        plateVerified: plateVerified,
        plateOcrRawText: plateOcrRawText,
        platePhotoPath: platePhotoPath,
        exitedAt: exitedAt ?? this.exitedAt,
        parkingId: parkingId,
        enteredBy: enteredBy,
        exitedBy: exitedBy ?? this.exitedBy,
      );
}
