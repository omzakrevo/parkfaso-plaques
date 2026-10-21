// PARKFASO — Préparation de la photo avant OCR.
//
// Tout le travail se fait hors du thread de l'interface (Isolate.run) :
// l'écran caméra reste fluide pendant l'analyse.

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Rectangle exprimé en fractions de l'image (0..1), indépendant de la résolution.
class NormalizedRect {
  const NormalizedRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  /// Cadre de guidage affiché à l'écran : large bandeau centré, au format d'une
  /// plaque arrière de moto (un peu plus haute que large pour les plaques carrées).
  static const guide = NormalizedRect(0.10, 0.30, 0.80, 0.40);

  static const full = NormalizedRect(0, 0, 1, 1);

  NormalizedRect inflate(double fraction) {
    final dx = width * fraction, dy = height * fraction;
    final l = (left - dx).clamp(0.0, 1.0), t = (top - dy).clamp(0.0, 1.0);
    final r = (left + width + dx).clamp(0.0, 1.0), b = (top + height + dy).clamp(0.0, 1.0);
    return NormalizedRect(l, t, r - l, b - t);
  }

  @override
  String toString() => 'NormalizedRect($left, $top, $width, $height)';
}

class PreprocessOptions {
  const PreprocessOptions({
    this.crop = NormalizedRect.guide,
    this.cropMargin = 0.12,
    this.maxWidth = 1600,
    this.rotateDegrees = 0,
    this.enhance = true,
  });

  final NormalizedRect crop;
  final double cropMargin;
  final int maxWidth;

  /// Rotation supplémentaire (ex. –angle détecté par ML Kit sur plaque inclinée).
  final double rotateDegrees;

  /// Niveaux de gris + étirement du contraste si l'image est terne ou sombre.
  final bool enhance;
}

class PreprocessResult {
  const PreprocessResult({
    required this.path,
    required this.width,
    required this.height,
    required this.meanLuminance,
    required this.contrastStretched,
  });

  final String path;
  final int width;
  final int height;
  final double meanLuminance;
  final bool contrastStretched;

  bool get isDark => meanLuminance < 70;
}

/// Prépare la photo : orientation EXIF, recadrage, réduction, contraste.
class PlateImagePreprocessor {
  const PlateImagePreprocessor();

  /// Version asynchrone, exécutée dans un isolate séparé.
  Future<PreprocessResult> process(String inputPath, String outputPath,
      [PreprocessOptions options = const PreprocessOptions()]) {
    return Isolate.run(() => processSync(inputPath, outputPath, options));
  }

  static PreprocessResult processSync(
      String inputPath, String outputPath, PreprocessOptions options) {
    final bytes = File(inputPath).readAsBytesSync();
    final out = processBytes(bytes, options);
    File(outputPath).writeAsBytesSync(out.$1, flush: true);
    return PreprocessResult(
      path: outputPath,
      width: out.$2.width,
      height: out.$2.height,
      meanLuminance: out.$3,
      contrastStretched: out.$4,
    );
  }

  /// Cœur du traitement, sans accès disque (testable).
  /// Retourne (jpeg, image, luminance moyenne, contraste étiré ?).
  static (Uint8List, img.Image, double, bool) processBytes(
      Uint8List bytes, PreprocessOptions options) {
    var image = img.decodeImage(bytes);
    if (image == null) {
      throw const FormatException('Photo illisible');
    }

    // 1. Orientation : on applique l'EXIF du téléphone (portrait/paysage).
    image = img.bakeOrientation(image);

    // 2. Recadrage sur la zone de la plaque (cadre de guidage + marge).
    final r = options.crop.inflate(options.cropMargin);
    final x = (r.left * image.width).round();
    final y = (r.top * image.height).round();
    final w = math.max(1, (r.width * image.width).round());
    final h = math.max(1, (r.height * image.height).round());
    if (!(x == 0 && y == 0 && w == image.width && h == image.height)) {
      image = img.copyCrop(image,
          x: x, y: y, width: math.min(w, image.width - x), height: math.min(h, image.height - y));
    }

    // 3. Redressement d'une plaque inclinée.
    if (options.rotateDegrees.abs() > 0.5) {
      image = img.copyRotate(image,
          angle: options.rotateDegrees, interpolation: img.Interpolation.linear);
    }

    // 4. Réduction : ML Kit n'a pas besoin de plus, et c'est bien plus rapide.
    if (image.width > options.maxWidth) {
      image = img.copyResize(image,
          width: options.maxWidth, interpolation: img.Interpolation.average);
    }

    // 5. Contraste : niveaux de gris + étirement entre les percentiles 2 % et 98 %.
    var mean = _meanLuminance(image);
    var stretched = false;
    if (options.enhance) {
      image = img.grayscale(image);
      final (lo, hi) = _percentiles(image, 0.02, 0.98);
      if (hi - lo < 170 || mean < 90 || mean > 200) {
        _stretch(image, lo, hi);
        stretched = true;
        mean = _meanLuminance(image);
      }
    }

    return (img.encodeJpg(image, quality: 92), image, mean, stretched);
  }

  static double _meanLuminance(img.Image image) {
    var sum = 0.0;
    var n = 0;
    // Échantillonnage : 1 pixel sur 4 suffit pour une moyenne.
    for (var y = 0; y < image.height; y += 2) {
      for (var x = 0; x < image.width; x += 2) {
        sum += image.getPixel(x, y).luminance;
        n++;
      }
    }
    return n == 0 ? 0 : sum / n;
  }

  static (int, int) _percentiles(img.Image image, double low, double high) {
    final hist = List<int>.filled(256, 0);
    var n = 0;
    for (var y = 0; y < image.height; y += 2) {
      for (var x = 0; x < image.width; x += 2) {
        hist[image.getPixel(x, y).luminance.round().clamp(0, 255)]++;
        n++;
      }
    }
    int find(double q) {
      final target = n * q;
      var acc = 0;
      for (var i = 0; i < 256; i++) {
        acc += hist[i];
        if (acc >= target) return i;
      }
      return 255;
    }

    return (find(low), find(high));
  }

  static void _stretch(img.Image image, int lo, int hi) {
    if (hi <= lo) return;
    final scale = 255.0 / (hi - lo);
    for (final p in image) {
      final v = ((p.luminance - lo) * scale).round().clamp(0, 255);
      p
        ..r = v
        ..g = v
        ..b = v;
    }
  }
}
