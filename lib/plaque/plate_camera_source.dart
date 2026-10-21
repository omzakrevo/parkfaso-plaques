// PARKFASO — Accès caméra derrière une interface (remplaçable dans les tests).

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

abstract class PlateCameraSource {
  Future<void> initialize();

  /// Rapport largeur/hauteur de l'aperçu en mode portrait.
  double get portraitAspectRatio;
  Widget buildPreview();
  Future<String> takePicture();
  Future<void> setTorch(bool on);
  bool get hasTorch;
  Future<void> dispose();
}

class PackageCameraSource implements PlateCameraSource {
  CameraController? _controller;
  bool _torch = true;

  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw CameraException('no_camera', 'Aucune caméra disponible');
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    // « high » (~720p) : assez net pour une plaque, rapide à capturer et analyser.
    final c = CameraController(back, ResolutionPreset.high,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    await c.initialize();
    await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
    try {
      await c.setFocusMode(FocusMode.auto);
      await c.setFlashMode(FlashMode.off);
    } catch (_) {
      _torch = false;
    }
    _controller = c;
  }

  @override
  double get portraitAspectRatio {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return 3 / 4;
    return 1 / c.value.aspectRatio; // l'aspectRatio du plugin est en paysage
  }

  @override
  Widget buildPreview() => _controller == null ? const SizedBox() : CameraPreview(_controller!);

  @override
  Future<String> takePicture() async {
    final file = await _controller!.takePicture();
    return file.path;
  }

  @override
  bool get hasTorch => _torch;

  @override
  Future<void> setTorch(bool on) async {
    if (!_torch || _controller == null) return;
    await _controller!.setFlashMode(on ? FlashMode.torch : FlashMode.off);
  }

  @override
  Future<void> dispose() async => _controller?.dispose();
}
