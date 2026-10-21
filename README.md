# PARKFASO — Gestion de parkings

Application Android (Flutter) pour gardiens et propriétaires de parkings :

- Entrée des véhicules (moto, voiture, tricycle, vélo), lecture des plaques par la caméra (hors ligne)
- Tickets thermiques Bluetooth avec QR code (ticket client automatique, ticket véhicule au choix)
- Scan des tickets à la sortie, véhicules présents, historique filtrable, recherche de plaque
- Export PDF et Excel, rapports de chiffre d'affaires par jour et par mois
- Plusieurs parkings, suivi à distance via GitHub, comptes administrateur / gardien (PIN)
- Licences signées gérées par GitHub (voir [LICENCES.md](LICENCES.md))

**Télécharger l'APK** : [dernière version](https://github.com/omzakrevo/parkfaso-plaques/releases/tag/derniere-version)
(compilée automatiquement à chaque modification).

Développement : `flutter pub get && flutter test`. Détails techniques : [INTEGRATION.md](INTEGRATION.md).
