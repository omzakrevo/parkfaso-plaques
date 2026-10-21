// PARKFASO — Réglages › Imprimante Bluetooth.

import 'package:flutter/material.dart';

import '../app/parkfaso_theme.dart';
import '../plaque/plate_models.dart';
import 'bluetooth_printer.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key, required this.printer, required this.parkingName});

  final BluetoothThermalPrinter printer;
  final String parkingName;

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  List<BtDevice>? _devices;
  String? _error;
  String? _busyAddress;
  bool _loading = false;
  bool _testing = false;

  BluetoothThermalPrinter get p => widget.printer;

  @override
  void initState() {
    super.initState();
    p.addListener(_refresh);
    _scan();
  }

  @override
  void dispose() {
    p.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await p.pairedDevices();
      if (mounted) setState(() => _devices = list);
    } on PrinterException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(BtDevice d) async {
    setState(() {
      _busyAddress = d.address;
      _error = null;
    });
    try {
      await p.select(d);
    } on PrinterException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyAddress = null);
    }
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      await p.printTest(widget.parkingName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: ParkColors.green, content: Text('Ticket de test envoyé')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = p.device;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Imprimante'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading ? null : _scan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SectionLabel('Imprimante active'),
        Card(
          child: ListTile(
            leading: PrinterStatusDot(state: p.state),
            title: Text(current?.name ?? 'Aucune imprimante',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(current == null ? 'Choisissez-en une ci-dessous' : _stateLabel(p.state)),
            trailing: current == null
                ? null
                : TextButton(onPressed: p.forget, child: const Text('Oublier')),
          ),
        ),
        const SizedBox(height: 16),
        const SectionLabel('Largeur du papier'),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<PaperWidth>(
            showSelectedIcon: false,
            segments: [
              for (final w in PaperWidth.values) ButtonSegment(value: w, label: Text(w.label)),
            ],
            selected: {p.paper},
            onSelectionChanged: (v) => p.setPaper(v.first),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('printer-test'),
          onPressed: current == null || _testing ? null : _test,
          icon: _testing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.receipt_long_outlined, size: 18),
          label: const Text('Imprimer un ticket de test'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ParkColors.red.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_error!, style: const TextStyle(color: ParkColors.red)),
          ),
        ],
        const SizedBox(height: 20),
        SectionLabel('Appareils appairés',
            trailing: _loading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : null),
        if (_devices != null && _devices!.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Aucun appareil. Appairez d\'abord l\'imprimante dans les réglages '
                'Bluetooth du téléphone (code 0000 ou 1234), puis actualisez.',
                style: TextStyle(color: ParkColors.muted)),
          ),
        if (_devices != null && _devices!.isNotEmpty)
          Card(
            child: Column(children: [
              for (var i = 0; i < _devices!.length; i++) ...[
                if (i > 0) const Divider(),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.print_outlined),
                  title: Text(_devices![i].name.isEmpty ? 'Sans nom' : _devices![i].name),
                  subtitle: Text(_devices![i].address),
                  trailing: _busyAddress == _devices![i].address
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : current?.address == _devices![i].address
                          ? const Icon(Icons.check_circle, color: ParkColors.green)
                          : null,
                  onTap: _busyAddress == null ? () => _select(_devices![i]) : null,
                ),
              ],
            ]),
          ),
      ]),
    );
  }
}

String _stateLabel(PrinterState s) => switch (s) {
      PrinterState.notConfigured => 'Non configurée',
      PrinterState.disconnected => 'Déconnectée — reconnexion à la prochaine impression',
      PrinterState.connecting => 'Connexion…',
      PrinterState.connected => 'Connectée',
      PrinterState.printing => 'Impression…',
    };

/// Pastille d'état (verte = prête).
class PrinterStatusDot extends StatelessWidget {
  const PrinterStatusDot({super.key, required this.state});
  final PrinterState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      PrinterState.connected || PrinterState.printing => ParkColors.green,
      PrinterState.connecting => ParkColors.amber,
      PrinterState.disconnected => ParkColors.muted,
      PrinterState.notConfigured => ParkColors.red,
    };
    return Stack(alignment: Alignment.bottomRight, children: [
      const Icon(Icons.print_outlined, size: 24),
      Container(width: 9, height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5))),
    ]);
  }
}
