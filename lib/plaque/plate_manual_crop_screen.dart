// PARKFASO — Recadrage manuel : le gardien encadre la plaque du doigt.

import 'dart:io';

import 'package:flutter/material.dart';

import 'plate_image_preprocessor.dart';

class PlateManualCropScreen extends StatefulWidget {
  const PlateManualCropScreen({super.key, required this.photoPath});

  final String photoPath;

  @override
  State<PlateManualCropScreen> createState() => _PlateManualCropScreenState();
}

class _PlateManualCropScreenState extends State<PlateManualCropScreen> {
  Size? _imageSize;
  // Rectangle en fractions de l'image.
  Rect _sel = const Rect.fromLTWH(0.15, 0.35, 0.7, 0.3);
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    final provider = FileImage(File(widget.photoPath));
    _stream = provider.resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() => _imageSize = Size(info.image.width.toDouble(), info.image.height.toDouble()));
      }
    });
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Encadrez la plaque'),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: _imageSize == null
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : LayoutBuilder(builder: (context, box) {
                    // Zone réellement occupée par l'image (BoxFit.contain).
                    final fitted = applyBoxFit(BoxFit.contain, _imageSize!, box.biggest).destination;
                    final origin = Offset((box.maxWidth - fitted.width) / 2, (box.maxHeight - fitted.height) / 2);
                    final area = origin & fitted;
                    final sel = Rect.fromLTWH(
                      area.left + _sel.left * area.width,
                      area.top + _sel.top * area.height,
                      _sel.width * area.width,
                      _sel.height * area.height,
                    );
                    return Stack(children: [
                      Positioned.fromRect(rect: area, child: Image.file(File(widget.photoPath), fit: BoxFit.fill)),
                      Positioned.fromRect(
                        rect: sel,
                        child: GestureDetector(
                          onPanUpdate: (d) => _move(d.delta, area.size),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFFFC107), width: 3),
                              color: const Color(0x22FFC107),
                            ),
                          ),
                        ),
                      ),
                      for (final corner in _corners)
                        Positioned(
                          left: sel.left + (corner.x + 1) / 2 * sel.width - 18,
                          top: sel.top + (corner.y + 1) / 2 * sel.height - 18,
                          child: GestureDetector(
                            onPanUpdate: (d) => _resize(corner, d.delta, area.size),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(color: Color(0xFFFFC107), shape: BoxShape.circle),
                            ),
                          ),
                        ),
                    ]);
                  }),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => Navigator.of(context).pop(
                    NormalizedRect(_sel.left, _sel.top, _sel.width, _sel.height)),
                icon: const Icon(Icons.search),
                label: const Text('ANALYSER CETTE ZONE'),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _move(Offset delta, Size area) {
    setState(() {
      final dx = delta.dx / area.width, dy = delta.dy / area.height;
      _sel = _sel.shift(Offset(dx, dy));
      _sel = Rect.fromLTWH(
        _sel.left.clamp(0.0, 1 - _sel.width),
        _sel.top.clamp(0.0, 1 - _sel.height),
        _sel.width,
        _sel.height,
      );
    });
  }

  void _resize(Alignment corner, Offset delta, Size area) {
    setState(() {
      final dx = delta.dx / area.width, dy = delta.dy / area.height;
      var l = _sel.left, t = _sel.top, r = _sel.right, b = _sel.bottom;
      if (corner.x < 0) {
        l += dx;
      } else {
        r += dx;
      }
      if (corner.y < 0) {
        t += dy;
      } else {
        b += dy;
      }
      l = l.clamp(0.0, r - 0.08);
      t = t.clamp(0.0, b - 0.05);
      r = r.clamp(l + 0.08, 1.0);
      b = b.clamp(t + 0.05, 1.0);
      _sel = Rect.fromLTRB(l, t, r, b);
    });
  }
}

const List<Alignment> _corners = [
  Alignment.topLeft, Alignment.topRight, Alignment.bottomLeft, Alignment.bottomRight,
];
