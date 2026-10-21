# PARKFASO — Reconnaissance automatique des immatriculations

Module à ajouter au projet Flutter PARKFASO existant. Il ne supprime ni ne modifie
aucune fonctionnalité : il ajoute un écran « Entrée MOTO », l'OCR des plaques, quatre
colonnes en base et les tickets moto/casque avec le numéro.

Parcours gardien : **MOTO → CASQUE OUI/NON → PHOTO PLAQUE → CONFIRMER → impression automatique.**

---

## 1. Copier les fichiers

| Depuis ce dossier | Vers PARKFASO |
|---|---|
| `lib/plaque/` | `lib/plaque/` |
| `lib/tickets/moto_tickets.dart` | `lib/tickets/moto_tickets.dart` |
| `test/*.dart` | `test/` |
| `integration_test/` | `integration_test/` |
| `android/app/proguard-rules.pro` | `android/app/proguard-rules.pro` (à fusionner si existant) |

Les imports internes sont relatifs : le module fonctionne quel que soit le nom du package.
`lib/main.dart` est une **application de démonstration** : ne la copiez pas.

## 2. Dépendances (`pubspec.yaml`)

```yaml
dependencies:
  camera: ^0.12.1
  google_mlkit_text_recognition: ^0.17.1
  image: ^4.12.0
  path_provider: ^2.1.6
  path: ^1.9.1
  sqflite: ^2.4.4+2        # déjà présent si PARKFASO utilise sqflite

dev_dependencies:
  integration_test:
    sdk: flutter
  sqflite_common_ffi: ^2.4.0
```

Android : `minSdk` **21** minimum (ML Kit). La permission caméra est ajoutée
automatiquement par le plugin `camera`. Le modèle ML Kit « latin » est **embarqué dans
l'APK** : aucune connexion n'est nécessaire, même au premier lancement.

**Build release (important)** : ajoutez dans `android/app/proguard-rules.pro` (fichier fourni)
les règles ML Kit, et référencez-le dans `android/app/build.gradle.kts` :

```kotlin
release {
    proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
}
```

Sans ces règles, R8 échoue sur les classes des écritures chinoise/japonaise/coréenne
que ML Kit référence mais que le module n'utilise pas.

## 3. Brancher les 4 points de raccordement

### a) Bouton « MOTO »

```dart
onPressed: () => Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => MotoEntryScreen(
    settings: MotoEntrySettings(
      parkingName: config.nomParking,      // ex. 'Parking Central'
      motoPrice: config.prixMoto,          // ex. 100
      helmetPrice: config.prixCasque,      // ex. 0
      paperWidth: config.papier80mm ? PaperWidth.mm80 : PaperWidth.mm58,
      allowEmptyPlate: config.plaqueFacultative,
    ),
    ocr: plateOcr,                          // un seul PlateOcrService pour toute l'appli
    repository: SqfliteMotoSessionRepository(db),
    printer: monImprimante,                 // voir c)
    photoStore: PlatePhotoStore(keepPhotos: false, retentionDays: 7),
  ),
)),
```

Créez `final plateOcr = PlateOcrService();` une seule fois (au démarrage) et appelez
`plateOcr.dispose()` à la fermeture : le moteur ML Kit reste chargé, l'analyse est plus rapide.

### b) Base de données

Dans `onUpgrade` (pensez à incrémenter `version`) ou simplement au démarrage :

```dart
await const PlateColumnsMigration(table: 'parking_sessions').apply(db);
```

La migration n'ajoute que les colonnes absentes (`license_plate`, `plate_capture_method`,
`plate_ocr_raw_text`, `plate_photo_path`, `plate_verified`) et ne touche pas aux données.

Si vos colonnes existantes ont d'autres noms, indiquez-les :

```dart
SqfliteMotoSessionRepository(db,
  table: 'sessions',
  columns: const SessionColumns(ticketNumber: 'numero', enteredAt: 'heure_entree',
      helmetCount: 'nb_casques', amount: 'montant', vehicleType: 'type'),
  ticketPrefix: 'PK');
```

Si PARKFASO a déjà son propre dépôt, implémentez simplement `MotoSessionRepository`
(2 méthodes : `nextTicketBase()` et `save()`), en ajoutant `session.plateColumns()` à
votre `insert`.

Supabase (si vos sessions y sont synchronisées) : `supabase_plaques.sql`.

### c) Imprimante

Si votre code d'impression envoie des octets ESC/POS (Bluetooth, USB, réseau) :

```dart
final monImprimante = EscPosBytesPrinter(
  (bytes) => votreConnexionBluetooth.writeBytes(bytes),   // votre fonction existante
  PaperWidth.mm58,
);
```

Sinon, implémentez `TicketPrinter.printTickets(List<TicketDocument>)` et utilisez
`TicketTextRenderer` (lignes déjà mises en page pour 32 ou 48 colonnes) ou
`EscPosTicketEncoder` (octets prêts à envoyer, QR code et coupe inclus).

Tickets produits à la suite : `PK-000125-C` (client), `PK-000125-M` (moto),
`PK-000125-H1`, `-H2`… (un par casque). Le numéro d'immatriculation est sur chacun,
en double taille, et dans le QR code (`PKF1|PK-000125-C|11AB2345|2026-10-21T08:35`).

### d) Réglages du propriétaire (facultatif)

| Réglage | Défaut | Effet |
|---|---|---|
| `allowEmptyPlate` | `false` | Autorise une moto sans numéro (ticket « NON RENSEIGNEE ») |
| `autoPrintAfterConfirm` | `true` | « Confirmer » sur la caméra enregistre et imprime directement |
| `keepPlatePhotos` | `false` | Conserve les photos (dossier privé de l'appli, caché de la galerie) |
| `platePhotoRetentionDays` | `7` | Durée de conservation ; appelez `photoStore.purgeExpired()` au démarrage |
| `keepOcrRawText` | `false` | Garde le texte OCR brut en base (diagnostic) ; purge avec `purgeTemporaryData` |

Consultation des photos conservées : `photoStore.canView(role)` n'autorise que
`proprietaire` et `admin` (modifiable via `allowedRoles`).

## 4. Fiabilité : ce que fait le module

- **Zone de la plaque** : cadre de guidage à l'écran ; l'image est recadrée sur ce cadre
  (+12 % de marge). Si rien n'est trouvé, nouvelle lecture sur l'image entière.
- **Recadrage manuel** : bouton « RECADRER » quand la lecture échoue.
- **Orientation** : EXIF appliqué ; plaque inclinée redressée selon l'angle mesuré par ML Kit.
- **Contraste** : niveaux de gris + étirement automatique si la photo est sombre ou terne.
  Lampe torche disponible sur l'écran caméra.
- **Normalisation** : majuscules, accents, tirets/points supprimés, espaces unifiés → `11 AB 2345`.
- **Formats Burkina** : `11 AB 2345`, `11 A 2345`, `11 AB 234`, 3 lettres, `CD`/`CC`
  (liste `kBurkinaPlateFormats`, extensible). Plaques moto sur deux lignes gérées.
- **Confusions O/0, I/1, B/8** (et S/5, Z/2, G/6) corrigées **selon la position** (chiffres
  ou lettres), au maximum 2 par plaque ; le gardien est prévenu (« 1 caractère corrigé — vérifiez »).
- **Jamais de numéro inventé** : si un caractère manque, rien n'est pré-rempli ; le texte lu
  est seulement montré comme indice. Un numéro de téléphone ne devient jamais une plaque.
  Deux plaques de même taille → le gardien choisit.
- **Interface fluide** : le traitement d'image tourne dans un isolate, ML Kit en natif.

## 5. Tests

```bash
flutter test                                     # 71 tests, sans téléphone
flutter test integration_test/plate_ocr_device_test.dart   # téléphone branché, MODE AVION
```

| Exigence | Où c'est testé |
|---|---|
| Plaque bien éclairée / peu éclairée / inclinée / sale / plusieurs textes / absente | `plate_parser_test`, `plate_ocr_service_test`, test téléphone |
| Erreur de reconnaissance, photo illisible | `plate_ocr_service_test`, `moto_entry_flow_test` |
| Hors ligne | `plate_ocr_service_test` (réseau interdit) + test téléphone en mode avion |
| Tickets 58 mm et 80 mm | `moto_tickets_test` (largeurs, numéro sur chaque ticket, ESC/POS, QR) |
| Base de données | `plate_storage_test` (migration sur table existante, idempotence, purge) |
| Parcours gardien complet | `moto_entry_flow_test` |

Le test téléphone reste indispensable : les tests sans téléphone simulent ML Kit.
Faites aussi un essai réel au parking (soleil, nuit avec lampe, plaques boueuses) avant
de déployer chez un client.
