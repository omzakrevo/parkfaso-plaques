// PARKFASO — Accueil gardien : choix du véhicule, scan, imprimante.

import 'package:flutter/material.dart';

import '../plaque/plate_camera_source.dart';
import '../plaque/plate_database.dart';
import '../plaque/plate_models.dart';
import '../plaque/plate_ocr_service.dart';
import '../plaque/plate_photo_store.dart';
import '../plaque/vehicle_entry_screen.dart';
import '../tickets/bluetooth_printer.dart';
import '../tickets/tickets.dart';
import '../tickets/printer_settings_screen.dart';
import '../tickets/ticket_scan_screen.dart';
import 'parkfaso_theme.dart';

class ParkHomeScreen extends StatelessWidget {
  const ParkHomeScreen({
    super.key,
    required this.settings,
    required this.ocr,
    required this.repository,
    required this.printer,
    required this.photoStore,
    this.ticketPrinter,
    this.cameraFactory,
    this.scannerBuilder,
    this.clock,
  });

  final ParkingSettings settings;
  final PlateOcrService ocr;
  final SessionRepository repository;
  final BluetoothThermalPrinter printer;
  final PlatePhotoStore photoStore;

  /// Imprimante utilisée pour les tickets (par défaut : [printer], Bluetooth).
  final TicketPrinter? ticketPrinter;
  final PlateCameraSource Function()? cameraFactory;
  final Widget Function(ValueChanged<String> onCode)? scannerBuilder;
  final DateTime Function()? clock;

  void _openEntry(BuildContext context, VehicleType type) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VehicleEntryScreen(
        vehicleType: type,
        settings: settings.copyWith(paperWidth: printer.paper),
        ocr: ocr,
        repository: repository,
        printer: ticketPrinter ?? printer,
        photoStore: photoStore,
        cameraFactory: cameraFactory,
        clock: clock,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(settings.brandName),
          Text(settings.parkingName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: ParkColors.muted)),
        ]),
        actions: [
          ListenableBuilder(
            listenable: printer,
            builder: (context, _) => IconButton(
              key: const Key('open-printer'),
              tooltip: 'Imprimante',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PrinterSettingsScreen(printer: printer, parkingName: settings.parkingName),
              )),
              icon: PrinterStatusDot(state: printer.state),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          ListenableBuilder(
            listenable: printer,
            builder: (context, _) => printer.isConfigured
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Material(
                      color: ParkColors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.print_disabled_outlined, color: ParkColors.warn),
                        title: const Text('Aucune imprimante', style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: const Text('Touchez pour choisir l\'imprimante Bluetooth'),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PrinterSettingsScreen(printer: printer, parkingName: settings.parkingName),
                        )),
                      ),
                    ),
                  ),
          ),
          const SectionLabel('Nouvelle entrée'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.55,
            children: [
              for (final t in settings.enabledVehicles)
                _VehicleTile(
                  type: t,
                  price: '${settings.priceOf(t)} ${settings.currency}',
                  onTap: () => _openEntry(context, t),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const SectionLabel('Sortie'),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('open-scan'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50), backgroundColor: Colors.white),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TicketScanScreen(
                  service: TicketScanService(repository, clock: clock),
                  currency: settings.currency,
                  scannerBuilder: scannerBuilder,
                ),
              )),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scanner un ticket'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _VehicleTile extends StatelessWidget {
  const _VehicleTile({required this.type, required this.price, required this.onTap});

  final VehicleType type;
  final String price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('vehicle-${type.name}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: ParkColors.navy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(type.icon, color: ParkColors.navy, size: 22),
            ),
            const Spacer(),
            Text(type.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text(price, style: const TextStyle(color: ParkColors.muted, fontSize: 12.5)),
          ]),
        ),
      ),
    );
  }
}
