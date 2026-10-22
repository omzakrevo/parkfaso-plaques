// PARKFASO — Entrée d'un véhicule (moto, voiture, tricycle, vélo).
//
// Phase 1 : casques, plaque (facultative) → ENREGISTRER : le ticket client sort.
// Phase 2 : le gardien choisit d'imprimer ou non le ticket véhicule / casques.

import 'package:flutter/material.dart';

import '../app/parkfaso_theme.dart';
import '../core/platform.dart';
import '../tickets/tickets.dart';
import 'plate_camera_source.dart';
import 'plate_capture_screen.dart';
import 'plate_database.dart';
import 'plate_models.dart';
import 'plate_ocr_service.dart';
import 'plate_photo_store.dart';

class VehicleEntryScreen extends StatefulWidget {
  const VehicleEntryScreen({
    super.key,
    required this.vehicleType,
    required this.settings,
    required this.ocr,
    required this.repository,
    required this.printer,
    required this.photoStore,
    this.cameraFactory,
    this.clock,
  });

  final VehicleType vehicleType;
  final ParkingSettings settings;
  final PlateOcrService ocr;
  final SessionRepository repository;
  final TicketPrinter printer;
  final PlatePhotoStore photoStore;

  /// Caméra injectable (tests) ; par défaut, caméra arrière.
  final PlateCameraSource Function()? cameraFactory;
  final DateTime Function()? clock;

  @override
  State<VehicleEntryScreen> createState() => _VehicleEntryScreenState();
}

class _VehicleEntryScreenState extends State<VehicleEntryScreen> {
  final _plateCtrl = TextEditingController();
  int? _helmets; // null = pas encore répondu (moto/tricycle)
  String? _ocrPlate;
  String? _ocrRaw;
  String? _photoPath;
  bool _verified = false;
  bool _busy = false;
  String? _error;

  // Phase 2
  ParkingSession? _saved;
  bool _clientPrinted = false;
  bool _printVehicle = true;
  bool _printHelmets = true;

  VehicleType get type => widget.vehicleType;

  /// Lecture de plaque par caméra : téléphone uniquement (pas sur PC).
  bool get _canPhoto => hasMobileCamera || widget.cameraFactory != null;
  ParkingSettings get s => widget.settings;
  int get _helmetCount => _helmets ?? 0;
  int get _total => s.priceOf(type) + s.helmetPrice * _helmetCount;
  bool get _helmetAnswered => !type.hasHelmet || _helmets != null;

  @override
  void dispose() {
    _plateCtrl.dispose();
    super.dispose();
  }

  PlateCaptureMethod get _method {
    final t = _plateCtrl.text.trim();
    if (t.isEmpty) return PlateCaptureMethod.none;
    return t == _ocrPlate ? PlateCaptureMethod.ocr : PlateCaptureMethod.manual;
  }

  Future<void> _photograph() async {
    final outcome = await PlateCaptureScreen.open(
      context,
      ocr: widget.ocr,
      camera: widget.cameraFactory?.call(),
      confirmLabel: _helmetAnswered ? 'CONFIRMER ET IMPRIMER' : 'CONFIRMER',
    );
    if (outcome == null || !mounted) return;
    if (_photoPath != null && _photoPath != outcome.photoPath) {
      await widget.photoStore.discard(_photoPath);
    }
    setState(() {
      _plateCtrl.text = outcome.plate;
      _ocrPlate = outcome.method == PlateCaptureMethod.ocr ? outcome.plate : null;
      _ocrRaw = outcome.ocrRawText;
      _photoPath = outcome.photoPath;
      _verified = outcome.verified;
      _error = null;
    });
    if (outcome.saveNow && _helmetAnswered) await _save();
  }

  /// Phase 1 : enregistrement + ticket client.
  Future<void> _save() async {
    if (_busy) return;
    if (!_helmetAnswered) {
      setState(() => _error = 'Indiquez le nombre de casques.');
      return;
    }
    final raw = _plateCtrl.text.trim();
    final plate = raw.isEmpty ? '' : (widget.ocr.parser.formatManualEntry(raw) ?? raw.toUpperCase());
    if (plate.isEmpty && type.hasPlate && !s.allowEmptyPlate) {
      setState(() => _error = 'Immatriculation obligatoire dans ce parking.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final base = await widget.repository.nextTicketBase();
      final method = _method;
      final keptPhoto = await widget.photoStore.finalize(_photoPath, ticketBase: base);
      _photoPath = null;
      var session = ParkingSession(
        vehicleType: type,
        ticketBase: base,
        enteredAt: (widget.clock ?? DateTime.now)(),
        helmetCount: _helmetCount,
        vehiclePrice: s.priceOf(type),
        helmetPrice: s.helmetPrice,
        licensePlate: plate,
        plateCaptureMethod: method,
        plateVerified: plate.isNotEmpty && (_verified || method == PlateCaptureMethod.manual),
        plateOcrRawText: s.keepOcrRawText ? _ocrRaw : null,
        platePhotoPath: keptPhoto,
      );
      session = session.copyWith(id: await widget.repository.save(session));
      setState(() => _saved = session);
      await _printClient();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Enregistrement impossible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printClient() async {
    setState(() => _busy = true);
    try {
      await widget.printer.printTickets([TicketBuilder(s).buildClient(_saved!)]);
      if (mounted) setState(() => _clientPrinted = true);
    } catch (e) {
      if (mounted) _snack('Ticket client non imprimé : $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Phase 2 : ticket véhicule / casques, si le gardien le décide.
  Future<void> _printSecondary() async {
    final docs = TicketBuilder(s).buildSecondary(_saved!, vehicle: _printVehicle, helmets: _printHelmets);
    if (docs.isEmpty) return _finish();
    setState(() => _busy = true);
    try {
      await widget.printer.printTickets(docs);
      if (!mounted) return;
      _finish(message: '${docs.length} ticket${docs.length > 1 ? 's' : ''} imprimé${docs.length > 1 ? 's' : ''}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Impression échouée : $e', error: true);
    }
  }

  void _finish({String? message}) {
    if (message != null) _snack(message);
    Navigator.of(context).pop(_saved);
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? ParkColors.red : ParkColors.green));
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _photoPath != null) widget.photoStore.discard(_photoPath);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [Icon(type.icon, size: 22), const SizedBox(width: 8), Text('Entrée ${type.label.toLowerCase()}')],
          ),
        ),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _saved == null ? _form() : _phaseTwo(),
          ),
        ),
      ),
    );
  }

  Widget _form() {
    return Column(
      key: const ValueKey('form'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: [
              if (type.hasHelmet) ...[
                const SectionLabel('Casques déposés'),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    key: const Key('helmet-choice'),
                    emptySelectionAllowed: true,
                    showSelectedIcon: false,
                    segments: [
                      const ButtonSegment(value: 0, label: Text('Aucun', key: Key('helmet-0'))),
                      for (var i = 1; i <= s.maxHelmets; i++)
                        ButtonSegment(
                          value: i,
                          label: Text('$i', key: Key('helmet-$i')),
                        ),
                    ],
                    selected: {if (_helmets != null) _helmets!},
                    onSelectionChanged: (v) => setState(() {
                      _helmets = v.isEmpty ? null : v.first;
                      _error = null;
                    }),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (type.hasPlate) ...[
                SectionLabel(s.allowEmptyPlate ? 'Immatriculation · facultatif' : 'Immatriculation'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('plate-field'),
                        controller: _plateCtrl,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [UpperCaseTextFormatter()],
                        onChanged: (_) => setState(() => _error = null),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                        decoration: InputDecoration(
                          hintText: '11 AB 2345',
                          suffixIcon: _method == PlateCaptureMethod.ocr
                              ? const Icon(Icons.verified, color: ParkColors.green, size: 20)
                              : null,
                        ),
                      ),
                    ),
                    if (_canPhoto) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 46,
                        width: 52,
                        child: FilledButton.tonal(
                          key: const Key('photo-plate'),
                          style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                          onPressed: _busy ? null : _photograph,
                          child: const Icon(Icons.photo_camera_outlined),
                        ),
                      ),
                    ],
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 2),
                  child: Text(switch (_method) {
                    PlateCaptureMethod.ocr => 'Lu par la caméra et vérifié',
                    PlateCaptureMethod.manual => 'Saisi à la main',
                    PlateCaptureMethod.none =>
                      _canPhoto ? 'Touchez l\'appareil photo pour lire la plaque' : 'Tapez le numéro, ex. 11AB2345',
                  }, style: const TextStyle(fontSize: 12, color: ParkColors.muted)),
                ),
                const SizedBox(height: 18),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    children: [
                      _amountRow(type.label, s.priceOf(type)),
                      if (_helmetCount > 0) _amountRow('Casque × $_helmetCount', s.helmetPrice * _helmetCount),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider()),
                      _amountRow('Total', _total, bold: true, key: const Key('total-amount')),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    key: const Key('form-error'),
                    style: const TextStyle(color: ParkColors.red, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('save-print'),
              style: FilledButton.styleFrom(backgroundColor: ParkColors.green),
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Icon(Icons.print_outlined, size: 20),
              label: const Text('Enregistrer · ticket client'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _phaseTwo() {
    final saved = _saved!;
    final vehicleLabel = type.label.toLowerCase();
    return Column(
      key: const ValueKey('phase2'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        _clientPrinted ? Icons.check_circle : Icons.error_outline,
                        color: _clientPrinted ? ParkColors.green : ParkColors.red,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _clientPrinted ? 'Ticket client imprimé' : 'Ticket client non imprimé',
                              key: const Key('client-status'),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            Text(
                              '${saved.ticketBase}-C · ${saved.total} ${s.currency}',
                              style: const TextStyle(color: ParkColors.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      if (saved.hasPlate) PlateBadge(saved.licensePlate, size: 14),
                    ],
                  ),
                ),
              ),
              if (!_clientPrinted)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    key: const Key('reprint-client'),
                    onPressed: _busy ? null : _printClient,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Réimprimer le ticket client'),
                  ),
                ),
              const SizedBox(height: 18),
              const SectionLabel('Autres tickets'),
              Card(
                child: Column(
                  children: [
                    CheckboxListTile(
                      key: const Key('opt-vehicle'),
                      dense: true,
                      value: _printVehicle,
                      onChanged: (v) => setState(() => _printVehicle = v ?? false),
                      title: Text('Ticket $vehicleLabel'),
                      subtitle: Text('À laisser sur ${type.withArticle} · ${saved.ticketBase}-${type.ticketSuffix}'),
                    ),
                    if (saved.helmetCount > 0) ...[
                      const Divider(),
                      CheckboxListTile(
                        key: const Key('opt-helmets'),
                        dense: true,
                        value: _printHelmets,
                        onChanged: (v) => setState(() => _printHelmets = v ?? false),
                        title: Text('Ticket${saved.helmetCount > 1 ? 's' : ''} casque × ${saved.helmetCount}'),
                        subtitle: const Text('À fixer sur chaque casque'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('finish-no-print'),
                  onPressed: _busy ? null : () => _finish(),
                  child: const Text('Terminer'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  key: const Key('print-secondary'),
                  onPressed: _busy || (!_printVehicle && !(_printHelmets && saved.helmetCount > 0))
                      ? null
                      : _printSecondary,
                  icon: const Icon(Icons.print_outlined, size: 20),
                  label: const Text('Imprimer'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _amountRow(String label, int value, {bool bold = false, Key? key}) {
    final style = TextStyle(
      fontSize: bold ? 17 : 14,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: bold ? ParkColors.navy : Colors.black87,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value == 0 && !bold ? 'Gratuit' : '$value ${s.currency}', key: key, style: style),
        ],
      ),
    );
  }
}
