// Tests exécutés uniquement sous Windows (machine GitHub Actions) : ils
// vérifient les appels système réels du module d'impression et la base SQLite.
@TestOn('windows')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:parkfaso_plaque/core/park_store.dart';
import 'package:parkfaso_plaque/tickets/windows_printer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('liste des imprimantes Windows (spouleur)', () {
    final names = windowsPrinterNames();
    // ignore: avoid_print
    print('Imprimantes trouvées : $names');
    expect(names, isA<List<String>>());
  });

  test('imprimante inexistante : échec propre, sans plantage', () {
    expect(windowsRawPrint('PARKFASO imprimante inexistante', [0x1B, 0x40]), isFalse);
  });

  test('port COM absent : échec propre', () {
    expect(windowsComWrite('COM199', [0x1B, 0x40]), isFalse);
  });

  test('liste des ports COM (registre)', () async {
    final ports = await windowsComPorts();
    expect(ports, isA<List>());
  });

  test('API imprimante : liste sans imprimantes virtuelles (PDF, XPS…)', () async {
    final devices = await WindowsPrinterApi().pairedDevices();
    expect(devices.where((d) => d.name.toLowerCase().contains('pdf')), isEmpty);
  });

  test('base SQLite « bureau » (bibliothèque embarquée)', () async {
    sqfliteFfiInit();
    final db = await openParkDatabase(inMemoryDatabasePath, factory: databaseFactoryFfi, singleInstance: false);
    final store = ParkStore(db);
    final p = await store.createParking('Parking Central');
    expect((await store.parkings()).single.id, p.id);
  });
}
