// PARKFASO — Impression des tickets sous Windows (ESC/POS en mode RAW).
//
// Deux façons de joindre l'imprimante thermique depuis un PC :
//  • Imprimante installée dans Windows (USB « POS-58 / POS-80 », « Generic / Text
//    Only », ou imprimante Bluetooth ajoutée dans Windows) : les octets ESC/POS
//    sont envoyés tels quels au spouleur Windows (type de données « RAW »).
//  • Port COM : une imprimante Bluetooth appairée dans Windows crée un port série
//    (ex. COM5) ; les octets y sont écrits directement.
//
// Les appels Windows sont faits dans un isolat séparé : l'interface ne se fige pas
// pendant la connexion Bluetooth (qui peut prendre quelques secondes).

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'bluetooth_printer.dart';

const _printerPrefix = 'printer:';
const _comPrefix = 'com:';

/// Liste les imprimantes installées dans Windows.
List<String> windowsPrinterNames() => using((arena) {
      const flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
      final needed = arena<Uint32>();
      final count = arena<Uint32>();
      EnumPrinters(flags, null, 4, null, 0, needed, count);
      if (needed.value == 0) return <String>[];
      final buf = arena<Uint8>(needed.value);
      final r = EnumPrinters(flags, null, 4, buf, needed.value, needed, count);
      if (!r.value) return <String>[];
      final infos = buf.cast<PRINTER_INFO_4>();
      return [for (var i = 0; i < count.value; i++) (infos + i).ref.pPrinterName.toDartString()];
    });

/// Envoie des octets bruts (ESC/POS) à une imprimante Windows.
bool windowsRawPrint(String printerName, List<int> bytes) => using((arena) {
      final handle = arena<Pointer>();
      if (!OpenPrinter(printerName.toPcwstr(allocator: arena), handle, null).value) return false;
      final h = PRINTER_HANDLE(handle.value);
      try {
        final doc = arena<DOC_INFO_1>();
        doc.ref.pDocName = 'PARKFASO ticket'.toPwstr(allocator: arena);
        doc.ref.pDatatype = 'RAW'.toPwstr(allocator: arena);
        if (StartDocPrinter(h, 1, doc) == 0) return false;
        try {
          StartPagePrinter(h);
          final buf = arena<Uint8>(bytes.length);
          buf.asTypedList(bytes.length).setAll(0, bytes);
          final written = arena<Uint32>();
          final ok = WritePrinter(h, buf, bytes.length, written) && written.value == bytes.length;
          EndPagePrinter(h);
          return ok;
        } finally {
          EndDocPrinter(h);
        }
      } finally {
        ClosePrinter(h);
      }
    });

/// Écrit des octets sur un port COM (imprimante Bluetooth appairée dans Windows).
bool windowsComWrite(String port, List<int> bytes) => using((arena) {
      // Chemin de périphérique Windows : \\.\COM5 (obligatoire au-delà de COM9).
      final path = '\\\\.\\$port';
      final r = CreateFile(path.toPcwstr(allocator: arena), GENERIC_WRITE, FILE_SHARE_NONE, null,
          OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null);
      final h = r.value;
      if (h == INVALID_HANDLE_VALUE || h.address == 0) return false;
      try {
        final buf = arena<Uint8>(bytes.length);
        buf.asTypedList(bytes.length).setAll(0, bytes);
        final written = arena<Uint32>();
        return WriteFile(h, buf, bytes.length, written, null).value && written.value == bytes.length;
      } finally {
        CloseHandle(h);
      }
    });

/// Ports COM présents (registre HARDWARE\DEVICEMAP\SERIALCOMM).
Future<List<BtDevice>> windowsComPorts() async {
  try {
    final r = await Process.run('reg', [r'query', r'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM']);
    final out = <BtDevice>[];
    for (final line in '${r.stdout}'.split('\n')) {
      final m = RegExp(r'^\s*(\S+)\s+REG_SZ\s+(COM\d+)\s*$').firstMatch(line);
      if (m == null) continue;
      final bt = m.group(1)!.toLowerCase().contains('bth');
      out.add(BtDevice('${m.group(2)}${bt ? ' (Bluetooth)' : ' (port série)'}', '$_comPrefix${m.group(2)}'));
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  } catch (_) {
    return const [];
  }
}

/// Imprimante thermique sous Windows, utilisée à la place du Bluetooth Android.
class WindowsPrinterApi implements BluetoothPrinterApi {
  String? _address;

  @override
  Future<bool> permissionGranted() async => true;

  @override
  Future<bool> bluetoothEnabled() async => true;

  @override
  Future<List<BtDevice>> pairedDevices() async {
    final printers = await Isolate.run(windowsPrinterNames);
    // Les imprimantes virtuelles (PDF, OneNote, Fax…) ne savent pas lire l'ESC/POS.
    final virtual = RegExp(r'pdf|xps|onenote|fax|anydesk|send to', caseSensitive: false);
    return [
      for (final p in printers)
        if (!virtual.hasMatch(p)) BtDevice(p, '$_printerPrefix$p'),
      ...await windowsComPorts(),
    ];
  }

  @override
  Future<bool> isConnected() async => _address != null;

  @override
  Future<bool> connect(String address) async {
    if (address.startsWith(_printerPrefix)) {
      final name = address.substring(_printerPrefix.length);
      final ok = (await Isolate.run(windowsPrinterNames)).contains(name);
      _address = ok ? address : null;
      return ok;
    }
    if (address.startsWith(_comPrefix)) {
      final ok = (await windowsComPorts()).any((d) => d.address == address);
      _address = ok ? address : null;
      return ok;
    }
    return false;
  }

  @override
  Future<bool> disconnect() async {
    _address = null;
    return true;
  }

  @override
  Future<bool> write(List<int> bytes) async {
    final a = _address;
    if (a == null) return false;
    final data = List<int>.from(bytes);
    if (a.startsWith(_comPrefix)) {
      final port = a.substring(_comPrefix.length);
      return Isolate.run(() => windowsComWrite(port, data));
    }
    final name = a.substring(_printerPrefix.length);
    return Isolate.run(() => windowsRawPrint(name, data));
  }
}
