// PARKFASO — Identification d'un numéro d'immatriculation dans un texte OCR.
//
// Code Dart pur (aucune dépendance Flutter) : testable et exécutable dans un
// isolate. Règle absolue : on ne propose JAMAIS un numéro qui ne correspond
// pas entièrement à un format connu. Un texte incomplet n'est pas « complété ».

import 'dart:math' as math;

/// Une ligne de texte détectée par l'OCR, avec sa position dans l'image.
/// Les coordonnées sont facultatives (tests, saisie, OCR sans géométrie).
class OcrLine {
  const OcrLine(
    this.text, {
    this.left,
    this.top,
    this.width,
    this.height,
    this.confidence,
    this.angle,
  });

  final String text;
  final double? left;
  final double? top;
  final double? width;
  final double? height;
  final double? confidence;

  /// Inclinaison de la ligne en degrés (fournie par ML Kit sur Android).
  final double? angle;

  double? get bottom => (top != null && height != null) ? top! + height! : null;
  double? get right => (left != null && width != null) ? left! + width! : null;
  double? get centerX => (left != null && width != null) ? left! + width! / 2 : null;
}

/// Type de caractère attendu à une position d'un format.
enum _Slot { digit, letter }

/// Un format de plaque : une suite de groupes (chiffres ou lettres) avec un
/// nombre de caractères min/max par groupe. Ex. Burkina standard :
/// 2 chiffres (code région) + 1 à 2 lettres + 3 à 4 chiffres → « 11 AB 2345 ».
class PlateFormat {
  const PlateFormat(this.name, this.groups, {this.fixedPrefix});

  final String name;

  /// Groupes successifs, ex. [PlateGroup.digits(2), PlateGroup.letters(1, 2), PlateGroup.digits(3, 4)].
  final List<PlateGroup> groups;

  /// Préfixe littéral obligatoire (ex. « CD » pour les plaques diplomatiques).
  final String? fixedPrefix;
}

class PlateGroup {
  const PlateGroup._(this._slot, this.min, this.max);
  const PlateGroup.digits(int min, [int? max]) : this._(_Slot.digit, min, max ?? min);
  const PlateGroup.letters(int min, [int? max]) : this._(_Slot.letter, min, max ?? min);

  final _Slot _slot;
  final int min;
  final int max;
}

/// Formats reconnus par défaut. Ajustez cette liste si un parking rencontre
/// d'autres modèles (la liste est injectable dans [PlateParser]).
const List<PlateFormat> kBurkinaPlateFormats = [
  // Format courant : 11 AB 2345 / 11 A 2345 / 11 AB 234
  PlateFormat('BF standard', [
    PlateGroup.digits(2),
    PlateGroup.letters(1, 2),
    PlateGroup.digits(3, 4),
  ]),
  // Variante à 3 lettres rencontrée sur certaines séries.
  PlateFormat('BF 3 lettres', [
    PlateGroup.digits(2),
    PlateGroup.letters(3),
    PlateGroup.digits(3, 4),
  ]),
  // Plaques diplomatiques / corps consulaire : CD 12 345, CC 12 345
  PlateFormat('Diplomatique CD', [PlateGroup.digits(2, 3), PlateGroup.digits(3, 4)],
      fixedPrefix: 'CD'),
  PlateFormat('Consulaire CC', [PlateGroup.digits(2, 3), PlateGroup.digits(3, 4)],
      fixedPrefix: 'CC'),
];

/// Statut d'une tentative de reconnaissance.
enum PlateMatchStatus {
  /// Un numéro complet et cohérent a été trouvé.
  found,

  /// Plusieurs numéros différents plausibles : le gardien doit choisir/corriger.
  ambiguous,

  /// Du texte ressemble à une plaque mais il est incomplet : rien n'est proposé.
  partial,

  /// Aucun texte exploitable.
  notFound,
}

class PlateCandidate {
  const PlateCandidate({
    required this.plate,
    required this.format,
    required this.score,
    required this.corrections,
    required this.source,
  });

  /// Numéro formaté pour l'affichage et l'impression : « 11 AB 2345 ».
  final String plate;
  final String format;

  /// Score entre 0 et 1 (plus haut = plus fiable).
  final double score;

  /// Nombre de caractères corrigés (O→0, I→1, B→8…).
  final int corrections;

  /// Texte OCR d'origine ayant produit ce candidat.
  final String source;

  /// Numéro sans espaces, pour les comparaisons et la base : « 11AB2345 ».
  String get compact => plate.replaceAll(' ', '');

  @override
  String toString() => 'PlateCandidate($plate, $format, score=${score.toStringAsFixed(2)}, '
      'corr=$corrections)';
}

class PlateParseResult {
  const PlateParseResult({
    required this.status,
    required this.candidates,
    required this.rawText,
    this.partialHint,
  });

  final PlateMatchStatus status;

  /// Candidats triés du plus probable au moins probable (vide si rien trouvé).
  final List<PlateCandidate> candidates;

  /// Texte OCR brut (toutes lignes), pour l'affichage temporaire uniquement.
  final String rawText;

  /// Texte lu quand la plaque est incomplète. À afficher comme indice
  /// (« lu : 11 AB 23… ») mais JAMAIS à insérer automatiquement.
  final String? partialHint;

  PlateCandidate? get best => candidates.isEmpty ? null : candidates.first;

  /// Le numéro à pré-remplir, uniquement si la reconnaissance est sûre.
  String? get plateToPrefill =>
      status == PlateMatchStatus.found ? best?.plate : null;
}

/// Analyse le texte OCR et isole le numéro d'immatriculation.
class PlateParser {
  PlateParser({
    this.formats = kBurkinaPlateFormats,
    this.ambiguityMargin = 0.08,
    this.minScore = 0.45,
  });

  final List<PlateFormat> formats;

  /// Écart de score sous lequel deux numéros différents sont jugés ambigus.
  final double ambiguityMargin;

  /// Score minimal pour accepter un candidat.
  final double minScore;

  /// Mots imprimés sur les plaques ou autour, à ignorer.
  static const _noiseWords = <String>{
    'BURKINA', 'FASO', 'BF', 'BFA', 'RBF', 'MOTO', 'YAMAHA', 'HONDA', 'SUZUKI',
    'TVS', 'BAJAJ', 'APSONIC', 'SANILI', 'HAOJUE', 'JAKARTA', 'KTM', 'POLICE',
    'TEL', 'WWW', 'COM', 'GARAGE',
  };

  // Corrections de confusion : vers chiffre, vers lettre.
  static const _toDigit = <String, String>{
    'O': '0', 'Q': '0', 'D': '0', 'U': '0',
    'I': '1', 'L': '1', 'T': '1', 'J': '1', '|': '1', '!': '1',
    'Z': '2',
    'S': '5', '\$': '5',
    'G': '6', 'B': '8', 'A': '4', 'Y': '7',
  };
  static const _toLetter = <String, String>{
    '0': 'O', '1': 'I', '2': 'Z', '4': 'A', '5': 'S', '6': 'G', '7': 'T', '8': 'B',
  };

  /// Normalise un texte : majuscules, accents retirés, séparateurs unifiés.
  static String normalize(String input) {
    const accents = {
      'À': 'A', 'Â': 'A', 'Ä': 'A', 'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
      'Î': 'I', 'Ï': 'I', 'Ô': 'O', 'Ö': 'O', 'Ù': 'U', 'Û': 'U', 'Ü': 'U', 'Ç': 'C',
    };
    final up = input.toUpperCase();
    final b = StringBuffer();
    for (final rune in up.runes) {
      var c = String.fromCharCode(rune);
      c = accents[c] ?? c;
      if (RegExp(r'[A-Z0-9]').hasMatch(c) || c == '|' || c == '!' || c == '\$') {
        b.write(c);
      } else {
        b.write(' '); // tirets, points, puces, espaces multiples → un séparateur
      }
    }
    return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Formate un numéro saisi à la main (« 11ab2345 » → « 11 AB 2345 »).
  /// Retourne null si la saisie ne correspond à aucun format : on garde alors
  /// la saisie telle quelle, normalisée, sans rien inventer.
  String? formatManualEntry(String input) {
    final res = _matchTokens(_tokensWithoutNoise(normalize(input)), input, allowCorrections: false);
    return res.isEmpty ? null : res.first.plate;
  }

  PlateParseResult parse(List<OcrLine> lines) {
    final cleaned = lines.where((l) => l.text.trim().isNotEmpty).toList();
    final raw = cleaned.map((l) => l.text).join('\n');
    if (cleaned.isEmpty) {
      return PlateParseResult(status: PlateMatchStatus.notFound, candidates: const [], rawText: raw);
    }

    final maxHeight = cleaned
        .map((l) => l.height ?? 0)
        .fold<double>(0, (a, b) => math.max(a, b));

    // 1. Groupes de lignes à essayer : chaque ligne, puis lignes empilées
    //    (plaques moto sur deux lignes : « 11 AB » au-dessus de « 2345 »).
    final groups = <List<OcrLine>>[];
    for (final l in cleaned) {
      groups.add([l]);
    }
    final ordered = [...cleaned]..sort((a, b) => (a.top ?? 0).compareTo(b.top ?? 0));
    for (var i = 0; i < ordered.length; i++) {
      for (var j = i + 1; j < ordered.length && j <= i + 2; j++) {
        if (_stacked(ordered[i], ordered[j])) groups.add([ordered[i], ordered[j]]);
      }
    }
    // Lignes sans géométrie : on essaie aussi les paires consécutives.
    if (cleaned.every((l) => l.top == null)) {
      for (var i = 0; i + 1 < cleaned.length; i++) {
        groups.add([cleaned[i], cleaned[i + 1]]);
      }
    }

    final all = <PlateCandidate>[];
    for (final g in groups) {
      final text = g.map((l) => l.text).join(' ');
      final tokens = _tokensWithoutNoise(normalize(text));
      final found = _matchTokens(tokens, text, allowCorrections: true);
      for (final c in found) {
        // Bonus géométrique : grands caractères = texte de la plaque.
        final h = g.map((l) => l.height ?? 0).fold<double>(0, (a, b) => math.max(a, b));
        final sizeBonus = maxHeight > 0 ? 0.25 * (h / maxHeight) : 0.0;
        final conf = g.map((l) => l.confidence).whereType<double>();
        final confBonus = conf.isEmpty ? 0.0 : 0.05 * (conf.reduce(math.min));
        all.add(PlateCandidate(
          plate: c.plate,
          format: c.format,
          score: (c.score + sizeBonus + confBonus).clamp(0.0, 1.0),
          corrections: c.corrections,
          source: text,
        ));
      }
    }

    // 2. Dédoublonnage par numéro (on garde le meilleur score).
    final byPlate = <String, PlateCandidate>{};
    for (final c in all) {
      final prev = byPlate[c.compact];
      if (prev == null || c.score > prev.score) byPlate[c.compact] = c;
    }
    final ranked = byPlate.values.where((c) => c.score >= minScore).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    if (ranked.isEmpty) {
      final hint = _partialHint(cleaned);
      return PlateParseResult(
        status: hint == null ? PlateMatchStatus.notFound : PlateMatchStatus.partial,
        candidates: const [],
        rawText: raw,
        partialHint: hint,
      );
    }

    // Un candidat qui est contenu dans un autre plus long (ex. « 11 AB 234 »
    // dans « 11 AB 2345 ») n'est pas un vrai concurrent.
    final distinct = <PlateCandidate>[];
    for (final c in ranked) {
      final absorbed = distinct.any((d) => d.compact.startsWith(c.compact) || c.compact.startsWith(d.compact));
      if (!absorbed) distinct.add(c);
    }

    final ambiguous = distinct.length > 1 &&
        (distinct[0].score - distinct[1].score) < ambiguityMargin;
    return PlateParseResult(
      status: ambiguous ? PlateMatchStatus.ambiguous : PlateMatchStatus.found,
      candidates: distinct,
      rawText: raw,
    );
  }

  // ---------------------------------------------------------------------------

  bool _stacked(OcrLine a, OcrLine b) {
    if (a.top == null || b.top == null || a.height == null || b.height == null) return false;
    // Même rangée inclinée : b commence là où a finit, légèrement décalé en hauteur.
    if (a.right != null && b.left != null) {
      final hGap = b.left! - a.right!;
      final vShift = (b.top! - a.top!).abs();
      if (hGap > -a.height! && hGap < a.height! * 1.5 && vShift < a.height! * 0.9) return true;
    }
    final gap = b.top! - a.bottom!;
    if (gap < -a.height! * 0.5 || gap > a.height! * 1.2) return false;
    if (a.left == null || b.left == null) return true;
    final overlap = math.min(a.right!, b.right!) - math.max(a.left!, b.left!);
    return overlap > math.min(a.width!, b.width!) * 0.3;
  }

  List<String> _tokensWithoutNoise(String normalized) {
    if (normalized.isEmpty) return const [];
    return normalized.split(' ').where((t) => !_noiseWords.contains(t)).toList();
  }

  /// Essaie chaque format sur la chaîne compacte et sur chaque sous-suite de
  /// jetons, puis renvoie les correspondances.
  List<PlateCandidate> _matchTokens(List<String> tokens, String source,
      {required bool allowCorrections}) {
    final out = <PlateCandidate>[];
    for (var start = 0; start < tokens.length; start++) {
      for (var end = start + 1; end <= tokens.length && end <= start + 4; end++) {
        final slice = tokens.sublist(start, end);
        final compact = slice.join();
        if (compact.length < 5 || compact.length > 11) continue;
        // Une même lecture ne doit produire qu'un candidat : celui qui demande
        // le moins de corrections (sinon « 11 AB 23 » deviendrait « 11 A 823 »).
        PlateCandidate? bestForSlice;
        for (final f in formats) {
          final m = _matchFormat(compact, slice, f, allowCorrections);
          if (m == null) continue;
          if (bestForSlice == null || m.$3 < bestForSlice.corrections ||
              (m.$3 == bestForSlice.corrections && m.$2 > bestForSlice.score)) {
            bestForSlice = PlateCandidate(
                plate: m.$1, format: f.name, score: m.$2, corrections: m.$3, source: source);
          }
        }
        if (bestForSlice != null) out.add(bestForSlice);
      }
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  /// Retourne (plaque formatée, score, nb corrections) ou null.
  (String, double, int)? _matchFormat(
      String compact, List<String> tokens, PlateFormat f, bool allowCorrections) {
    var body = compact;
    var offset = 0;
    if (f.fixedPrefix != null) {
      if (!body.startsWith(f.fixedPrefix!)) return null;
      body = body.substring(f.fixedPrefix!.length);
      offset = f.fixedPrefix!.length;
    }
    // Les espaces lus par l'OCR sont des frontières : un caractère ne peut pas
    // passer d'un bloc à l'autre (« AB 23 » ne devient jamais « A 823 »).
    final boundaries = <int>{};
    var acc = 0;
    for (final t in tokens.take(tokens.length - 1)) {
      acc += t.length;
      if (acc - offset > 0) boundaries.add(acc - offset);
      if (acc - offset < 0) return null;
    }
    if (f.fixedPrefix != null && !boundaries.contains(0) && tokens.first.length != offset &&
        tokens.first.length < offset) {
      return null;
    }
    final best = _assign(body, 0, f.groups, 0, allowCorrections, boundaries);
    if (best == null) return null;
    final (parts, corrections) = best;
    // Pénalités : corrections, et découpage en jetons incohérent avec les groupes.
    var score = 0.70 - corrections * 0.12;
    final expectedTokens = f.groups.length + (f.fixedPrefix != null ? 1 : 0);
    if (tokens.length == expectedTokens) score += 0.05;
    if (tokens.length > expectedTokens + 1) score -= 0.1;
    if (corrections > 2) return null; // trop de doutes : on ne devine pas
    final plate = [if (f.fixedPrefix != null) f.fixedPrefix!, ...parts].join(' ');
    return (plate, score, corrections);
  }

  /// Affecte récursivement les caractères aux groupes en minimisant les corrections.
  (List<String>, int)? _assign(String s, int pos, List<PlateGroup> groups, int gi,
      bool allowCorrections, Set<int> boundaries) {
    if (gi == groups.length) return pos == s.length ? (<String>[], 0) : null;
    final g = groups[gi];
    (List<String>, int)? best;
    for (var len = g.min; len <= g.max; len++) {
      if (pos + len > s.length) break;
      if (boundaries.any((b) => b > pos && b < pos + len)) continue;
      final chunk = s.substring(pos, pos + len);
      final conv = _convert(chunk, g._slot, allowCorrections);
      if (conv == null) continue;
      final rest = _assign(s, pos + len, groups, gi + 1, allowCorrections, boundaries);
      if (rest == null) continue;
      final total = conv.$2 + rest.$2;
      if (best == null || total < best.$2) best = ([conv.$1, ...rest.$1], total);
    }
    return best;
  }

  (String, int)? _convert(String chunk, _Slot slot, bool allowCorrections) {
    // Un groupe de lettres doit contenir au moins une vraie lettre : sinon un
    // numéro de téléphone (« 70123456 ») deviendrait une fausse plaque.
    if (slot == _Slot.letter && !RegExp(r'[A-Z]').hasMatch(chunk)) return null;
    final b = StringBuffer();
    var corrections = 0;
    for (final ch in chunk.split('')) {
      final isDigit = RegExp(r'[0-9]').hasMatch(ch);
      final isLetter = RegExp(r'[A-Z]').hasMatch(ch);
      if (slot == _Slot.digit) {
        if (isDigit) {
          b.write(ch);
        } else if (allowCorrections && _toDigit.containsKey(ch)) {
          b.write(_toDigit[ch]);
          corrections++;
        } else {
          return null;
        }
      } else {
        if (isLetter) {
          b.write(ch);
        } else if (allowCorrections && _toLetter.containsKey(ch)) {
          b.write(_toLetter[ch]);
          corrections++;
        } else {
          return null;
        }
      }
    }
    return (b.toString(), corrections);
  }

  /// Si le texte ressemble au début d'une plaque (ex. « 11 AB 23 »), on
  /// renvoie ce texte comme indice — jamais comme numéro.
  String? _partialHint(List<OcrLine> lines) {
    for (final l in lines) {
      final t = _tokensWithoutNoise(normalize(l.text)).join(' ');
      if (RegExp(r'^\d{2} ?[A-Z0-9]{1,3}( ?\d{0,3})?$').hasMatch(t) ||
          RegExp(r'^[A-Z]{1,3} ?\d{2,4}$').hasMatch(t)) {
        return t;
      }
    }
    return null;
  }
}
