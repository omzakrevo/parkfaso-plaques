// PARKFASO — Scan d'un ticket (QR) à la sortie.
//
// Le gardien scanne le ticket client, véhicule ou casque : l'application
// retrouve la session, affiche la plaque à comparer, la durée, et valide la
// sortie. Un ticket déjà utilisé ou inconnu est signalé. Fonctionne hors ligne.

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app/parkfaso_theme.dart';
import '../plaque/plate_database.dart';
import '../plaque/plate_models.dart';
import 'tickets.dart';

enum ScanStatus {
  /// Véhicule au parking : la sortie peut être validée.
  inside,

  /// Ticket déjà utilisé pour une sortie.
  alreadyExited,

  /// Ticket PARKFASO lisible, mais absent de ce téléphone.
  notFound,

  /// La plaque du QR ne correspond pas à celle enregistrée (ticket modifié ?).
  plateMismatch,

  /// Ce n'est pas un ticket PARKFASO.
  invalid,
}

class ScanResult {
  const ScanResult(this.status, {this.qr, this.session});
  final ScanStatus status;
  final TicketQr? qr;
  final ParkingSession? session;
}

/// Logique du scan, indépendante de la caméra (testable).
class TicketScanService {
  TicketScanService(this.repository, {DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  final SessionRepository repository;
  final DateTime Function() clock;

  Future<ScanResult> lookup(String code) async {
    final qr = TicketQr.tryParse(code);
    if (qr == null) return const ScanResult(ScanStatus.invalid);
    final s = await repository.findByTicket(qr.ticketBase);
    if (s == null) return ScanResult(ScanStatus.notFound, qr: qr);
    if (qr.plate.isNotEmpty && s.licensePlate.replaceAll(' ', '') != qr.plate) {
      return ScanResult(ScanStatus.plateMismatch, qr: qr, session: s);
    }
    if (!s.isInside) return ScanResult(ScanStatus.alreadyExited, qr: qr, session: s);
    return ScanResult(ScanStatus.inside, qr: qr, session: s);
  }

  Future<ParkingSession> validateExit(ParkingSession s) async {
    final now = clock();
    await repository.markExited(s.id!, now);
    return s.copyWith(exitedAt: now);
  }
}

String formatDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  if (h >= 24) return '${h ~/ 24} j ${h % 24} h';
  return '$h h ${m.toString().padLeft(2, '0')}';
}

class TicketScanScreen extends StatefulWidget {
  const TicketScanScreen({
    super.key,
    required this.service,
    this.currency = 'FCFA',
    this.scannerBuilder,
  });

  final TicketScanService service;
  final String currency;

  /// Caméra injectable (tests). Par défaut : lecteur QR ML Kit embarqué.
  final Widget Function(ValueChanged<String> onCode)? scannerBuilder;

  @override
  State<TicketScanScreen> createState() => _TicketScanScreenState();
}

class _TicketScanScreenState extends State<TicketScanScreen> {
  MobileScannerController? _controller;
  ScanResult? _result;
  bool _busy = false;
  String? _lastCode;
  DateTime? _exitDone;

  @override
  void initState() {
    super.initState();
    if (widget.scannerBuilder == null) {
      _controller = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onCode(String code) async {
    if (_busy || _result != null || code == _lastCode) return;
    _lastCode = code;
    setState(() => _busy = true);
    final r = await widget.service.lookup(code);
    if (!mounted) return;
    setState(() {
      _result = r;
      _busy = false;
      _exitDone = null;
    });
  }

  Future<void> _validate() async {
    final s = _result?.session;
    if (s == null) return;
    setState(() => _busy = true);
    final updated = await widget.service.validateExit(s);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _exitDone = updated.exitedAt;
      _result = ScanResult(ScanStatus.alreadyExited, qr: _result!.qr, session: updated);
    });
  }

  void _next() => setState(() {
        _result = null;
        _lastCode = null;
        _exitDone = null;
      });

  Future<void> _manual() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('N° du ticket'),
        content: TextField(
          key: const Key('manual-ticket-field'),
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'PK-000125'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            key: const Key('manual-ticket-ok'),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Rechercher'),
          ),
        ],
      ),
    );
    if (code != null && code.trim().isNotEmpty) {
      _lastCode = null;
      _result = null;
      await _onCode(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scanner un ticket'),
        actions: [
          IconButton(
            key: const Key('manual-ticket'),
            tooltip: 'Saisir le numéro',
            onPressed: _manual,
            icon: const Icon(Icons.keyboard_outlined),
          ),
          if (_controller != null)
            IconButton(
              tooltip: 'Lampe',
              onPressed: () => _controller!.toggleTorch(),
              icon: const Icon(Icons.flashlight_on_outlined),
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            widget.scannerBuilder?.call(_onCode) ??
                MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    final v = capture.barcodes.firstOrNull?.rawValue;
                    if (v != null) _onCode(v);
                  },
                  errorBuilder: (context, error) => const Center(
                    child: Text('Caméra indisponible.\nSaisissez le numéro du ticket.',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
                  ),
                ),
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    border: Border.all(color: ParkColors.amber, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            if (_busy) const Center(child: CircularProgressIndicator(color: Colors.white)),
          ]),
        ),
        if (_result != null) _resultPanel(_result!),
        if (_result == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Placez le QR code du ticket dans le cadre',
                style: TextStyle(color: Colors.white70)),
          ),
      ]),
    );
  }

  Widget _resultPanel(ScanResult r) {
    final s = r.session;
    final (color, icon, title) = switch (r.status) {
      ScanStatus.inside => (ParkColors.green, Icons.local_parking, 'Au parking'),
      ScanStatus.alreadyExited when _exitDone != null =>
        (ParkColors.green, Icons.check_circle, 'Sortie validée'),
      ScanStatus.alreadyExited => (ParkColors.red, Icons.block, 'Ticket déjà utilisé'),
      ScanStatus.plateMismatch => (ParkColors.red, Icons.warning_amber, 'Plaque différente !'),
      ScanStatus.notFound => (ParkColors.warn, Icons.help_outline, 'Ticket inconnu sur ce téléphone'),
      ScanStatus.invalid => (ParkColors.red, Icons.qr_code_2, 'Ce n\'est pas un ticket PARKFASO'),
    };
    final qr = r.qr;
    return Container(
      key: const Key('scan-result'),
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, key: const Key('scan-title'),
                style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          if (qr != null)
            Text(qr.ticketNumber, style: const TextStyle(color: ParkColors.muted, fontSize: 13)),
        ]),
        if (qr?.kind == TicketKind.casque)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Ticket casque n° ${qr!.helmetIndex ?? ''} — rendre le casque',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        if (s != null) ...[
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Icon(s.vehicleType.icon, color: ParkColors.navy),
            const SizedBox(width: 8),
            Text(s.vehicleType.label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            if (s.hasPlate) PlateBadge(s.licensePlate, key: const Key('scan-plate'), size: 18)
            else const Text('Sans plaque', style: TextStyle(color: ParkColors.muted)),
          ]),
          if (r.status == ScanStatus.plateMismatch)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Le QR indique « ${qr!.plate} ». Vérifiez le véhicule.',
                  style: const TextStyle(color: ParkColors.red)),
            ),
          const SizedBox(height: 10),
          _info('Entrée', formatDateTime(s.enteredAt)),
          if (s.exitedAt != null) _info('Sortie', formatDateTime(s.exitedAt!)),
          _info('Durée', formatDuration((s.exitedAt ?? widget.service.clock()).difference(s.enteredAt))),
          if (s.helmetCount > 0) _info('Casques', '${s.helmetCount}'),
          _info('Payé', '${s.total} ${widget.currency}'),
        ] else if (qr != null && r.status == ScanStatus.notFound) ...[
          const SizedBox(height: 8),
          if (qr.plate.isNotEmpty) _info('Plaque (QR)', qr.plate),
          if (qr.enteredAt != null) _info('Entrée (QR)', formatDateTime(qr.enteredAt!)),
          const Text('Ce ticket a peut-être été émis par un autre téléphone.',
              style: TextStyle(color: ParkColors.muted, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('scan-next'),
              onPressed: _next,
              child: const Text('Suivant'),
            ),
          ),
          if (r.status == ScanStatus.inside) ...[
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                key: const Key('validate-exit'),
                style: FilledButton.styleFrom(backgroundColor: ParkColors.green),
                onPressed: _busy ? null : _validate,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Valider la sortie'),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _info(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(color: ParkColors.muted))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}
