// Génération de photos de plaques de test (synthétiques, reproductibles).
// Utilisé par les tests unitaires (prétraitement) et par le test sur téléphone
// (vrai ML Kit, hors ligne).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

enum PlateScene { wellLit, dark, tilted, dirty, multipleTexts, noPlate, twoLines }

/// Image 720×960 (portrait, comme le téléphone) avec la plaque dans le cadre de guidage.
img.Image buildPlateScene(PlateScene scene, {String plate = '11 AB 2345', int seed = 7}) {
  final rnd = math.Random(seed);
  final w = 720, h = 960;
  final bg = img.Image(width: w, height: h);
  img.fill(bg, color: img.ColorRgb8(96, 84, 70)); // garde-boue / carrosserie

  // Plaque : fond blanc, bord noir, centrée dans le cadre (10%..90%, 30%..70%).
  final pw = 560, ph = scene == PlateScene.twoLines ? 300 : 170;
  final px = (w - pw) ~/ 2, py = (h - ph) ~/ 2;
  if (scene != PlateScene.noPlate) {
    final plateImg = img.Image(width: pw, height: ph);
    img.fill(plateImg, color: img.ColorRgb8(245, 245, 240));
    img.drawRect(plateImg, x1: 0, y1: 0, x2: pw - 1, y2: ph - 1,
        color: img.ColorRgb8(10, 10, 10), thickness: 8);
    if (scene == PlateScene.twoLines) {
      final parts = plate.split(' ');
      _drawBig(plateImg, '${parts[0]} ${parts[1]}', y: 30);
      _drawBig(plateImg, parts.sublist(2).join(' '), y: 160);
    } else {
      _drawBig(plateImg, plate, y: 45);
    }
    var placed = plateImg;
    if (scene == PlateScene.tilted) {
      placed = img.copyRotate(plateImg, angle: 12, interpolation: img.Interpolation.linear);
    }
    img.compositeImage(bg, placed,
        dstX: (w - placed.width) ~/ 2, dstY: (h - placed.height) ~/ 2);
  }

  if (scene == PlateScene.multipleTexts) {
    img.drawString(bg, 'TEL 70 12 34 56', font: img.arial24, x: 40, y: 80,
        color: img.ColorRgb8(255, 255, 255));
    img.drawString(bg, 'YAMAHA', font: img.arial48, x: 40, y: 840,
        color: img.ColorRgb8(230, 230, 230));
  }
  if (scene == PlateScene.noPlate) {
    img.drawString(bg, 'PARKING', font: img.arial24, x: 300, y: 450,
        color: img.ColorRgb8(200, 200, 200));
  }
  if (scene == PlateScene.dirty) {
    // Boue : taches sombres + dernier chiffre effacé.
    for (var i = 0; i < 40; i++) {
      img.fillCircle(bg,
          x: px + rnd.nextInt(pw), y: py + rnd.nextInt(ph), radius: 4 + rnd.nextInt(10),
          color: img.ColorRgb8(90, 70, 50));
    }
    img.fillRect(bg, x1: px + pw - 120, y1: py + 20, x2: px + pw - 20, y2: py + ph - 20,
        color: img.ColorRgb8(240, 240, 235));
  }
  if (scene == PlateScene.dark) {
    for (final p in bg) {
      p
        ..r = p.r * 0.22
        ..g = p.g * 0.22
        ..b = p.b * 0.25;
    }
  }
  // Bruit de capteur léger partout.
  for (var i = 0; i < 4000; i++) {
    final p = bg.getPixel(rnd.nextInt(w), rnd.nextInt(h));
    final d = rnd.nextInt(30) - 15;
    p
      ..r = (p.r + d).clamp(0, 255)
      ..g = (p.g + d).clamp(0, 255)
      ..b = (p.b + d).clamp(0, 255);
  }
  return bg;
}

Uint8List buildPlateJpeg(PlateScene scene, {String plate = '11 AB 2345'}) =>
    img.encodeJpg(buildPlateScene(scene, plate: plate), quality: 90);

/// Grands caractères : police 48 px agrandie ×2 (≈ 96 px), comme une vraie plaque.
void _drawBig(img.Image target, String text, {required int y}) {
  final small = img.Image(width: 280, height: 60);
  img.fill(small, color: img.ColorRgb8(245, 245, 240));
  img.drawString(small, text, font: img.arial48, x: 4, y: 4, color: img.ColorRgb8(10, 10, 10));
  final big = img.copyResize(small, width: 560, height: 120, interpolation: img.Interpolation.cubic);
  img.compositeImage(target, big, dstX: 0, dstY: y);
}
