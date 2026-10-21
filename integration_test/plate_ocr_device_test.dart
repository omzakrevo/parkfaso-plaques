// Test sur téléphone Android : vrai moteur ML Kit, sans Internet.
//
//   1. Branchez le téléphone (débogage USB), activez le MODE AVION.
//   2. flutter test integration_test/plate_ocr_device_test.dart
//
// Les photos sont générées (plaque bien éclairée, sombre, inclinée, sale,
// textes multiples, sans plaque, plaque sur deux lignes) puis analysées par le
// même service que l'application.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:parkfaso_plaque/plaque/plate_ocr_service.dart';

import 'plate_images.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late PlateOcrService ocr;
  late Directory tmp;
  setUpAll(() {
    ocr = PlateOcrService(); // ML Kit réel
    tmp = Directory.systemTemp.createTempSync('pk_device_');
  });
  tearDownAll(() async {
    await ocr.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<PlateRecognitionResult> run(PlateScene scene) async {
    final f = File('${tmp.path}/${scene.name}.jpg')..writeAsBytesSync(buildPlateJpeg(scene));
    final r = await ocr.recognize(f.path);
    // ignore: avoid_print
    print('${scene.name.padRight(14)} → ${r.plate ?? '(aucun)'}  statut=${r.status.name} '
        'passes=${r.passes} ${r.elapsed.inMilliseconds} ms  brut="${r.parse.rawText.replaceAll('\n', ' | ')}"');
    return r;
  }

  for (final scene in [
    PlateScene.wellLit,
    PlateScene.dark,
    PlateScene.tilted,
    PlateScene.multipleTexts,
    PlateScene.twoLines,
  ]) {
    test('${scene.name} : numéro lu correctement', () async {
      final r = await run(scene);
      expect(r.plate, '11 AB 2345');
    });
  }

  test('plaque lisible : analyse en moins de 2 secondes', () async {
    final r = await run(PlateScene.wellLit);
    expect(r.elapsed.inMilliseconds, lessThan(2000));
  });

  test('plaque sale / effacée : jamais un numéro faux', () async {
    final r = await run(PlateScene.dirty);
    expect(r.plate, anyOf(isNull, '11 AB 2345'));
  });

  test('absence de plaque : aucun numéro', () async {
    final r = await run(PlateScene.noPlate);
    expect(r.plate, isNull);
  });

  test('hors ligne : aucune connexion n\'est nécessaire', () async {
    // En mode avion, toute requête échoue : ML Kit fonctionne quand même.
    final online = await _hasInternet();
    // ignore: avoid_print
    print(online ? 'ATTENTION : Internet actif, activez le mode avion pour ce test.'
        : 'Mode hors ligne confirmé.');
    final r = await run(PlateScene.wellLit);
    expect(r.plate, '11 AB 2345');
  });
}

Future<bool> _hasInternet() async {
  try {
    final r = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
    return r.isNotEmpty;
  } catch (_) {
    return false;
  }
}
