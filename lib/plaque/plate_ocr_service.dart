// PARKFASO — Service de reconnaissance de plaque (100 % hors ligne sur Android).
//
// ML Kit « text-recognition » (script latin) embarque son modèle dans l'APK :
// aucune connexion n'est nécessaire, ni au premier lancement ni ensuite.

import 'dart:io';
import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;

import 'plate_image_preprocessor.dart';
import 'plate_parser.dart';

/// Moteur OCR abstrait : ML Kit en production, faux moteur dans les tests.
abstract class TextRecognitionEngine {
  Future<List<OcrLine>> recognize(String imagePath);
  Future<void> close();
}

/// Moteur ML Kit, sur l'appareil, sans réseau.
class MlKitTextEngine implements TextRecognitionEngine {
  MlKitTextEngine() : _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  @override
  Future<List<OcrLine>> recognize(String imagePath) async {
    final result = await _recognizer.processImage(InputImage.fromFilePath(imagePath));
    return [
      for (final block in result.blocks)
        for (final line in block.lines)
          OcrLine(
            line.text,
            left: line.boundingBox.left,
            top: line.boundingBox.top,
            width: line.boundingBox.width,
            height: line.boundingBox.height,
            confidence: line.confidence,
            angle: line.angle,
          ),
    ];
  }

  @override
  Future<void> close() => _recognizer.close();
}

/// Résultat présenté au gardien.
class PlateRecognitionResult {
  const PlateRecognitionResult({
    required this.parse,
    required this.photoPath,
    required this.elapsed,
    required this.passes,
    this.error,
  });

  final PlateParseResult parse;

  /// Photo d'origine (supprimée par défaut après validation, voir PlatePhotoStore).
  final String photoPath;
  final Duration elapsed;

  /// Nombre de passes OCR effectuées (1 si plaque lisible du premier coup).
  final int passes;

  /// Erreur technique éventuelle (photo illisible, moteur indisponible…).
  final String? error;

  PlateMatchStatus get status => parse.status;
  String? get plate => parse.plateToPrefill;
  bool get failed => error != null || parse.plateToPrefill == null;
}

/// Orchestration : prétraitement → OCR → analyse, avec passes de secours.
class PlateOcrService {
  PlateOcrService({
    TextRecognitionEngine? engine,
    PlateParser? parser,
    PlateImagePreprocessor preprocessor = const PlateImagePreprocessor(),
    Directory? workDir,
  })  : _engine = engine ?? MlKitTextEngine(),
        _parser = parser ?? PlateParser(),
        _pre = preprocessor,
        _workDir = workDir; // ignore: prefer_initializing_formals

  final TextRecognitionEngine _engine;
  final PlateParser _parser;
  final PlateImagePreprocessor _pre;
  final Directory? _workDir;

  PlateParser get parser => _parser;

  /// Analyse une photo. [crop] : zone choisie à la main (recadrage manuel) ;
  /// par défaut, le cadre de guidage de l'écran caméra.
  Future<PlateRecognitionResult> recognize(String photoPath,
      {NormalizedRect crop = NormalizedRect.guide}) async {
    final sw = Stopwatch()..start();
    final dir = _workDir ?? Directory.systemTemp;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final temp = <String>[];
    String tmp(String name) {
      final path = p.join(dir.path, 'plaque_${stamp}_$name.jpg');
      temp.add(path);
      return path;
    }

    var passes = 0;
    PlateParseResult? best;
    List<OcrLine> allLines = [];
    try {
      // Passe 1 : zone du cadre, contraste amélioré. Cas normal, la plus rapide.
      final cropped = await _pre.process(photoPath, tmp('cadre'),
          PreprocessOptions(crop: crop, enhance: true));
      var lines = await _engine.recognize(cropped.path);
      passes++;
      allLines = lines;
      best = _parser.parse(lines);
      if (best.status == PlateMatchStatus.found) return _done(best, photoPath, sw, passes);

      // Passe 2 : plaque inclinée → redressement selon l'angle lu par ML Kit.
      {
        final angles = lines.map((l) => l.angle).whereType<double>().toList();
        if (angles.isNotEmpty) {
          angles.sort();
          final median = angles[angles.length ~/ 2];
          if (median.abs() > 6 && median.abs() < 60) {
            final straight = await _pre.process(photoPath, tmp('redresse'),
                PreprocessOptions(crop: crop, rotateDegrees: -median));
            lines = await _engine.recognize(straight.path);
            passes++;
            best = _pick(best, _parser.parse(lines));
            if (best.status == PlateMatchStatus.found) return _done(best, photoPath, sw, passes);
          }
        }
      }

      // Passe 3 : plaque hors du cadre → image entière, couleurs d'origine.
      final whole = await _pre.process(photoPath, tmp('entiere'),
          const PreprocessOptions(crop: NormalizedRect.full, cropMargin: 0, enhance: false));
      lines = await _engine.recognize(whole.path);
      passes++;
      allLines = [...allLines, ...lines];
      best = _pick(best, _parser.parse(lines));
      return _done(best, photoPath, sw, passes);
    } catch (e) {
      return PlateRecognitionResult(
        parse: best ??
            PlateParseResult(
              status: PlateMatchStatus.notFound,
              candidates: const [],
              rawText: allLines.map((l) => l.text).join('\n'),
            ),
        photoPath: photoPath,
        elapsed: sw.elapsed,
        passes: passes,
        error: _humanError(e),
      );
    } finally {
      for (final t in temp) {
        try {
          File(t).deleteSync();
        } catch (_) {}
      }
    }
  }

  PlateRecognitionResult _done(
          PlateParseResult r, String photo, Stopwatch sw, int passes) =>
      PlateRecognitionResult(parse: r, photoPath: photo, elapsed: sw.elapsed, passes: passes);

  /// Garde le résultat le plus exploitable entre deux passes.
  PlateParseResult _pick(PlateParseResult a, PlateParseResult b) {
    int rank(PlateParseResult r) => switch (r.status) {
          PlateMatchStatus.found => 3,
          PlateMatchStatus.ambiguous => 2,
          PlateMatchStatus.partial => 1,
          PlateMatchStatus.notFound => 0,
        };
    if (rank(b) != rank(a)) return rank(b) > rank(a) ? b : a;
    final sa = a.best?.score ?? 0, sb = b.best?.score ?? 0;
    return math.max(sa, sb) == sb ? b : a;
  }

  String _humanError(Object e) {
    if (e is FormatException) return 'Photo illisible. Reprenez la photo.';
    return 'La reconnaissance a échoué. Reprenez la photo ou saisissez le numéro.';
  }

  Future<void> dispose() => _engine.close();
}
