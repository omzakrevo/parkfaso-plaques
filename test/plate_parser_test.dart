import 'package:flutter_test/flutter_test.dart';
import 'package:parkfaso_plaque/plaque/plate_parser.dart';

/// Chaque scénario reproduit ce que ML Kit renvoie réellement dans la
/// situation décrite (lignes + positions). Les textes viennent de cas typiques
/// de plaques burkinabè photographiées au parking.
void main() {
  final parser = PlateParser();

  group('Plaque bien éclairée', () {
    test('une ligne nette', () {
      final r = parser.parse([const OcrLine('11 AB 2345', top: 100, height: 60)]);
      expect(r.status, PlateMatchStatus.found);
      expect(r.plateToPrefill, '11 AB 2345');
      expect(r.best!.corrections, 0);
    });

    test('mentions BURKINA FASO / BF autour du numéro', () {
      final r = parser.parse(const [
        OcrLine('BURKINA FASO', left: 40, top: 10, width: 200, height: 18),
        OcrLine('11 GA 0457', left: 20, top: 40, width: 260, height: 60),
        OcrLine('BF', left: 280, top: 40, width: 30, height: 20),
      ]);
      expect(r.plateToPrefill, '11 GA 0457');
    });

    test('plaque moto carrée sur deux lignes', () {
      final r = parser.parse(const [
        OcrLine('11 AB', left: 40, top: 20, width: 160, height: 55),
        OcrLine('2345', left: 50, top: 85, width: 150, height: 55),
      ]);
      expect(r.status, PlateMatchStatus.found);
      expect(r.plateToPrefill, '11 AB 2345');
    });

    test('variantes 1 lettre et 3 chiffres', () {
      expect(parser.parse([const OcrLine('09 K 1234')]).plateToPrefill, '09 K 1234');
      expect(parser.parse([const OcrLine('11 AB 234')]).plateToPrefill, '11 AB 234');
    });

    test('plaque diplomatique', () {
      expect(parser.parse([const OcrLine('CD 12 345')]).plateToPrefill, 'CD 12 345');
    });
  });

  group('Plaque peu éclairée (caractères confondus)', () {
    test('O/0 dans la partie chiffres', () {
      final r = parser.parse([const OcrLine('11 AB 2O45')]);
      expect(r.plateToPrefill, '11 AB 2045');
      expect(r.best!.corrections, 1);
    });

    test('I/1 dans le code région', () {
      expect(parser.parse([const OcrLine('I1 AB 2345')]).plateToPrefill, '11 AB 2345');
    });

    test('B/8 : 8 lu dans les lettres, B lu dans les chiffres', () {
      expect(parser.parse([const OcrLine('11 A8 2345')]).plateToPrefill, '11 AB 2345');
      expect(parser.parse([const OcrLine('11 AB 234B')]).plateToPrefill, '11 AB 2348');
    });

    test('0 lu à la place de O dans les lettres', () {
      expect(parser.parse([const OcrLine('11 0A 1234')]).plateToPrefill, '11 OA 1234');
    });

    test('trop de doutes : aucun numéro proposé', () {
      final r = parser.parse([const OcrLine('IO 8B ZSOB')]);
      expect(r.plateToPrefill, isNull);
    });
  });

  group('Plaque inclinée', () {
    test('ML Kit coupe la ligne en morceaux décalés', () {
      final r = parser.parse(const [
        OcrLine('11 AB', left: 10, top: 40, width: 120, height: 50),
        OcrLine('2345', left: 120, top: 70, width: 110, height: 50),
      ]);
      expect(r.plateToPrefill, '11 AB 2345');
    });

    test('séparateurs parasites (tirets, points)', () {
      expect(parser.parse([const OcrLine('11-AB.2345')]).plateToPrefill, '11 AB 2345');
      expect(parser.parse([const OcrLine('11AB2345')]).plateToPrefill, '11 AB 2345');
    });
  });

  group('Plaque sale ou partiellement effacée', () {
    test('dernier chiffre illisible : rien n\'est inventé', () {
      final r = parser.parse([const OcrLine('11 AB 23')]);
      expect(r.plateToPrefill, isNull);
      expect(r.status, PlateMatchStatus.partial);
      expect(r.partialHint, '11 AB 23');
    });

    test('lettres effacées : rien n\'est inventé', () {
      final r = parser.parse([const OcrLine('11 2345')]);
      expect(r.plateToPrefill, isNull);
    });
  });

  group('Plusieurs textes dans l\'image', () {
    test('numéro de téléphone et marque ignorés', () {
      final r = parser.parse(const [
        OcrLine('YAMAHA', left: 0, top: 0, width: 100, height: 20),
        OcrLine('TEL 70 12 34 56', left: 0, top: 200, width: 200, height: 18),
        OcrLine('11 JK 7788', left: 30, top: 80, width: 240, height: 64),
      ]);
      expect(r.status, PlateMatchStatus.found);
      expect(r.plateToPrefill, '11 JK 7788');
    });

    test('un numéro de téléphone seul ne devient pas une plaque', () {
      final r = parser.parse([const OcrLine('70123456')]);
      expect(r.plateToPrefill, isNull);
    });

    test('deux plaques de même taille : ambigu, le gardien choisit', () {
      final r = parser.parse(const [
        OcrLine('11 AB 2345', left: 0, top: 0, width: 200, height: 60),
        OcrLine('03 CD 9876', left: 0, top: 300, width: 200, height: 60),
      ]);
      expect(r.status, PlateMatchStatus.ambiguous);
      expect(r.plateToPrefill, isNull);
      expect(r.candidates.map((c) => c.plate),
          containsAll(['11 AB 2345', '03 CD 9876']));
    });

    test('la grande plaque l\'emporte sur un petit autocollant', () {
      final r = parser.parse(const [
        OcrLine('11 AB 2345', left: 0, top: 0, width: 260, height: 70),
        OcrLine('03 CD 9876', left: 0, top: 300, width: 80, height: 14),
      ]);
      expect(r.status, PlateMatchStatus.found);
      expect(r.plateToPrefill, '11 AB 2345');
    });
  });

  group('Absence de plaque / erreur', () {
    test('aucun texte', () {
      final r = parser.parse(const []);
      expect(r.status, PlateMatchStatus.notFound);
      expect(r.plateToPrefill, isNull);
    });

    test('texte sans rapport', () {
      final r = parser.parse([const OcrLine('PARKING CENTRAL'), const OcrLine('ENTREE')]);
      expect(r.status, PlateMatchStatus.notFound);
    });
  });

  group('Saisie manuelle', () {
    test('mise en forme sans correction automatique', () {
      expect(parser.formatManualEntry('11ab2345'), '11 AB 2345');
      expect(parser.formatManualEntry(' 11 ab  2345 '), '11 AB 2345');
      expect(parser.formatManualEntry('11AB23'), isNull);
    });

    test('normalisation', () {
      expect(PlateParser.normalize('  11-ab.2345 '), '11 AB 2345');
      expect(PlateParser.normalize('é'), 'E');
    });
  });
}
