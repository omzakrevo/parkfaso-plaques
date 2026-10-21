# PARKFASO — Licences et suivi à distance

## Licences (gérées par GitHub, sans base de données)

**Principe**
- Une licence est un texte signé par OMZAKREVO avec la **clé privée** (fichier
  `parkfaso_cle_privee.txt`, à garder secret et sauvegardé hors ligne).
- L'application vérifie la signature **hors ligne** avec la clé publique intégrée :
  une licence modifiée (nombre de parkings, date) ou inventée est refusée.
- Les licences révoquées sont listées dans `licences/revoquees.json` (ce dépôt).
  Chaque téléphone relit ce fichier une fois par jour quand il a Internet.
- Sans licence : **essai de 7 jours, 1 parking**. Ensuite les entrées sont bloquées
  (l'historique et les exports restent accessibles).

**Créer une licence**
1. Ouvrez la page `docs/licences/index.html` dans Chrome.
   - Soit téléchargez le fichier depuis GitHub et ouvrez-le sur l'ordinateur.
   - Soit activez GitHub Pages (Settings → Pages → Source : *GitHub Actions*) pour l'avoir en ligne.
2. Collez la clé privée (une seule fois si vous cochez « Mémoriser »).
3. Indiquez le client, le nombre de parkings et la durée → **Générer**.
4. Envoyez la licence par WhatsApp (bouton) ou montrez le QR code au client.
5. Dans l'application : **Réglages → Licence → Saisir une licence** (coller ou scanner).

**Révoquer une licence** (non-paiement, téléphone volé…)
- Sur la même page, partie 4 : jeton GitHub « fine-grained » limité à ce dépôt,
  permission *Contents : Read and write*, puis l'ID de la licence → **Révoquer**.
- Ou modifiez directement `licences/revoquees.json` sur GitHub :
  `"revoquees": [{"id": "L20261021-ABC", "motif": "…", "date": "2026-10-21"}]`.

⚠️ Ne publiez jamais la clé privée (ni dans ce dépôt, ni dans une conversation).
Si elle est perdue, plus aucune licence ne peut être créée sans publier une
nouvelle version de l'application avec une nouvelle clé.

## Suivi des parkings à distance (synchronisation GitHub)

1. Créez un dépôt **privé** par client, ex. `omzakrevo/parkfaso-data-client1`.
2. Créez un jeton *Fine-grained* : Repository access → ce dépôt uniquement,
   Permissions → *Contents : Read and write*, expiration 1 an.
3. Sur **chaque téléphone** du client : Réglages → Synchronisation GitHub →
   dépôt + jeton → *Tester et synchroniser*.
4. Le propriétaire configure aussi son propre téléphone : **Rapports → À distance**
   affiche alors tous les parkings (présents, recette du jour et du mois,
   dernières entrées, graphique du mois).

Chaque téléphone écrit uniquement ses propres fichiers (pas de conflit), toutes
les 10 minutes et 20 secondes après chaque entrée. Hors ligne, rien n'est perdu.

## Comptes

- **Administrateur** : tarifs, parkings, comptes, rapports, synchronisation, licence.
- **Gardien** : entrées, sorties, présents, historique, imprimante, son PIN.
- PIN à 4 chiffres, jamais stocké en clair ; 5 erreurs → blocage 30 secondes.
