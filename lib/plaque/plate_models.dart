// PARKFASO — Modèles et réglages liés à l'immatriculation des motos.

/// Comment le numéro a été obtenu (colonne `plate_capture_method`).
enum PlateCaptureMethod {
  /// Lu par la caméra et accepté tel quel par le gardien.
  ocr('OCR'),

  /// Tapé par le gardien, ou numéro OCR corrigé à la main.
  manual('MANUEL'),

  /// Champ laissé vide (si le parking l'autorise).
  none('AUCUN');

  const PlateCaptureMethod(this.dbValue);
  final String dbValue;

  static PlateCaptureMethod fromDb(String? v) =>
      values.firstWhere((m) => m.dbValue == v, orElse: () => PlateCaptureMethod.none);
}

enum PaperWidth {
  mm58(32),
  mm80(48);

  const PaperWidth(this.charsPerLine);

  /// Caractères par ligne en police normale (police A, 12×24).
  final int charsPerLine;
}

/// Réglages du parking pour l'entrée moto. À alimenter depuis la configuration
/// PARKFASO existante (tarifs, nom du parking, imprimante).
class MotoEntrySettings {
  const MotoEntrySettings({
    this.brandName = 'PARKFASO',
    required this.parkingName,
    required this.motoPrice,
    this.helmetPrice = 0,
    this.currency = 'FCFA',
    this.paperWidth = PaperWidth.mm58,
    this.allowEmptyPlate = false,
    this.autoPrintAfterConfirm = true,
    this.maxHelmets = 3,
    this.keepPlatePhotos = false,
    this.platePhotoRetentionDays = 7,
    this.keepOcrRawText = false,
  });

  final String brandName;
  final String parkingName;
  final int motoPrice;

  /// Prix par casque déposé (0 si gratuit).
  final int helmetPrice;
  final String currency;
  final PaperWidth paperWidth;

  /// Le gardien peut-il enregistrer une moto sans numéro ?
  final bool allowEmptyPlate;

  /// « Confirmer » sur l'écran caméra enregistre et imprime directement.
  final bool autoPrintAfterConfirm;
  final int maxHelmets;

  /// Conservation des photos de plaques : désactivée par défaut.
  final bool keepPlatePhotos;
  final int platePhotoRetentionDays;

  /// Conserver le texte OCR brut en base (désactivé : donnée temporaire).
  final bool keepOcrRawText;

  MotoEntrySettings copyWith({
    int? motoPrice,
    int? helmetPrice,
    PaperWidth? paperWidth,
    bool? allowEmptyPlate,
    bool? autoPrintAfterConfirm,
    bool? keepPlatePhotos,
    int? platePhotoRetentionDays,
    bool? keepOcrRawText,
  }) =>
      MotoEntrySettings(
        brandName: brandName,
        parkingName: parkingName,
        motoPrice: motoPrice ?? this.motoPrice,
        helmetPrice: helmetPrice ?? this.helmetPrice,
        currency: currency,
        paperWidth: paperWidth ?? this.paperWidth,
        allowEmptyPlate: allowEmptyPlate ?? this.allowEmptyPlate,
        autoPrintAfterConfirm: autoPrintAfterConfirm ?? this.autoPrintAfterConfirm,
        maxHelmets: maxHelmets,
        keepPlatePhotos: keepPlatePhotos ?? this.keepPlatePhotos,
        platePhotoRetentionDays: platePhotoRetentionDays ?? this.platePhotoRetentionDays,
        keepOcrRawText: keepOcrRawText ?? this.keepOcrRawText,
      );
}

/// Ce que l'écran caméra renvoie au formulaire moto.
class PlateCaptureOutcome {
  const PlateCaptureOutcome({
    required this.plate,
    required this.method,
    required this.verified,
    required this.photoPath,
    this.ocrRawText,
    this.printNow = false,
  });

  final String plate;
  final PlateCaptureMethod method;
  final bool verified;
  final String? photoPath;
  final String? ocrRawText;

  /// Le gardien a confirmé : enregistrer et imprimer sans autre geste.
  final bool printNow;
}

/// Une session de stationnement moto prête à être enregistrée.
class MotoParkingSession {
  const MotoParkingSession({
    this.id,
    required this.ticketBase,
    required this.enteredAt,
    required this.helmetCount,
    required this.motoPrice,
    required this.helmetPrice,
    required this.licensePlate,
    required this.plateCaptureMethod,
    required this.plateVerified,
    this.plateOcrRawText,
    this.platePhotoPath,
  });

  final int? id;

  /// Numéro de base du ticket, ex. « PK-000125 » (suffixes -C, -M, -H1…).
  final String ticketBase;
  final DateTime enteredAt;
  final int helmetCount;
  final int motoPrice;

  /// Prix unitaire d'un casque.
  final int helmetPrice;

  /// Numéro validé, ex. « 11 AB 2345 ». Vide si non renseigné.
  final String licensePlate;
  final PlateCaptureMethod plateCaptureMethod;
  final bool plateVerified;
  final String? plateOcrRawText;
  final String? platePhotoPath;

  int get total => motoPrice + helmetPrice * helmetCount;
  bool get hasPlate => licensePlate.trim().isNotEmpty;

  /// Colonnes ajoutées par la migration (à fusionner avec vos colonnes existantes).
  Map<String, Object?> plateColumns() => {
        'license_plate': hasPlate ? licensePlate : null,
        'plate_capture_method': plateCaptureMethod.dbValue,
        'plate_ocr_raw_text': plateOcrRawText,
        'plate_photo_path': platePhotoPath,
        'plate_verified': plateVerified ? 1 : 0,
      };

  MotoParkingSession copyWith({int? id, String? platePhotoPath, String? plateOcrRawText}) =>
      MotoParkingSession(
        id: id ?? this.id,
        ticketBase: ticketBase,
        enteredAt: enteredAt,
        helmetCount: helmetCount,
        motoPrice: motoPrice,
        helmetPrice: helmetPrice,
        licensePlate: licensePlate,
        plateCaptureMethod: plateCaptureMethod,
        plateVerified: plateVerified,
        plateOcrRawText: plateOcrRawText ?? this.plateOcrRawText,
        platePhotoPath: platePhotoPath ?? this.platePhotoPath,
      );
}
