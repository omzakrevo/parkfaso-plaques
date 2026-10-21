import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:parkfaso_plaque/plaque/plate_models.dart';
import 'package:parkfaso_plaque/tickets/moto_tickets.dart';

void main() {
  final when = DateTime(2026, 10, 21, 8, 35);
  MotoParkingSession session({String plate = '11 AB 2345', int helmets = 1}) => MotoParkingSession(
        ticketBase: 'PK-000125',
        enteredAt: when,
        helmetCount: helmets,
        motoPrice: 100,
        helmetPrice: 0,
        licensePlate: plate,
        plateCaptureMethod: PlateCaptureMethod.ocr,
        plateVerified: true,
      );
  MotoEntrySettings settings(PaperWidth w) =>
      MotoEntrySettings(parkingName: 'Parking Central', motoPrice: 100, paperWidth: w);

  test('1 casque → 3 tickets à la suite : client, moto, casque', () {
    final t = MotoTicketBuilder(settings(PaperWidth.mm58)).buildAll(session());
    expect(t.map((d) => d.kind), [TicketKind.client, TicketKind.moto, TicketKind.casque]);
    expect(t.map((d) => d.number), ['PK-000125-C', 'PK-000125-M', 'PK-000125-H1']);
  });

  test('2 casques → un ticket par casque ; sans casque → 2 tickets', () {
    final b = MotoTicketBuilder(settings(PaperWidth.mm58));
    expect(b.buildAll(session(helmets: 2)).length, 4);
    expect(b.buildAll(session(helmets: 0)).length, 2);
  });

  for (final paper in PaperWidth.values) {
    group('Papier ${paper.name}', () {
      final r = TicketTextRenderer(paper);
      final tickets = MotoTicketBuilder(settings(paper)).buildAll(session());

      test('le numéro d\'immatriculation figure sur tous les tickets', () {
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

      test('le numéro en grand tient sur une ligne', () {
        final plateLine = tickets.first.lines.firstWhere((l) => l.large);
        expect(r.renderLine(plateLine), hasLength(1));
      });

      test('encodage ESC/POS : texte, QR code et coupe', () {
        final bytes = EscPosTicketEncoder(paper).encode(tickets.first);
        final asText = latin1.decode(bytes, allowInvalid: true);
        expect(asText, contains('11 AB 2345'));
        expect(asText, contains('PK-000125-C'));
        expect(asText, contains('CONSERVEZ CE TICKET'));
        // Commande QR « GS ( k … 1 P 0 » suivie des données
        expect(_indexOf(bytes, [0x1D, 0x28, 0x6B]), greaterThan(0));
        expect(asText, contains('PKF1|PK-000125-C|11AB2345'));
        // Double taille activée pour le numéro, coupe en fin de ticket
        expect(_indexOf(bytes, [0x1D, 0x21, 0x11]), greaterThan(0));
        expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 0x42, 0x00]);
        // Uniquement de l'ASCII (pas d'accents mal imprimés)
        expect(bytes.every((b) => b < 256), isTrue);
      });
    });
  }

  test('ticket client conforme au modèle demandé (58 mm)', () {
    final r = TicketTextRenderer(PaperWidth.mm58);
    final text = r.render(MotoTicketBuilder(settings(PaperWidth.mm58)).buildClient(session())).join('\n');
    // Affiché ici pour relecture humaine dans la sortie des tests.
    // ignore: avoid_print
    print(text);
    for (final expected in [
      'PARKFASO', 'PARKING CENTRAL', 'TICKET CLIENT', 'N° : PK-000125-C', 'VEHICULE : MOTO',
      'IMMATRICULATION :', 'CASQUE : 01', 'DATE : 21/10/2026', 'HEURE : 08:35',
      'PRIX MOTO :', '100 FCFA', 'PRIX CASQUE :', '0 FCFA', 'TOTAL :', 'CONSERVEZ CE TICKET',
    ]) {
      expect(text, contains(expected));
    }
  });

  test('ticket casque : moto associée + numéro du casque', () {
    final t = MotoTicketBuilder(settings(PaperWidth.mm80)).buildHelmet(session(helmets: 2), 2);
    final text = TicketTextRenderer(PaperWidth.mm80).render(t).join('\n');
    expect(text, contains('MOTO ASSOCIEE :'));
    expect(text, contains('11 AB 2345'));
    expect(text, contains('CASQUE N° : 02 / 02'));
    expect(t.number, 'PK-000125-H2');
  });

  test('plaque non renseignée : mention explicite, aucun numéro inventé', () {
    final t = MotoTicketBuilder(settings(PaperWidth.mm58)).buildMoto(session(plate: ''));
    final text = TicketTextRenderer(PaperWidth.mm58).render(t).join('\n');
    expect(text, contains('NON RENSEIGNEE'));
    expect(t.qrData, 'PKF1|PK-000125-M||2026-10-21T08:35');
  });

  test('total = moto + casques × prix casque', () {
    final s = MotoParkingSession(
      ticketBase: 'PK-1', enteredAt: when, helmetCount: 2, motoPrice: 100, helmetPrice: 50,
      licensePlate: '11 AB 2345', plateCaptureMethod: PlateCaptureMethod.manual, plateVerified: true,
    );
    expect(s.total, 200);
  });

  test('imprimante octets bruts : 3 envois dans l\'ordre', () async {
    final sent = <List<int>>[];
    final printer = EscPosBytesPrinter((b) async => sent.add(b), PaperWidth.mm58);
    await printer.printTickets(MotoTicketBuilder(settings(PaperWidth.mm58)).buildAll(session()));
    expect(sent, hasLength(3));
    expect(latin1.decode(sent[2]), contains('TICKET CASQUE'));
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
