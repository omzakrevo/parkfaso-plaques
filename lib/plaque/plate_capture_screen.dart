// PARKFASO — Écran « Photographier la plaque ».

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'plate_camera_source.dart';
import 'plate_image_preprocessor.dart';
import 'plate_manual_crop_screen.dart';
import 'plate_models.dart';
import 'plate_ocr_service.dart';
import 'plate_parser.dart';

class PlateCaptureScreen extends StatefulWidget {
  const PlateCaptureScreen({
    super.key,
    required this.ocr,
    this.camera,
    this.autoPrintOnConfirm = true,
  });

  final PlateOcrService ocr;

  /// Caméra injectable (tests). Par défaut : caméra arrière du téléphone.
  final PlateCameraSource? camera;

  /// « Confirmer » renvoie printNow = true → enregistrement + impression directs.
  final bool autoPrintOnConfirm;

  /// Ouvre l'écran et renvoie le numéro validé (ou null si le gardien annule).
  static Future<PlateCaptureOutcome?> open(BuildContext context,
      {required PlateOcrService ocr, PlateCameraSource? camera, bool autoPrintOnConfirm = true}) {
    return Navigator.of(context).push<PlateCaptureOutcome>(MaterialPageRoute(
      builder: (_) => PlateCaptureScreen(ocr: ocr, camera: camera, autoPrintOnConfirm: autoPrintOnConfirm),
    ));
  }

  @override
  State<PlateCaptureScreen> createState() => _PlateCaptureScreenState();
}

enum _Phase { starting, ready, analyzing, result, cameraError }

class _PlateCaptureScreenState extends State<PlateCaptureScreen> {
  late final PlateCameraSource _camera = widget.camera ?? PackageCameraSource();
  _Phase _phase = _Phase.starting;
  String? _cameraError;
  String? _photoPath;
  PlateRecognitionResult? _result;
  String? _selected; // numéro choisi (ambiguïté) ou détecté
  bool _torch = false;
  bool _returned = false;

  @override
  void initState() {
    super.initState();
    _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      await _camera.initialize();
      if (mounted) setState(() => _phase = _Phase.ready);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.cameraError;
          _cameraError = 'Caméra indisponible. Vérifiez l\'autorisation caméra '
              'ou saisissez le numéro à la main.';
        });
      }
    }
  }

  @override
  void dispose() {
    _camera.setTorch(false);
    _camera.dispose();
    // Photo non utilisée (gardien qui quitte) : on ne la garde pas.
    if (!_returned && _photoPath != null) {
      try {
        File(_photoPath!).deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _capture() async {
    if (_phase != _Phase.ready) return;
    HapticFeedback.selectionClick();
    try {
      final path = await _camera.takePicture();
      await _analyze(path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _phase = _Phase.ready);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo impossible. Réessayez.')),
      );
    }
  }

  Future<void> _analyze(String path, {NormalizedRect crop = NormalizedRect.guide}) async {
    setState(() {
      _photoPath = path;
      _phase = _Phase.analyzing;
      _result = null;
      _selected = null;
    });
    final r = await widget.ocr.recognize(path, crop: crop);
    if (!mounted) return;
    setState(() {
      _result = r;
      _selected = r.plate;
      _phase = _Phase.result;
    });
    if (r.plate != null) HapticFeedback.mediumImpact();
  }

  Future<void> _retake() async {
    if (_photoPath != null) {
      try {
        File(_photoPath!).deleteSync();
      } catch (_) {}
    }
    setState(() {
      _photoPath = null;
      _result = null;
      _selected = null;
      _phase = _Phase.ready;
    });
  }

  Future<void> _manualCrop() async {
    final path = _photoPath;
    if (path == null) return;
    final rect = await Navigator.of(context).push<NormalizedRect>(
      MaterialPageRoute(builder: (_) => PlateManualCropScreen(photoPath: path)),
    );
    if (rect != null && mounted) await _analyze(path, crop: rect);
  }

  void _confirm() {
    final plate = _selected;
    if (plate == null) return;
    _finish(PlateCaptureOutcome(
      plate: plate,
      method: PlateCaptureMethod.ocr,
      verified: true,
      photoPath: _photoPath,
      ocrRawText: _result?.parse.rawText,
      printNow: widget.autoPrintOnConfirm,
    ));
  }

  Future<void> _correct() async {
    final typed = await showPlateEditDialog(context,
        initial: _selected ?? _result?.parse.partialHint ?? '', parser: widget.ocr.parser);
    if (typed == null || !mounted) return;
    final unchanged = typed == _selected;
    _finish(PlateCaptureOutcome(
      plate: typed,
      method: unchanged ? PlateCaptureMethod.ocr : PlateCaptureMethod.manual,
      verified: true,
      photoPath: _photoPath,
      ocrRawText: _result?.parse.rawText,
      // Après une correction, on revient au formulaire : le gardien relit avant d'imprimer.
      printNow: false,
    ));
  }

  void _finish(PlateCaptureOutcome outcome) {
    _returned = true;
    Navigator.of(context).pop(outcome);
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Photographier la plaque'),
        actions: [
          if (_phase == _Phase.ready && _camera.hasTorch)
            IconButton(
              tooltip: _torch ? 'Éteindre la lampe' : 'Allumer la lampe',
              icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
              onPressed: () async {
                setState(() => _torch = !_torch);
                await _camera.setTorch(_torch);
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _viewfinder()),
            _bottomPanel(),
          ],
        ),
      ),
    );
  }

  Widget _viewfinder() {
    if (_phase == _Phase.cameraError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_cameraError ?? '', textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
        ),
      );
    }
    if (_phase == _Phase.starting) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    final frozen = _photoPath != null && _phase != _Phase.ready;
    return Center(
      child: AspectRatio(
        aspectRatio: _camera.portraitAspectRatio,
        child: Stack(fit: StackFit.expand, children: [
          if (frozen)
            Image.file(File(_photoPath!), fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black))
          else
            _camera.buildPreview(),
          const _GuideOverlay(rect: NormalizedRect.guide),
          if (_phase == _Phase.analyzing)
            const ColoredBox(
              color: Color(0x88000000),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12),
                  Text('Analyse en cours…',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _bottomPanel() {
    final theme = Theme.of(context);
    Widget body;
    switch (_phase) {
      case _Phase.starting:
      case _Phase.analyzing:
        body = const SizedBox(height: 88);
      case _Phase.cameraError:
        body = _wide(FilledButton.icon(
          onPressed: _correct,
          icon: const Icon(Icons.keyboard),
          label: const Text('SAISIR À LA MAIN'),
        ));
      case _Phase.ready:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Placez la plaque arrière dans le cadre',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: 'Prendre la photo',
            child: GestureDetector(
              key: const Key('capture-button'),
              onTap: _capture,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 5),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(5),
                  child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
                ),
              ),
            ),
          ),
        ]);
      case _Phase.result:
        body = _resultPanel(theme);
    }
    return Container(
      width: double.infinity,
      color: _phase == _Phase.result ? theme.colorScheme.surface : Colors.black,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: body,
    );
  }

  Widget _resultPanel(ThemeData theme) {
    final r = _result!;
    final parse = r.parse;
    final children = <Widget>[];

    if (r.error != null) {
      children.add(_message(r.error!, Icons.error_outline, theme.colorScheme.error));
    } else {
      switch (parse.status) {
        case PlateMatchStatus.found:
          children.add(Text('Numéro détecté', style: theme.textTheme.labelLarge));
          final corrections = parse.best?.corrections ?? 0;
          if (corrections > 0) {
            children.add(Text(
              '$corrections caractère${corrections > 1 ? 's' : ''} corrigé${corrections > 1 ? 's' : ''} '
              'automatiquement — vérifiez',
              style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
            ));
          }
        case PlateMatchStatus.ambiguous:
          children.add(Text('Plusieurs numéros lus : touchez le bon', style: theme.textTheme.labelLarge));
          children.add(const SizedBox(height: 8));
          children.add(Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in parse.candidates.take(4))
              ChoiceChip(
                label: Text(c.plate, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                selected: _selected == c.plate,
                onSelected: (_) => setState(() => _selected = c.plate),
              ),
          ]));
        case PlateMatchStatus.partial:
          children.add(_message(
            'Plaque incomplète : aucun numéro proposé.\nLu : « ${parse.partialHint} »',
            Icons.warning_amber, Colors.orange.shade800));
        case PlateMatchStatus.notFound:
          children.add(_message('Aucune plaque reconnue.', Icons.search_off, theme.colorScheme.error));
      }
    }

    if (_selected != null) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          key: const Key('detected-plate'),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black, width: 3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(_selected!,
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 2,
                  color: Colors.black)),
        ),
      ));
      children.add(_wide(FilledButton.icon(
        key: const Key('confirm-plate'),
        style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700, minimumSize: const Size.fromHeight(56)),
        onPressed: _confirm,
        icon: const Icon(Icons.check_circle),
        label: Text(widget.autoPrintOnConfirm ? 'CONFIRMER ET IMPRIMER' : 'CONFIRMER',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      )));
      children.add(const SizedBox(height: 8));
      children.add(Row(children: [
        Expanded(child: OutlinedButton.icon(
          key: const Key('correct-plate'),
          onPressed: _correct, icon: const Icon(Icons.edit), label: const Text('CORRIGER'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          key: const Key('retake-photo'),
          onPressed: _retake, icon: const Icon(Icons.camera_alt), label: const Text('REPRENDRE'))),
      ]));
    } else {
      children.add(const SizedBox(height: 10));
      children.add(_wide(FilledButton.icon(
        key: const Key('retake-photo'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: _retake,
        icon: const Icon(Icons.camera_alt),
        label: const Text('REPRENDRE LA PHOTO'),
      )));
      children.add(const SizedBox(height: 8));
      children.add(Row(children: [
        Expanded(child: OutlinedButton.icon(
          key: const Key('manual-crop'),
          onPressed: _manualCrop, icon: const Icon(Icons.crop), label: const Text('RECADRER'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          key: const Key('correct-plate'),
          onPressed: _correct, icon: const Icon(Icons.keyboard), label: const Text('SAISIR'))),
      ]));
    }

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: children);
  }

  Widget _wide(Widget w) => SizedBox(width: double.infinity, child: w);

  Widget _message(String text, IconData icon, Color color) => Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
      ]);
}

/// Cadre de guidage : zone claire au centre, reste assombri.
class _GuideOverlay extends StatelessWidget {
  const _GuideOverlay({required this.rect});

  final NormalizedRect rect;

  @override
  Widget build(BuildContext context) => IgnorePointer(child: CustomPaint(painter: _GuidePainter(rect)));
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.r);

  final NormalizedRect r;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = Rect.fromLTWH(r.left * size.width, r.top * size.height, r.width * size.width, r.height * size.height);
    final rr = RRect.fromRectAndRadius(hole, const Radius.circular(14));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(rr)),
      Paint()..color = const Color(0x99000000),
    );
    final corner = Paint()
      ..color = const Color(0xFFFFC107)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 28.0;
    for (final (p, dx, dy) in [
      (hole.topLeft, 1.0, 1.0), (hole.topRight, -1.0, 1.0),
      (hole.bottomLeft, 1.0, -1.0), (hole.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(p, p + Offset(l * dx, 0), corner);
      canvas.drawLine(p, p + Offset(0, l * dy), corner);
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) => old.r != r;
}

/// Boîte de dialogue de saisie / correction du numéro.
Future<String?> showPlateEditDialog(BuildContext context,
    {required String initial, required PlateParser parser}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Numéro d\'immatriculation'),
      content: TextField(
        key: const Key('plate-edit-field'),
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
        decoration: const InputDecoration(hintText: '11 AB 2345'),
        inputFormatters: [UpperCaseTextFormatter()],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ANNULER')),
        FilledButton(
          key: const Key('plate-edit-ok'),
          onPressed: () {
            final v = ctrl.text.trim();
            if (v.isEmpty) return;
            Navigator.pop(ctx, parser.formatManualEntry(v) ?? PlateParser.normalize(v));
          },
          child: const Text('VALIDER'),
        ),
      ],
    ),
  );
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
