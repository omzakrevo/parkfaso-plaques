// PARKFASO — Imprimante thermique Bluetooth (ESC/POS).
//
// Compatible avec les imprimantes Bluetooth « classiques » (SPP) vendues au
// Burkina : MTP-II, Goojprt PT-210, Xprinter XP-P300/P323, Rongta, Sunmi…
// L'imprimante doit d'abord être appairée dans les réglages Bluetooth du
// téléphone (code habituel : 0000 ou 1234).

import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../plaque/plate_models.dart';
import 'tickets.dart';

class BtDevice {
  const BtDevice(this.name, this.address);
  final String name;
  final String address;
}

class PrinterException implements Exception {
  const PrinterException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Accès Bluetooth (remplaçable dans les tests).
abstract class BluetoothPrinterApi {
  Future<bool> permissionGranted();
  Future<bool> bluetoothEnabled();
  Future<List<BtDevice>> pairedDevices();
  Future<bool> isConnected();
  Future<bool> connect(String address);
  Future<bool> disconnect();
  Future<bool> write(List<int> bytes);
}

class PluginBluetoothApi implements BluetoothPrinterApi {
  @override
  Future<bool> permissionGranted() => PrintBluetoothThermal.isPermissionBluetoothGranted;
  @override
  Future<bool> bluetoothEnabled() => PrintBluetoothThermal.bluetoothEnabled;
  @override
  Future<List<BtDevice>> pairedDevices() async => [
        for (final d in await PrintBluetoothThermal.pairedBluetooths) BtDevice(d.name, d.macAdress),
      ];
  @override
  Future<bool> isConnected() => PrintBluetoothThermal.connectionStatus;
  @override
  Future<bool> connect(String address) => PrintBluetoothThermal.connect(macPrinterAddress: address);
  @override
  Future<bool> disconnect() => PrintBluetoothThermal.disconnect;
  @override
  Future<bool> write(List<int> bytes) => PrintBluetoothThermal.writeBytes(bytes);
}

enum PrinterState { notConfigured, disconnected, connecting, connected, printing }

/// Imprimante choisie + connexion. Mémorise l'imprimante et le papier.
class BluetoothThermalPrinter extends ChangeNotifier implements TicketPrinter {
  BluetoothThermalPrinter({BluetoothPrinterApi? api, this.prefsKey = 'parkfaso.printer'})
      : api = api ?? PluginBluetoothApi();

  final BluetoothPrinterApi api;
  final String prefsKey;

  BtDevice? _device;
  PaperWidth _paper = PaperWidth.mm58;
  PrinterState _state = PrinterState.notConfigured;

  BtDevice? get device => _device;
  PaperWidth get paper => _paper;
  PrinterState get state => _state;
  bool get isConfigured => _device != null;

  void _set(PrinterState s) {
    _state = s;
    notifyListeners();
  }

  /// Recharge l'imprimante mémorisée (à appeler au démarrage).
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final addr = p.getString('$prefsKey.address');
    _paper = PaperWidth.fromName(p.getString('$prefsKey.paper'));
    if (addr != null) {
      _device = BtDevice(p.getString('$prefsKey.name') ?? 'Imprimante', addr);
      _set(PrinterState.disconnected);
      // Connexion en arrière-plan : pas d'attente au démarrage.
      ensureConnected().catchError((_) {});
    } else {
      _set(PrinterState.notConfigured);
    }
  }

  Future<void> _checkBluetooth() async {
    if (!await api.permissionGranted()) {
      throw const PrinterException(
          'Autorisation Bluetooth refusée. Autorisez « Appareils à proximité » pour PARKFASO.');
    }
    if (!await api.bluetoothEnabled()) {
      throw const PrinterException('Le Bluetooth est désactivé. Activez-le puis réessayez.');
    }
  }

  /// Imprimantes appairées dans les réglages Bluetooth du téléphone.
  Future<List<BtDevice>> pairedDevices() async {
    await _checkBluetooth();
    return api.pairedDevices();
  }

  /// Choisit l'imprimante, s'y connecte et la mémorise.
  Future<void> select(BtDevice d, {PaperWidth? paper}) async {
    await _checkBluetooth();
    _device = d;
    if (paper != null) _paper = paper;
    final p = await SharedPreferences.getInstance();
    await p.setString('$prefsKey.address', d.address);
    await p.setString('$prefsKey.name', d.name);
    await p.setString('$prefsKey.paper', _paper.name);
    if (await api.isConnected()) await api.disconnect();
    _set(PrinterState.disconnected);
    await ensureConnected();
  }

  Future<void> setPaper(PaperWidth paper) async {
    _paper = paper;
    final p = await SharedPreferences.getInstance();
    await p.setString('$prefsKey.paper', paper.name);
    notifyListeners();
  }

  Future<void> forget() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('$prefsKey.address');
    await p.remove('$prefsKey.name');
    try {
      await api.disconnect();
    } catch (_) {}
    _device = null;
    _set(PrinterState.notConfigured);
  }

  /// Se (re)connecte si nécessaire : 2 tentatives (imprimante en veille).
  Future<void> ensureConnected() async {
    final d = _device;
    if (d == null) {
      throw const PrinterException('Aucune imprimante choisie. Ouvrez Réglages › Imprimante.');
    }
    if (await api.isConnected()) {
      if (_state != PrinterState.printing) _set(PrinterState.connected);
      return;
    }
    await _checkBluetooth();
    _set(PrinterState.connecting);
    for (var attempt = 0; attempt < 2; attempt++) {
      if (await api.connect(d.address)) {
        _set(PrinterState.connected);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    _set(PrinterState.disconnected);
    throw PrinterException('Impossible de joindre « ${d.name} ». '
        'Vérifiez qu\'elle est allumée et à moins de 10 m.');
  }

  @override
  Future<void> printTickets(List<TicketDocument> tickets) async {
    await ensureConnected();
    _set(PrinterState.printing);
    try {
      final enc = EscPosTicketEncoder(_paper);
      for (final t in tickets) {
        if (!await api.write(enc.encode(t))) {
          // Connexion perdue entre deux tickets : on retente une fois.
          await ensureConnected();
          if (!await api.write(enc.encode(t))) {
            throw const PrinterException('Impression interrompue. Vérifiez le papier et la batterie.');
          }
        }
      }
    } finally {
      _set(await api.isConnected() ? PrinterState.connected : PrinterState.disconnected);
    }
  }

  /// Ticket de test (réglages).
  Future<void> printTest(String parkingName) async {
    final sample = ParkingSession(
      vehicleType: VehicleType.moto,
      ticketBase: 'PK-TEST',
      enteredAt: DateTime.now(),
      helmetCount: 0,
      vehiclePrice: 0,
      helmetPrice: 0,
      licensePlate: '11 AB 2345',
      plateCaptureMethod: PlateCaptureMethod.manual,
      plateVerified: true,
    );
    final doc = TicketBuilder(ParkingSettings(parkingName: parkingName, paperWidth: _paper))
        .buildVehicle(sample);
    await printTickets([
      TicketDocument(
        kind: doc.kind,
        number: doc.number,
        qrData: doc.qrData,
        lines: [...doc.lines, TicketLine('TEST ${_paper.label} OK', align: TicketAlign.center)],
        footer: const [TicketLine('IMPRIMANTE PRETE', align: TicketAlign.center)],
      ),
    ]);
  }
}
