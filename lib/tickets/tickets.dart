// PARKFASO — Tickets thermiques courts (client, véhicule, casques) avec QR code.
//
// Le ticket est décrit ligne par ligne (TicketDocument), puis :
//   • rendu en texte (aperçu, tests) avec [TicketTextRenderer] ;
//   • encodé en ESC/POS avec [EscPosTicketEncoder] pour les imprimantes 58/80 mm.

import 'dart:convert';

import '../plaque/plate_models.dart';

enum TicketKind { client, vehicule, casque }

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

  /// Texte à gauche, texte à droite sur la même ligne.
  const TicketLine.pair(String label, String value, {this.bold = false})
      : text = '$label\u0000$value',
        align = TicketAlign.left,
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
String formatDateTime(DateTime d) => '${formatDate(d)} ${formatTime(d)}';

/// Contenu du QR code d'un ticket : `PKF1|PK-000125-C|11AB2345|2026-10-21T08:35`.
class TicketQr {
  const TicketQr({
    required this.ticketNumber,
    required this.ticketBase,
    required this.kind,
    required this.plate,
    this.enteredAt,
    this.helmetIndex,
  });

  final String ticketNumber;
  final String ticketBase;
  final TicketKind kind;

  /// Plaque compacte (sans espaces), vide si non renseignée.
  final String plate;
  final DateTime? enteredAt;
  final int? helmetIndex;

  static String encode(String number, ParkingSession s) => [
        'PKF1',
        number,
        s.licensePlate.replaceAll(' ', ''),
        s.enteredAt.toIso8601String().substring(0, 16),
      ].join('|');

  /// Lit un QR PARKFASO, ou un numéro saisi à la main (« PK-000125-C », « pk000125 »).
  /// Retourne null si le code n'est pas un ticket PARKFASO.
  static TicketQr? tryParse(String raw) {
    final code = raw.trim();
    String number;
    var plate = '';
    DateTime? at;
    if (code.startsWith('PKF1|')) {
      final parts = code.split('|');
      if (parts.length < 4) return null;
      number = parts[1];
      plate = parts[2];
      at = DateTime.tryParse(parts[3]);
    } else {
      number = code.toUpperCase().replaceAll(' ', '');
    }
    final m = RegExp(r'^([A-Z]{1,4})-?(\d{3,9})(?:-([A-Z])(\d{0,2}))?$').firstMatch(number);
    if (m == null) return null;
    final base = '${m.group(1)}-${m.group(2)!.padLeft(6, '0')}';
    final suffix = m.group(3);
    final kind = switch (suffix) {
      'H' => TicketKind.casque,
      null || 'C' => TicketKind.client,
      _ => TicketKind.vehicule,
    };
    final idx = suffix == 'H' ? int.tryParse(m.group(4) ?? '') : null;
    return TicketQr(
      ticketNumber: suffix == null ? base : '$base-$suffix${m.group(4) ?? ''}',
      ticketBase: base,
      kind: kind,
      plate: plate,
      enteredAt: at,
      helmetIndex: idx,
    );
  }
}

/// Construit les tickets d'une entrée : client (imprimé tout de suite),
/// puis véhicule et casques (imprimés seulement si le gardien le décide).
class TicketBuilder {
  const TicketBuilder(this.settings);

  final ParkingSettings settings;

  List<TicketDocument> buildAll(ParkingSession s) => [buildClient(s), ...buildSecondary(s)];

  /// Tickets de la 2e phase : véhicule + un ticket par casque.
  List<TicketDocument> buildSecondary(ParkingSession s, {bool vehicle = true, bool helmets = true}) => [
        if (vehicle) buildVehicle(s),
        if (helmets)
          for (var i = 1; i <= s.helmetCount; i++) buildHelmet(s, i),
      ];

  String _money(int v) => '$v ${settings.currency}';

  List<TicketLine> get _header => [
        TicketLine('${settings.brandName} - ${settings.parkingName.toUpperCase()}',
            align: TicketAlign.center, bold: true),
        const TicketLine.rule('-'),
      ];

  List<TicketLine> _plate(ParkingSession s) => s.hasPlate
      ? [TicketLine(s.licensePlate, align: TicketAlign.center, bold: true, large: true)]
      : const [];

  TicketDocument buildClient(ParkingSession s) {
    final number = '${s.ticketBase}-C';
    final label = s.vehicleType.label.toUpperCase().replaceAll('É', 'E');
    return TicketDocument(
      kind: TicketKind.client,
      number: number,
      qrData: TicketQr.encode(number, s),
      lines: [
        ..._header,
        TicketLine.pair('TICKET CLIENT', number, bold: true),
        TicketLine.pair(label, formatDateTime(s.enteredAt)),
        ..._plate(s),
        if (s.helmetCount > 0)
          TicketLine.pair('CASQUE: ${s.helmetCount}', 'TOTAL ${_money(s.total)}', bold: true)
        else
          TicketLine.pair('TOTAL', _money(s.total), bold: true),
      ],
      footer: const [TicketLine('CONSERVEZ CE TICKET', align: TicketAlign.center)],
    );
  }

  TicketDocument buildVehicle(ParkingSession s) {
    final number = '${s.ticketBase}-${s.vehicleType.ticketSuffix}';
    final label = s.vehicleType.label.toUpperCase().replaceAll('É', 'E');
    return TicketDocument(
      kind: TicketKind.vehicule,
      number: number,
      qrData: TicketQr.encode(number, s),
      lines: [
        ..._header,
        TicketLine.pair('TICKET $label', number, bold: true),
        TicketLine(formatDateTime(s.enteredAt)),
        ..._plate(s),
      ],
      footer: [TicketLine('A LAISSER SUR ${s.vehicleType.withArticle.toUpperCase().replaceAll('É', 'E')}', align: TicketAlign.center)],
    );
  }

  TicketDocument buildHelmet(ParkingSession s, int index) {
    final number = '${s.ticketBase}-H$index';
    return TicketDocument(
      kind: TicketKind.casque,
      number: number,
      qrData: TicketQr.encode(number, s),
      lines: [
        ..._header,
        TicketLine.pair('CASQUE ${_two(index)}/${_two(s.helmetCount)}', number, bold: true),
        TicketLine.pair(s.hasPlate ? s.licensePlate : s.vehicleType.label.toUpperCase(),
            formatTime(s.enteredAt)),
      ],
      footer: const [TicketLine('A FIXER SUR LE CASQUE', align: TicketAlign.center)],
    );
  }
}

/// Supprime les accents : les imprimantes thermiques bon marché n'ont souvent
/// pas la bonne page de code.
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
        _center('[QR CODE]', paper.charsPerLine),
        for (final l in doc.footer) ...renderLine(l),
      ];

  List<String> renderLine(TicketLine l) {
    final width = l.large ? paper.charsPerLine ~/ 2 : paper.charsPerLine;
    if (l.isRule) return [l.text * paper.charsPerLine];
    if (l.isPair) {
      final parts = l.text.split('\u0000');
      final gap = width - parts[0].length - parts[1].length;
      if (gap >= 1) return ['${parts[0]}${' ' * gap}${parts[1]}'];
      return [parts[0], parts[1].padLeft(width)];
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

/// Encodeur ESC/POS standard (Xprinter, Goojprt, MTP-II, Rongta, Epson… 58 et 80 mm).
class EscPosTicketEncoder {
  const EscPosTicketEncoder(this.paper, {this.qrModuleSize, this.cut = true});

  final PaperWidth paper;
  final int? qrModuleSize;

  /// Beaucoup d'imprimantes 58 mm Bluetooth n'ont pas de massicot : la commande
  /// est alors simplement ignorée.
  final bool cut;

  static const _esc = 0x1B, _gs = 0x1D;

  List<int> encode(TicketDocument doc) {
    final out = <int>[_esc, 0x40]; // initialisation
    final renderer = TicketTextRenderer(paper);
    void line(TicketLine l) {
      out.addAll([_esc, 0x61, switch (l.align) { TicketAlign.left => 0, TicketAlign.center => 1, TicketAlign.right => 2 }]);
      out.addAll([_esc, 0x45, l.bold ? 1 : 0]);
      out.addAll([_gs, 0x21, l.large ? 0x11 : 0x00]);
      // L'alignement centré est fait par l'imprimante : texte envoyé sans marge.
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
    out.addAll(qr(doc.qrData));
    for (final l in doc.footer) {
      line(l);
    }
    out.addAll([_esc, 0x61, 0, _esc, 0x64, 3]); // avance de 3 lignes
    if (cut) out.addAll([_gs, 0x56, 0x42, 0x00]); // coupe partielle
    return out;
  }

  /// QR code natif ESC/POS (GS ( k), modèle 2, correction M.
  List<int> qr(String data) {
    final bytes = ascii.encode(toPrinterAscii(data));
    final size = qrModuleSize ?? (paper == PaperWidth.mm58 ? 5 : 6);
    final len = bytes.length + 3;
    return [
      _esc, 0x61, 1, // centré
      _gs, 0x28, 0x6B, 4, 0, 0x31, 0x41, 0x32, 0x00, // modèle 2
      _gs, 0x28, 0x6B, 3, 0, 0x31, 0x43, size, // taille du module
      _gs, 0x28, 0x6B, 3, 0, 0x31, 0x45, 0x31, // correction d'erreur M
      _gs, 0x28, 0x6B, len & 0xFF, len >> 8, 0x31, 0x50, 0x30, ...bytes, // données
      _gs, 0x28, 0x6B, 3, 0, 0x31, 0x51, 0x30, // impression
      0x0A,
    ];
  }
}

/// Impression : imprimante Bluetooth (voir bluetooth_printer.dart) ou autre.
abstract class TicketPrinter {
  /// Imprime les tickets à la suite, dans l'ordre reçu.
  Future<void> printTickets(List<TicketDocument> tickets);
}

/// Adaptateur pour toute librairie qui envoie des octets bruts (USB, réseau…).
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
