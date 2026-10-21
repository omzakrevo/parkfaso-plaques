import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:parkfaso_plaque/plaque/plate_models.dart';
import 'package:parkfaso_plaque/tickets/bluetooth_printer.dart';
import 'package:parkfaso_plaque/tickets/tickets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Imprimante Bluetooth simulée.
class FakeBtApi implements BluetoothPrinterApi {
  bool permission = true;
  bool enabled = true;
  bool connected = false;
  int connectFailures = 0;
  int writeFailures = 0;
  final writes = <List<int>>[];
  final connectCalls = <String>[];

  @override
  Future<bool> permissionGranted() async => permission;
  @override
  Future<bool> bluetoothEnabled() async => enabled;
  @override
  Future<List<BtDevice>> pairedDevices() async =>
      const [BtDevice('MTP-II', '00:11:22:33:44:55'), BtDevice('Casque JBL', 'AA:BB:CC:DD:EE:FF')];
  @override
  Future<bool> isConnected() async => connected;
  @override
  Future<bool> connect(String address) async {
    connectCalls.add(address);
    if (connectFailures > 0) {
      connectFailures--;
      return false;
    }
    connected = true;
    return true;
  }

  @override
  Future<bool> disconnect() async {
    connected = false;
    return true;
  }

  @override
  Future<bool> write(List<int> bytes) async {
    if (writeFailures > 0) {
      writeFailures--;
      connected = false;
      return false;
    }
    writes.add(bytes);
    return true;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final ticket = TicketBuilder(const ParkingSettings(parkingName: 'P')).buildClient(ParkingSession(
    vehicleType: VehicleType.moto, ticketBase: 'PK-000001', enteredAt: DateTime(2026, 10, 21, 8),
    helmetCount: 0, vehiclePrice: 100, helmetPrice: 0, licensePlate: '11 AB 2345',
    plateCaptureMethod: PlateCaptureMethod.ocr, plateVerified: true,
  ));

  test('choisir une imprimante : connexion + mémorisation', () async {
    final api = FakeBtApi();
    final p = BluetoothThermalPrinter(api: api);
    await p.load();
    expect(p.state, PrinterState.notConfigured);
    final devices = await p.pairedDevices();
    await p.select(devices.first, paper: PaperWidth.mm80);
    expect(p.state, PrinterState.connected);
    expect(api.connectCalls.last, '00:11:22:33:44:55');

    // Au prochain démarrage, l'imprimante est retrouvée et reconnectée.
    final api2 = FakeBtApi();
    final p2 = BluetoothThermalPrinter(api: api2);
    await p2.load();
    await Future<void>.delayed(Duration.zero);
    expect(p2.device!.name, 'MTP-II');
    expect(p2.paper, PaperWidth.mm80);
    expect(api2.connectCalls, ['00:11:22:33:44:55']);
  });

  test('impression : octets ESC/POS envoyés à l\'imprimante', () async {
    final api = FakeBtApi();
    final p = BluetoothThermalPrinter(api: api);
    await p.select(const BtDevice('MTP-II', '00:11:22:33:44:55'));
    await p.printTickets([ticket]);
    expect(api.writes, hasLength(1));
    expect(latin1.decode(api.writes.single), contains('11 AB 2345'));
  });

  test('imprimante en veille : reconnexion automatique', () async {
    final api = FakeBtApi();
    final p = BluetoothThermalPrinter(api: api);
    await p.select(const BtDevice('MTP-II', '00:11:22:33:44:55'));
    api.connected = false;
    api.connectFailures = 1; // 1re tentative ratée, 2e réussie
    await p.printTickets([ticket]);
    expect(api.writes, hasLength(1));
  });

  test('connexion perdue pendant l\'envoi : on renvoie le ticket', () async {
    final api = FakeBtApi();
    final p = BluetoothThermalPrinter(api: api);
    await p.select(const BtDevice('MTP-II', '00:11:22:33:44:55'));
    api.writeFailures = 1;
    await p.printTickets([ticket, ticket]);
    expect(api.writes, hasLength(2));
  });

  test('imprimante éteinte : message clair', () async {
    final api = FakeBtApi();
    final p = BluetoothThermalPrinter(api: api);
    await p.select(const BtDevice('MTP-II', '00:11:22:33:44:55'));
    api.connected = false;
    api.connectFailures = 5;
    await expectLater(p.printTickets([ticket]),
        throwsA(isA<PrinterException>().having((e) => e.message, 'message', contains('allumée'))));
    expect(p.state, PrinterState.disconnected);
  });

  test('Bluetooth coupé ou refusé : messages clairs', () async {
    final api = FakeBtApi()..enabled = false;
    final p = BluetoothThermalPrinter(api: api);
    await expectLater(p.pairedDevices(),
        throwsA(isA<PrinterException>().having((e) => e.message, 'm', contains('désactivé'))));
    api
      ..enabled = true
      ..permission = false;
    await expectLater(p.pairedDevices(),
        throwsA(isA<PrinterException>().having((e) => e.message, 'm', contains('Autorisation'))));
  });

  test('aucune imprimante choisie', () async {
    final p = BluetoothThermalPrinter(api: FakeBtApi());
    await expectLater(p.printTickets([ticket]), throwsA(isA<PrinterException>()));
  });

  test('ticket de test', () async {
    final api = FakeBtApi();
    final p = BluetoothThermalPrinter(api: api);
    await p.select(const BtDevice('MTP-II', '00:11:22:33:44:55'));
    await p.printTest('Parking Central');
    expect(latin1.decode(api.writes.single), contains('IMPRIMANTE PRETE'));
  });

  test('oublier l\'imprimante', () async {
    final p = BluetoothThermalPrinter(api: FakeBtApi());
    await p.select(const BtDevice('MTP-II', '00:11:22:33:44:55'));
    await p.forget();
    expect(p.isConfigured, isFalse);
    final p2 = BluetoothThermalPrinter(api: FakeBtApi());
    await p2.load();
    expect(p2.isConfigured, isFalse);
  });
}
