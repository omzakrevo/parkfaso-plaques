// PARKFASO — Enregistrement d'une moto (ouvert par le bouton « MOTO »).
//
// Parcours rapide : MOTO → CASQUE OUI/NON → PHOTO PLAQUE → CONFIRMER → impression.

import 'package:flutter/material.dart';

import '../tickets/moto_tickets.dart';
import 'plate_camera_source.dart';
import 'plate_capture_screen.dart';
import 'plate_database.dart';
import 'plate_models.dart';
import 'plate_ocr_service.dart';
import 'plate_photo_store.dart';

class MotoEntryScreen extends StatefulWidget {
  const MotoEntryScreen({
    super.key,
    required this.settings,
    required this.ocr,
    required this.repository,
    required this.printer,
    required this.photoStore,
    this.cameraFactory,
    this.clock,
  });

  final MotoEntrySettings settings;
  final PlateOcrService ocr;
  final MotoSessionRepository repository;
  final TicketPrinter printer;
  final PlatePhotoStore photoStore;

  /// Caméra injectable (tests) ; par défaut, caméra arrière.
  final PlateCameraSource Function()? cameraFactory;
  final DateTime Function()? clock;

  @override
  State<MotoEntryScreen> createState() => _MotoEntryScreenState();
}

class _MotoEntryScreenState extends State<MotoEntryScreen> {
  final _plateCtrl = TextEditingController();
  bool? _hasHelmet; // null = pas encore répondu
  int _helmets = 1;
  String? _ocrPlate; // numéro tel que lu et confirmé via la caméra
  String? _ocrRaw;
  String? _photoPath;
  bool _verified = false;
  bool _busy = false;
  String? _plateError;
  List<TicketDocument>? _lastTickets; // pour « Réimprimer » si l'impression échoue

  MotoEntrySettings get s => widget.settings;
  int get _helmetCount => _hasHelmet == true ? _helmets : 0;
  int get _total => s.motoPrice + s.helmetPrice * _helmetCount;

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
      autoPrintOnConfirm: s.autoPrintAfterConfirm,
    );
    if (outcome == null || !mounted) return;
    // Nouvelle photo : l'ancienne n'est plus utile.
    if (_photoPath != null && _photoPath != outcome.photoPath) {
      await widget.photoStore.discard(_photoPath);
    }
    setState(() {
      _plateCtrl.text = outcome.plate;
      _ocrPlate = outcome.method == PlateCaptureMethod.ocr ? outcome.plate : null;
      _ocrRaw = outcome.ocrRawText;
      _photoPath = outcome.photoPath;
      _verified = outcome.verified;
      _plateError = null;
    });
    if (outcome.printNow) await _saveAndPrint();
  }

  Future<void> _saveAndPrint() async {
    if (_busy) return;
    final raw = _plateCtrl.text.trim();
    final plate = raw.isEmpty ? '' : (widget.ocr.parser.formatManualEntry(raw) ?? raw.toUpperCase());
    if (plate.isEmpty && !s.allowEmptyPlate) {
      setState(() => _plateError = 'Numéro obligatoire : photographiez ou saisissez la plaque.');
      return;
    }
    setState(() {
      _busy = true;
      _plateError = null;
    });
    try {
      final now = (widget.clock ?? DateTime.now)();
      final base = await widget.repository.nextTicketBase();
      final method = _method;
      final keptPhoto = await widget.photoStore.finalize(_photoPath, ticketBase: base);
      _photoPath = null;
      final session = MotoParkingSession(
        ticketBase: base,
        enteredAt: now,
        helmetCount: _helmetCount,
        motoPrice: s.motoPrice,
        helmetPrice: s.helmetPrice,
        licensePlate: plate,
        plateCaptureMethod: method,
        // Saisie manuelle = le gardien a tapé le numéro lui-même.
        plateVerified: plate.isNotEmpty && (_verified || method == PlateCaptureMethod.manual),
        plateOcrRawText: s.keepOcrRawText ? _ocrRaw : null,
        platePhotoPath: keptPhoto,
      );
      final id = await widget.repository.save(session);
      final tickets = MotoTicketBuilder(s).buildAll(session.copyWith(id: id));
      _lastTickets = tickets;
      await widget.printer.printTickets(tickets);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green.shade700,
        content: Text('Moto enregistrée — ${tickets.length} tickets imprimés'),
      ));
      Navigator.of(context).pop(session.copyWith(id: id));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showPrintError(e);
    }
  }

  void _showPrintError(Object e) {
    final saved = _lastTickets != null;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(saved ? 'Impression échouée' : 'Enregistrement échoué'),
        content: Text(saved
            ? 'La moto est enregistrée, mais l\'imprimante n\'a pas répondu.\nVérifiez le papier et la connexion.'
            : 'Erreur : $e'),
        actions: [
          if (saved)
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await widget.printer.printTickets(_lastTickets!);
                  if (mounted) Navigator.of(context).pop();
                } catch (err) {
                  if (mounted) _showPrintError(err);
                }
              },
              child: const Text('RÉIMPRIMER'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (saved) Navigator.of(context).pop();
            },
            child: Text(saved ? 'FERMER' : 'OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _photoPath != null) widget.photoStore.discard(_photoPath);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Entrée MOTO')),
        body: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Casque déposé ?', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _choice('OUI', _hasHelmet == true, () => setState(() => _hasHelmet = true),
                    key: const Key('helmet-yes'))),
                const SizedBox(width: 12),
                Expanded(child: _choice('NON', _hasHelmet == false, () => setState(() => _hasHelmet = false),
                    key: const Key('helmet-no'))),
              ]),
              if (_hasHelmet == true) ...[
                const SizedBox(height: 16),
                Text('Nombre de casques', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton.filledTonal(
                    key: const Key('helmet-minus'),
                    iconSize: 32,
                    onPressed: _helmets > 1 ? () => setState(() => _helmets--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text('$_helmets', key: const Key('helmet-count'),
                        style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  IconButton.filledTonal(
                    key: const Key('helmet-plus'),
                    iconSize: 32,
                    onPressed: _helmets < s.maxHelmets ? () => setState(() => _helmets++) : null,
                    icon: const Icon(Icons.add),
                  ),
                ]),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 64,
                child: FilledButton.icon(
                  key: const Key('photo-plate'),
                  onPressed: _photograph,
                  icon: const Icon(Icons.photo_camera, size: 28),
                  label: const Text('PHOTOGRAPHIER LA PLAQUE',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('plate-field'),
                controller: _plateCtrl,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [UpperCaseTextFormatter()],
                onChanged: (_) => setState(() => _plateError = null),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
                decoration: InputDecoration(
                  labelText: 'Numéro d\'immatriculation',
                  hintText: '11 AB 2345',
                  border: const OutlineInputBorder(),
                  errorText: _plateError,
                  helperText: switch (_method) {
                    PlateCaptureMethod.ocr => 'Lu par la caméra et vérifié',
                    PlateCaptureMethod.manual => 'Saisi à la main',
                    PlateCaptureMethod.none =>
                      s.allowEmptyPlate ? 'Facultatif dans ce parking' : 'Obligatoire',
                  },
                  suffixIcon: _method == PlateCaptureMethod.ocr
                      ? const Icon(Icons.verified, color: Colors.green)
                      : null,
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    _amount('Moto', s.motoPrice),
                    if (_helmetCount > 0) _amount('Casque × $_helmetCount', s.helmetPrice * _helmetCount),
                    const Divider(),
                    _amount('Montant du stationnement', _total, bold: true, key: const Key('total-amount')),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 64,
                child: FilledButton.icon(
                  key: const Key('save-print'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                  onPressed: _hasHelmet == null || _busy ? null : _saveAndPrint,
                  icon: _busy
                      ? const SizedBox(width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                      : const Icon(Icons.print, size: 28),
                  label: const Text('ENREGISTRER ET IMPRIMER',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
              if (_hasHelmet == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Indiquez d\'abord si un casque est déposé.', textAlign: TextAlign.center),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choice(String label, bool selected, VoidCallback onTap, {Key? key}) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 60,
      child: selected
          ? FilledButton(key: key, onPressed: onTap,
              child: Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))
          : OutlinedButton(key: key, onPressed: onTap,
              style: OutlinedButton.styleFrom(side: BorderSide(color: scheme.outline, width: 2)),
              child: Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
    );
  }

  Widget _amount(String label, int value, {bool bold = false, Key? key}) {
    final style = TextStyle(fontSize: bold ? 20 : 16, fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text('$value ${s.currency}', key: key, style: style),
      ]),
    );
  }
}
