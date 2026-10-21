// PARKFASO — Tickets thermiques moto (client, moto, casques) avec immatriculation.
//
// Le ticket est décrit ligne par ligne (TicketDocument), puis :
//   • rendu en texte (aperçu, tests) avec [TicketTextRenderer] ;
//   • encodé en ESC/POS avec [EscPosTicketEncoder] pour les imprimantes 58/80 mm.
// Si PARKFASO a déjà son module d'impression, il suffit de lui passer les
// TicketDocument (ou les octets ESC/POS) via [TicketPrinter].

import 'dart:convert';

import '../plaque/plate_models.dart';

enum TicketKind { client, moto, casque }

enum TicketAlign { left, center, right }

class TicketLine {
  const TicketLine(this.text,
      {this.align = TicketAlign.left, this.bold = false, this.large = false})
      : _rule = false;

  /// Ligne séparatrice remplie avec [char] sur toute la largeur.
  const TicketLine.rule(String char)
      : text = char,
        align = TicketAlign.left,
        bold = false,
        large = false,
        _rule = true;

  /// Libellé à gauche, valeur à droite : « PRIX MOTO :      100 FCFA ».
  const TicketLine.pair(String label, String value)
      : text = '$label\u0000$value',
        align = TicketAlign.left,
        bold = false,
        large = false,
        _rule = false;

  const TicketLine.blank()
      : text = '',
        align = TicketAlign.left,
        bold = false,
        large = false,
        _rule = false;

  final String text;
  final TicketAlign align;
  final bool bold;

  /// Double largeur + double hauteur (numéro d'immatriculation).
  final bool large;
  final bool _rule;

  bool get isRule => _rule;
  bool get isPair => text.contains('\u0000');
}

class TicketDocument {
  const TicketDocument({
    required this.kind,
    required this.number,
    required this.lines,
    required this.qrData,
    required this.footer,
  });

  final TicketKind kind;
  final String number;
  final List<TicketLine> lines;
  final String qrData;
  final List<TicketLine> footer;
}

String _two(int n) => n.toString().padLeft(2, '0');
String formatDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';
String formatTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// Construit les tickets d'une entrée moto : client + moto + un ticket par casque.
class MotoTicketBuilder {
  const MotoTicketBuilder(this.settings);

  final MotoEntrySettings settings;

  static const plateMissing = 'NON RENSEIGNEE';

  List<TicketDocument> buildAll(MotoParkingSession s) => [
        buildClient(s),
        buildMoto(s),
        for (var i = 1; i <= s.helmetCount; i++) buildHelmet(s, i),
      ];

  String _money(int v) => '$v ${settings.currency}';
  String _plate(MotoParkingSession s) => s.hasPlate ? s.licensePlate : plateMissing;

  List<TicketLine> _header(String title) => [
        const TicketLine.rule('='),
        TicketLine(settings.brandName, align: TicketAlign.center, bold: true),
        TicketLine(settings.parkingName.toUpperCase(), align: TicketAlign.center),
        const TicketLine.rule('='),
        TicketLine(title, align: TicketAlign.center, bold: true),
        const TicketLine.blank(),
      ];

  List<TicketLine> _plateBlock(MotoParkingSession s, {String label = 'IMMATRICULATION :'}) => [
        TicketLine(label),
        TicketLine(_plate(s), align: TicketAlign.center, bold: true, large: s.hasPlate),
        const TicketLine.blank(),
      ];

  List<TicketLine> _dateBlock(MotoParkingSession s) => [
        TicketLine('DATE : ${formatDate(s.enteredAt)}'),
        TicketLine('HEURE : ${formatTime(s.enteredAt)}'),
        const TicketLine.blank(),
      ];

  /// Contenu du QR : compact, lisible par le module de sortie de PARKFASO.
  String qrPayload(MotoParkingSession s, String number) => [
        'PKF1',
        number,
        s.licensePlate.replaceAll(' ', ''),
        s.enteredAt.toIso8601String().substring(0, 16),
      ].join('|');

  TicketDocument buildClient(MotoParkingSession s) {
    final number = '${s.ticketBase}-C';
    return TicketDocument(
      kind: TicketKind.client,
      number: number,
      qrData: qrPayload(s, number),
      lines: [
        ..._header('TICKET CLIENT'),
        TicketLine('N° : $number'),
        const TicketLine.blank(),
        const TicketLine('VEHICULE : MOTO'),
        ..._plateBlock(s),
        TicketLine('CASQUE : ${_two(s.helmetCount)}'),
        const TicketLine.blank(),
        ..._dateBlock(s),
        const TicketLine.rule('-'),
        TicketLine.pair('PRIX MOTO :', _money(s.motoPrice)),
        TicketLine.pair('PRIX CASQUE :', _money(s.helmetPrice * s.helmetCount)),
        const TicketLine.rule('-'),
        TicketLine.pair('TOTAL :', _money(s.total)),
        const TicketLine.rule('-'),
      ],
      footer: const [
        TicketLine('CONSERVEZ CE TICKET', align: TicketAlign.center, bold: true),
        TicketLine.rule('='),
      ],
    );
  }

  TicketDocument buildMoto(MotoParkingSession s) {
    final number = '${s.ticketBase}-M';
    return TicketDocument(
      kind: TicketKind.moto,
      number: number,
      qrData: qrPayload(s, number),
      lines: [
        ..._header('TICKET MOTO'),
        TicketLine('N° : $number'),
        const TicketLine.blank(),
        ..._plateBlock(s),
        ..._dateBlock(s),
        const TicketLine.rule('-'),
        TicketLine.pair('PRIX MOTO :', _money(s.motoPrice)),
        const TicketLine.rule('-'),
      ],
      footer: const [
        TicketLine('A LAISSER SUR LA MOTO', align: TicketAlign.center, bold: true),
        TicketLine.rule('='),
      ],
    );
  }

  TicketDocument buildHelmet(MotoParkingSession s, int index) {
    final number = '${s.ticketBase}-H$index';
    return TicketDocument(
      kind: TicketKind.casque,
      number: number,
      qrData: qrPayload(s, number),
      lines: [
        ..._header('TICKET CASQUE'),
        TicketLine('N° : $number'),
        const TicketLine.blank(),
        ..._plateBlock(s, label: 'MOTO ASSOCIEE :'),
        TicketLine('CASQUE N° : ${_two(index)} / ${_two(s.helmetCount)}', bold: true),
        const TicketLine.blank(),
        ..._dateBlock(s),
        const TicketLine.rule('-'),
        TicketLine.pair('PRIX CASQUE :', _money(s.helmetPrice)),
        const TicketLine.rule('-'),
      ],
      footer: const [
        TicketLine('A FIXER SUR LE CASQUE', align: TicketAlign.center, bold: true),
        TicketLine.rule('='),
      ],
    );
  }
}

/// Supprime les accents : les imprimantes thermiques bon marché n'ont souvent
/// pas la bonne page de code (« N° » reste lisible, le reste passe en ASCII).
String toPrinterAscii(String s) {
  const map = {
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'à': 'a', 'â': 'a', 'î': 'i', 'ï': 'i',
    'ô': 'o', 'ù': 'u', 'û': 'u', 'ç': 'c', 'É': 'E', 'È': 'E', 'Ê': 'E', 'À': 'A',
    'Ç': 'C', 'Ô': 'O', '°': 'o',
  };
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(map[ch] ?? (ch.codeUnitAt(0) < 128 ? ch : '?'));
  }
  return b.toString();
}

/// Rendu texte d'un ticket (aperçu à l'écran, tests de mise en page).
class TicketTextRenderer {
  const TicketTextRenderer(this.paper);

  final PaperWidth paper;

  List<String> render(TicketDocument doc) => [
        for (final l in doc.lines) ...renderLine(l),
        '',
        _center('[QR CODE]', paper.charsPerLine),
        '',
        for (final l in doc.footer) ...renderLine(l),
      ];

  List<String> renderLine(TicketLine l) {
    final width = l.large ? paper.charsPerLine ~/ 2 : paper.charsPerLine;
    if (l.isRule) return [l.text * paper.charsPerLine];
    if (l.isPair) {
      final parts = l.text.split('\u0000');
      final gap = width - parts[0].length - parts[1].length;
      return [gap >= 1 ? '${parts[0]}${' ' * gap}${parts[1]}' : '${parts[0]} ${parts[1]}'];
    }
    return _wrap(l.text, width).map((t) => switch (l.align) {
          TicketAlign.left => t,
          TicketAlign.center => _center(t, width),
          TicketAlign.right => t.padLeft(width),
        }).toList();
  }

  static String _center(String t, int width) {
    if (t.length >= width) return t;
    final pad = (width - t.length) ~/ 2;
    return '${' ' * pad}$t';
  }

  static List<String> _wrap(String t, int width) {
    if (t.length <= width) return [t];
    final out = <String>[];
    var rest = t;
    while (rest.length > width) {
      var cut = rest.lastIndexOf(' ', width);
      if (cut <= 0) cut = width;
      out.add(rest.substring(0, cut).trimRight());
      rest = rest.substring(cut).trimLeft();
    }
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }
}

/// Encodeur ESC/POS standard (Epson, Xprinter, Goojprt, Rongta… 58 et 80 mm).
class EscPosTicketEncoder {
  const EscPosTicketEncoder(this.paper, {this.qrModuleSize, this.cut = true});

  final PaperWidth paper;
  final int? qrModuleSize;
  final bool cut;

  static const _esc = 0x1B, _gs = 0x1D;

  List<int> encode(TicketDocument doc) {
    final out = <int>[_esc, 0x40]; // initialisation
    final renderer = TicketTextRenderer(paper);
    void line(TicketLine l) {
      out.addAll([_esc, 0x61, switch (l.align) { TicketAlign.left => 0, TicketAlign.center => 1, TicketAlign.right => 2 }]);
      out.addAll([_esc, 0x45, l.bold ? 1 : 0]);
      out.addAll([_gs, 0x21, l.large ? 0x11 : 0x00]);
      // L'alignement est fait par l'imprimante : on envoie le texte non centré.
      final texts = l.align == TicketAlign.left
          ? renderer.renderLine(l)
          : renderer.renderLine(TicketLine(l.text, large: l.large)).map((t) => t.trim());
      for (final t in texts) {
        out.addAll(ascii.encode(toPrinterAscii(t)));
        out.add(0x0A);
      }
    }

    for (final l in doc.lines) {
      line(l);
    }
    out.addAll([_esc, 0x45, 0, _gs, 0x21, 0]);
    out.add(0x0A);
    out.addAll(_qr(doc.qrData));
    out.add(0x0A);
    for (final l in doc.footer) {
      line(l);
    }
    out.addAll([_esc, 0x61, 0, _esc, 0x64, 4]); // avance de 4 lignes
    if (cut) out.addAll([_gs, 0x56, 0x42, 0x00]); // coupe partielle
    return out;
  }

  List<int> _qr(String data) {
    final bytes = ascii.encode(toPrinterAscii(data));
    final size = qrModuleSize ?? (paper == PaperWidth.mm58 ? 5 : 7);
    final len = bytes.length + 3;
    return [
      _esc, 0x61, 1, // centré
      _gs, 0x28, 0x6B, 4, 0, 0x31, 0x41, 0x32, 0x00, // modèle 2
      _gs, 0x28, 0x6B, 3, 0, 0x31, 0x43, size, // taille du module
      _gs, 0x28, 0x6B, 3, 0, 0x31, 0x45, 0x31, // correction d'erreur M
      _gs, 0x28, 0x6B, len & 0xFF, len >> 8, 0x31, 0x50, 0x30, ...bytes, // données
      _gs, 0x28, 0x6B, 3, 0, 0x31, 0x51, 0x30, // impression
    ];
  }
}

/// Impression : branchez votre imprimante PARKFASO existante ici.
abstract class TicketPrinter {
  /// Imprime les tickets à la suite, dans l'ordre reçu.
  Future<void> printTickets(List<TicketDocument> tickets);
}

/// Adaptateur prêt à l'emploi pour toute librairie qui envoie des octets bruts
/// (Bluetooth, USB, réseau) : passez simplement votre fonction d'envoi.
class EscPosBytesPrinter implements TicketPrinter {
  EscPosBytesPrinter(this.send, this.paper);

  final Future<void> Function(List<int> bytes) send;
  final PaperWidth paper;

  @override
  Future<void> printTickets(List<TicketDocument> tickets) async {
    final enc = EscPosTicketEncoder(paper);
    for (final t in tickets) {
      await send(enc.encode(t));
    }
  }
}
