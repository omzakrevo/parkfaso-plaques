# PARKFASO — Entrées, plaques, tickets Bluetooth et scan de sortie

Application gardien Flutter (Android) prête à l'emploi, et modules à reprendre dans le
projet PARKFASO existant.

**Entrée :** choix du véhicule → casques → photo de la plaque (facultative) → le
**ticket client sort automatiquement** → le gardien **décide** d'imprimer ou non le
ticket véhicule et les tickets casque.

**Sortie :** scan du QR code du ticket → plaque, durée, montant payé → **valider la sortie**.

---

## 1. Ce que fait l'application

| Fonction | Détail |
|---|---|
| Véhicules | Moto, voiture, tricycle, vélo — prix par type (`ParkingSettings.prices`) |
| Casques | Moto et tricycle : « Aucun / 1 / 2 / 3 » en un seul geste |
| Immatriculation | **Facultative** par défaut (`allowEmptyPlate: true`), lue par la caméra hors ligne, ou tapée. Pas de champ pour le vélo |
| Impression phase 1 | Ticket client imprimé dès l'enregistrement (ou dès « Confirmer et imprimer » sur l'écran caméra) |
| Impression phase 2 | Ticket véhicule et tickets casque cochés par défaut : le gardien imprime, décoche, ou « Terminer » sans imprimer |
| Tickets | Courts : 6 à 8 lignes + QR code natif ESC/POS, 58 mm et 80 mm |
| Imprimante | Bluetooth (MTP-II, Goojprt, Xprinter, Rongta…), mémorisée, reconnexion automatique, ticket de test |
| Scan | QR du ticket client, véhicule ou casque ; saisie du n° possible ; alerte ticket déjà utilisé, plaque modifiée, ticket inconnu |

Tickets produits : `PK-000125-C` (client), `-M`/`-V`/`-T`/`-B` (moto/voiture/tricycle/vélo),
`-H1`, `-H2`… (casques). QR : `PKF1|PK-000125-C|11AB2345|2026-10-21T08:35`.

Exemple (58 mm) :

```
   PARKFASO - PARKING CENTRAL
--------------------------------
TICKET CLIENT        PK-000125-C
MOTO            21/10/2026 08:35
   11 AB 2345        (double taille)
CASQUE: 1         TOTAL 100 FCFA
           [QR CODE]
      CONSERVEZ CE TICKET
```

## 2. Imprimante Bluetooth : mise en route

1. Allumez l'imprimante, appairez-la dans **Réglages Bluetooth du téléphone** (code 0000 ou 1234).
2. Dans PARKFASO, touchez l'icône imprimante (en haut à droite) → choisissez-la dans la liste.
3. Choisissez le papier (58 ou 80 mm) → « Imprimer un ticket de test ».

La pastille sur l'icône indique l'état : verte = connectée, grise = se reconnectera à la
prochaine impression, rouge = aucune imprimante. Android demande l'autorisation
« Appareils à proximité » la première fois.

## 3. Reprendre les modules dans PARKFASO

| Dossier | Rôle |
|---|---|
| `lib/app/` | Thème compact, écran d'accueil (choix véhicule, scan, imprimante) |
| `lib/plaque/` | Écran d'entrée, OCR des plaques, base de données, photos |
| `lib/tickets/` | Tickets, imprimante Bluetooth, réglages imprimante, scan |
| `android/app/proguard-rules.pro` | Règles R8 ML Kit (obligatoire en release) |

Les imports sont relatifs : le code fonctionne quel que soit le nom du package.

**Dépendances** (`pubspec.yaml`) : `camera`, `google_mlkit_text_recognition`, `image`,
`mobile_scanner`, `print_bluetooth_thermal`, `shared_preferences`, `path_provider`,
`path`, `sqflite` (+ `sqflite_common_ffi` et `integration_test` en dev). Flutter 3.32 ou plus récent.

**Démarrage** : voir `lib/main.dart` — ouvrir la base, `PlateColumnsMigration().apply(db)`,
`printer.load()`, puis afficher `ParkHomeScreen`. Si PARKFASO a déjà son accueil,
ouvrez directement `VehicleEntryScreen(vehicleType: VehicleType.moto, …)` depuis vos
boutons, et `TicketScanScreen` pour la sortie.

**Base de données** : la migration ajoute uniquement les colonnes absentes
(`license_plate`, `plate_capture_method`, `plate_ocr_raw_text`, `plate_photo_path`,
`plate_verified`, `exited_at`), sans toucher aux données. Noms de colonnes différents :
`SqfliteSessionRepository(db, table: …, columns: SessionColumns(…))`. Dépôt existant :
implémentez `SessionRepository` (4 méthodes). Supabase : `supabase_plaques.sql`.

**Release Android** : `proguard-rules.pro` référencé dans `android/app/build.gradle.kts` :

```kotlin
release {
    proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
}
```

## 4. Réglages (`ParkingSettings`)

| Réglage | Défaut | Effet |
|---|---|---|
| `prices` | moto 100, voiture 300, tricycle 200, vélo 50 | Tarif par type |
| `helmetPrice` | 0 | Prix par casque (« Gratuit » si 0) |
| `allowEmptyPlate` | `true` | Immatriculation facultative |
| `enabledVehicles` | tous | Types affichés à l'accueil |
| `keepPlatePhotos` | `false` | Conserver les photos (dossier privé, caché de la galerie) |
| `platePhotoRetentionDays` | 7 | Durée de conservation |
| `keepOcrRawText` | `false` | Garder le texte OCR brut en base |

## 5. Reconnaissance des plaques

Cadre de guidage, recadrage manuel, redressement des plaques inclinées, contraste
automatique, lampe torche, formats burkinabè (`kBurkinaPlateFormats`, extensible),
plaques sur deux lignes, corrections O/0, I/1, B/8 selon la position. **Aucun numéro
inventé** : une lecture incomplète n'est jamais pré-remplie. Modèles ML Kit (texte et QR)
embarqués : tout fonctionne en mode avion.

## 6. Tests

```bash
flutter test                                                # 88 tests, sans téléphone
flutter test integration_test/plate_ocr_device_test.dart    # téléphone branché, MODE AVION
```

| Fichier | Couvre |
|---|---|
| `plate_parser_test` | Plaques nettes, sombres, inclinées, sales, textes multiples, absentes |
| `plate_ocr_service_test` | Prétraitement, passes de secours, erreurs, hors ligne |
| `tickets_test` | Tickets courts 58/80 mm, ESC/POS, QR et sa relecture |
| `bluetooth_printer_test` | Choix, mémorisation, reconnexion, coupure, Bluetooth désactivé |
| `plate_storage_test` | Migration, sortie, photos |
| `app_flow_test` | Parcours complets : entrée par type, 2 phases d'impression, scan de sortie |

Les tests sans téléphone simulent la caméra, ML Kit et l'imprimante : faites un essai
réel (vraie imprimante, vraies plaques) avant de livrer.
