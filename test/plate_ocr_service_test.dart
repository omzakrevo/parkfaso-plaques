import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:parkfaso_plaque/plaque/plate_image_preprocessor.dart';
import 'package:parkfaso_plaque/plaque/plate_ocr_service.dart';
import 'package:parkfaso_plaque/plaque/plate_parser.dart';

import '../integration_test/plate_images.dart';

/// Moteur OCR simulé : renvoie, pour chaque passe, la réponse prévue.
class ScriptedEngine implements TextRecognitionEngine {
  ScriptedEngine(this.responses);

  final List<List<OcrLine>> responses;
  final seenPaths = <String>[];
  final seenSizes = <(int, int)>[];
  int calls = 0;

  @override
  Future<List<OcrLine>> recognize(String imagePath) async {
    seenPaths.add(imagePath);
    final decoded = img.decodeJpg(File(imagePath).readAsBytesSync())!;
    seenSizes.add((decoded.width, decoded.height));
    final r = calls < responses.length ? responses[calls] : const <OcrLine>[];
    calls++;
    return r;
  }

  @override
  Future<void> close() async {}
}

class ThrowingEngine implements TextRecognitionEngine {
  @override
  Future<List<OcrLine>> recognize(String imagePath) => throw StateError('moteur indisponible');
  @override
  Future<void> close() async {}
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pk_ocr_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String photo(PlateScene scene) {
    final f = File('${tmp.path}/${scene.name}.jpg')..writeAsBytesSync(buildPlateJpeg(scene));
    return f.path;
  }

  group('Prétraitement de l\'image', () {
    test('recadrage sur le cadre de guidage (+ marge)', () {
      final out = PlateImagePreprocessor.processBytes(
          buildPlateJpeg(PlateScene.wellLit), const PreprocessOptions());
      // cadre 80 % × 40 % de 720×960, + 12 % de marge
      expect(out.$2.width, closeTo(720 * 0.8 * 1.24, 3));
      expect(out.$2.height, closeTo(960 * 0.4 * 1.24, 3));
    });

    test('plaque peu éclairée : contraste étiré', () {
      final dark = PlateImagePreprocessor.processBytes(
          buildPlateJpeg(PlateScene.dark), const PreprocessOptions());
      expect(dark.$4, isTrue, reason: 'le contraste doit être amélioré');
      // Après étirement, la plaque blanche redevient claire : forte dynamique.
      final lum = [for (final p in dark.$2) p.luminance];
      lum.sort();
      expect(lum[(lum.length * 0.98).floor()] - lum[(lum.length * 0.02).floor()], greaterThan(180));
    });

    test('orientation EXIF appliquée (photo prise en paysage)', () {
      final landscape = img.Image(width: 400, height: 300);
      landscape.exif.imageIfd.orientation = 6; // rotation de 90°
      final bytes = Uint8List.fromList(img.encodeJpg(landscape));
      final out = PlateImagePreprocessor.processBytes(bytes,
          const PreprocessOptions(crop: NormalizedRect.full, cropMargin: 0, enhance: false));
      expect((out.$2.width, out.$2.height), (300, 400));
    });

    test('réduction des grandes photos pour la vitesse', () {
      final big = img.Image(width: 4000, height: 3000);
      final out = PlateImagePreprocessor.processBytes(Uint8List.fromList(img.encodeJpg(big)),
          const PreprocessOptions(crop: NormalizedRect.full, cropMargin: 0));
      expect(out.$2.width, 1600);
    });

    test('photo corrompue → erreur claire', () {
      expect(() => PlateImagePreprocessor.processBytes(Uint8List.fromList([1, 2, 3]), const PreprocessOptions()),
          throwsFormatException);
    });
  });

  group('Service OCR', () {
    test('plaque lisible : une seule passe, numéro trouvé', () async {
      final engine = ScriptedEngine([
        [const OcrLine('11 AB 2345', top: 40, height: 90)],
      ]);
      final svc = PlateOcrService(engine: engine, workDir: tmp);
      final r = await svc.recognize(photo(PlateScene.wellLit));
      expect(r.plate, '11 AB 2345');
      expect(r.passes, 1);
      expect(r.error, isNull);
    });

    test('plaque inclinée : redressement selon l\'angle puis nouvelle lecture', () async {
      final engine = ScriptedEngine([
        [const OcrLine('11 A', angle: 12), const OcrLine('5 2', angle: 13)],
        [const OcrLine('11 AB 2345', angle: 0.5)],
      ]);
      final svc = PlateOcrService(engine: engine, workDir: tmp);
      final r = await svc.recognize(photo(PlateScene.tilted));
      expect(r.plate, '11 AB 2345');
      expect(r.passes, 2);
    });

    test('plaque hors du cadre : la passe image entière la retrouve', () async {
      final engine = ScriptedEngine([
        const [],
        [const OcrLine('BURKINA FASO'), const OcrLine('03 CD 9876')],
      ]);
      final svc = PlateOcrService(engine: engine, workDir: tmp);
      final r = await svc.recognize(photo(PlateScene.wellLit));
      expect(r.plate, '03 CD 9876');
      expect(r.passes, 2);
      // La passe 2 travaille sur l'image entière (720 de large), pas le recadrage.
      expect(engine.seenSizes.last.$1, 720);
    });

    test('absence de plaque : aucun numéro, statut « non trouvé »', () async {
      final svc = PlateOcrService(engine: ScriptedEngine([const [], const []]), workDir: tmp);
      final r = await svc.recognize(photo(PlateScene.noPlate));
      expect(r.plate, isNull);
      expect(r.status, PlateMatchStatus.notFound);
      expect(r.failed, isTrue);
    });

    test('plaque sale : texte incomplet, rien n\'est inventé', () async {
      final svc = PlateOcrService(
          engine: ScriptedEngine([[const OcrLine('11 AB 23')], [const OcrLine('11 AB 23')]]),
          workDir: tmp);
      final r = await svc.recognize(photo(PlateScene.dirty));
      expect(r.plate, isNull);
      expect(r.status, PlateMatchStatus.partial);
      expect(r.parse.partialHint, '11 AB 23');
    });

    test('erreur de reconnaissance : message lisible, pas de plantage', () async {
      final svc = PlateOcrService(engine: ThrowingEngine(), workDir: tmp);
      final r = await svc.recognize(photo(PlateScene.wellLit));
      expect(r.plate, isNull);
      expect(r.error, contains('Reprenez la photo'));
    });

    test('photo illisible : message lisible', () async {
      final bad = File('${tmp.path}/bad.jpg')..writeAsBytesSync([0, 1, 2]);
      final svc = PlateOcrService(engine: ScriptedEngine([]), workDir: tmp);
      final r = await svc.recognize(bad.path);
      expect(r.error, 'Photo illisible. Reprenez la photo.');
    });

    test('fichiers temporaires supprimés, photo d\'origine conservée', () async {
      final engine = ScriptedEngine([const [], const []]);
      final svc = PlateOcrService(engine: engine, workDir: tmp);
      final src = photo(PlateScene.wellLit);
      await svc.recognize(src);
      for (final pth in engine.seenPaths) {
        expect(File(pth).existsSync(), isFalse);
      }
      expect(File(src).existsSync(), isTrue);
    });

    test('fonctionnement hors ligne : aucune connexion réseau utilisée', () async {
      await HttpOverrides.runZoned(() async {
        final svc = PlateOcrService(
            engine: ScriptedEngine([[const OcrLine('11 AB 2345')]]), workDir: tmp);
        final r = await svc.recognize(photo(PlateScene.wellLit));
        expect(r.plate, '11 AB 2345');
      }, createHttpClient: (c) => throw StateError('Réseau interdit'));
    });
  });
}
