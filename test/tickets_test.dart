import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:parkfaso_plaque/plaque/plate_models.dart';
import 'package:parkfaso_plaque/tickets/tickets.dart';

void main() {
  final when = DateTime(2026, 10, 21, 8, 35);
  ParkingSession session({String plate = '11 AB 2345', int helmets = 1, VehicleType type = VehicleType.moto}) =>
      ParkingSession(
        vehicleType: type,
        ticketBase: 'PK-000125',
        enteredAt: when,
        helmetCount: helmets,
        vehiclePrice: 100,
        helmetPrice: 0,
        licensePlate: plate,
        plateCaptureMethod: PlateCaptureMethod.ocr,
        plateVerified: true,
      );
  ParkingSettings settings(PaperWidth w) => ParkingSettings(parkingName: 'Parking Central', paperWidth: w);

  test('phase 1 : ticket client seul ; phase 2 : véhicule + casques au choix', () {
    final b = TicketBuilder(settings(PaperWidth.mm58));
    expect(b.buildClient(session()).number, 'PK-000125-C');
    expect(b.buildSecondary(session(helmets: 2)).map((t) => t.number),
        ['PK-000125-M', 'PK-000125-H1', 'PK-000125-H2']);
    expect(b.buildSecondary(session(helmets: 2), helmets: false).map((t) => t.number), ['PK-000125-M']);
    expect(b.buildSecondary(session(helmets: 2), vehicle: false).length, 2);
  });

  test('suffixe du ticket véhicule selon le type', () {
    final b = TicketBuilder(settings(PaperWidth.mm58));
    expect(b.buildVehicle(session(type: VehicleType.voiture)).number, 'PK-000125-V');
    expect(b.buildVehicle(session(type: VehicleType.tricycle)).number, 'PK-000125-T');
    expect(b.buildVehicle(session(type: VehicleType.velo, plate: '')).number, 'PK-000125-B');
  });

  for (final paper in PaperWidth.values) {
    group('Papier ${paper.label}', () {
      final r = TicketTextRenderer(paper);
      final tickets = TicketBuilder(settings(paper)).buildAll(session());

      test('ticket court : 9 lignes max, QR compris', () {
        for (final t in tickets) {
          expect(r.render(t).length, lessThanOrEqualTo(9), reason: r.render(t).join('\n'));
          expect(r.render(t), contains(contains('[QR CODE]')));
        }
      });

      test('plaque sur chaque ticket et dans chaque QR', () {
        for (final t in tickets) {
          expect(r.render(t).join('\n'), contains('11 AB 2345'), reason: t.number);
          expect(t.qrData, contains('11AB2345'));
        }
      });

      test('aucune ligne ne dépasse la largeur du papier', () {
        for (final t in tickets) {
          for (final l in t.lines) {
            final width = l.large ? paper.charsPerLine ~/ 2 : paper.charsPerLine;
            for (final out in r.renderLine(l)) {
              expect(out.length, lessThanOrEqualTo(width), reason: '"$out" (${t.number})');
            }
          }
        }
      });

      test('ESC/POS : texte, QR natif, coupe', () {
        final bytes = EscPosTicketEncoder(paper).encode(tickets.first);
        final text = latin1.decode(bytes);
        expect(text, contains('11 AB 2345'));
        expect(text, contains('PKF1|PK-000125-C|11AB2345|2026-10-21T08:35'));
        expect(_indexOf(bytes, [0x1D, 0x28, 0x6B, 4, 0, 0x31, 0x41]), greaterThan(0));
        expect(_indexOf(bytes, [0x1D, 0x21, 0x11]), greaterThan(0), reason: 'plaque en double taille');
        expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 0x42, 0x00]);
      });
    });
  }

  test('ticket client 58 mm (relecture humaine)', () {
    final b = TicketBuilder(settings(PaperWidth.mm58));
    final r = TicketTextRenderer(PaperWidth.mm58);
    for (final t in b.buildAll(session())) {
      // ignore: avoid_print
      print('${r.render(t).join('\n')}\n');
    }
    final client = r.render(b.buildClient(session())).join('\n');
    for (final e in ['PARKFASO - PARKING CENTRAL', 'TICKET CLIENT', 'PK-000125-C', 'MOTO',
      '21/10/2026 08:35', 'CASQUE: 1', 'TOTAL 100 FCFA', 'CONSERVEZ CE TICKET']) {
      expect(client, contains(e));
    }
  });

  test('sans plaque : pas de ligne vide, QR sans plaque', () {
    final t = TicketBuilder(settings(PaperWidth.mm58)).buildClient(session(plate: '', helmets: 0));
    expect(t.lines.where((l) => l.large), isEmpty);
    expect(t.qrData, 'PKF1|PK-000125-C||2026-10-21T08:35');
  });

  group('Lecture du QR (scan)', () {
    test('QR client, véhicule, casque', () {
      final c = TicketQr.tryParse('PKF1|PK-000125-C|11AB2345|2026-10-21T08:35')!;
      expect(c.ticketBase, 'PK-000125');
      expect(c.kind, TicketKind.client);
      expect(c.plate, '11AB2345');
      expect(c.enteredAt, DateTime(2026, 10, 21, 8, 35));
      expect(TicketQr.tryParse('PKF1|PK-000125-M|11AB2345|2026-10-21T08:35')!.kind, TicketKind.vehicule);
      final h = TicketQr.tryParse('PKF1|PK-000125-H2||2026-10-21T08:35')!;
      expect(h.kind, TicketKind.casque);
      expect(h.helmetIndex, 2);
    });

    test('numéro saisi à la main', () {
      expect(TicketQr.tryParse('pk-000125-c')!.ticketBase, 'PK-000125');
      expect(TicketQr.tryParse('PK125')!.ticketBase, 'PK-000125');
      expect(TicketQr.tryParse(' PK-000125 ')!.kind, TicketKind.client);
    });

    test('code étranger refusé', () {
      expect(TicketQr.tryParse('https://exemple.com'), isNull);
      expect(TicketQr.tryParse('PKF1|abc'), isNull);
      expect(TicketQr.tryParse(''), isNull);
    });

    test('aller-retour : chaque ticket imprimé se relit', () {
      for (final t in TicketBuilder(settings(PaperWidth.mm58)).buildAll(session(helmets: 2))) {
        final q = TicketQr.tryParse(t.qrData)!;
        expect(q.ticketNumber, t.number);
        expect(q.ticketBase, 'PK-000125');
      }
    });
  });

  test('imprimante octets bruts : envois dans l\'ordre', () async {
    final sent = <List<int>>[];
    final printer = EscPosBytesPrinter((b) async => sent.add(b), PaperWidth.mm58);
    await printer.printTickets(TicketBuilder(settings(PaperWidth.mm58)).buildAll(session()));
    expect(sent, hasLength(3));
    expect(latin1.decode(sent[2]), contains('CASQUE 01/01'));
  });
}

int _indexOf(List<int> hay, List<int> needle) {
  for (var i = 0; i + needle.length <= hay.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}
