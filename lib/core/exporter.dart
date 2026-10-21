// PARKFASO — Export de l'historique en PDF et en Excel (.xlsx).
//
// Le fichier Excel est écrit directement (archive ZIP + XML « Office Open »),
// sans dépendance supplémentaire : il s'ouvre dans Excel, WPS, LibreOffice et
// Google Sheets.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../plaque/plate_models.dart';
import '../tickets/tickets.dart';
import 'models.dart';

String _money(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '$b FCFA';
}

String formatMoney(int v) => _money(v);

String _period(HistoryFilter f) {
  final a = formatDate(f.from), b = formatDate(f.to);
  return a == b ? a : '$a au $b';
}

List<String> _row(ParkingSession s, DateTime now) => [
      s.ticketBase,
      s.vehicleType.label,
      s.hasPlate ? s.licensePlate : '-',
      formatDateTime(s.enteredAt),
      s.exitedAt == null ? 'Au parking' : formatDateTime(s.exitedAt!),
      _duration(s.stayAt(now)),
      '${s.helmetCount}',
      '${s.total}',
      s.enteredBy ?? '',
    ];

String _duration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  return h == 0 ? '$m min' : '$h h ${m.toString().padLeft(2, '0')}';
}

const _headers = ['Ticket', 'Véhicule', 'Plaque', 'Entrée', 'Sortie', 'Durée', 'Casques', 'Montant', 'Gardien'];

/// Rapport PDF A4 (paysage) : en-tête, totaux, tableau.
Future<Uint8List> buildHistoryPdf({
  required String parkingName,
  required HistoryFilter filter,
  required List<ParkingSession> sessions,
  required DateTime now,
}) async {
  final doc = pw.Document(title: 'PARKFASO - Historique', author: 'PARKFASO');
  const navy = PdfColor.fromInt(0xFF0E3A5B);
  const amber = PdfColor.fromInt(0xFFF2A900);
  final total = sessions.fold<int>(0, (a, s) => a + s.total);
  final inside = sessions.where((s) => s.isInside).length;
  final byType = <VehicleType, int>{};
  for (final s in sessions) {
    byType[s.vehicleType] = (byType[s.vehicleType] ?? 0) + 1;
  }

  pw.Widget kpi(String label, String value) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(10),
          margin: const pw.EdgeInsets.only(right: 8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 3),
            pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: navy)),
          ]),
        ),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(28),
    header: (ctx) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      margin: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: amber, width: 2))),
      child: pw.Row(children: [
        pw.Text('PARKFASO', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: navy)),
        pw.SizedBox(width: 10),
        pw.Text(parkingName, style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey800)),
        pw.Spacer(),
        pw.Text('Historique du ${_period(filter)}', style: const pw.TextStyle(fontSize: 11)),
      ]),
    ),
    footer: (ctx) => pw.Row(children: [
      pw.Text('Édité le ${formatDateTime(now)}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      pw.Spacer(),
      pw.Text('Page ${ctx.pageNumber}/${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ]),
    build: (ctx) => [
      pw.Row(children: [
        kpi('Entrées', '${sessions.length}'),
        kpi('Chiffre d\'affaires', _money(total)),
        kpi('Encore au parking', '$inside'),
        kpi('Par type', byType.entries.map((e) => '${e.key.label} ${e.value}').join(' · ').padRight(1)),
      ]),
      pw.SizedBox(height: 14),
      if (sessions.isEmpty)
        pw.Text('Aucune entrée sur cette période.')
      else
        pw.TableHelper.fromTextArray(
          headers: _headers,
          data: [for (final s in sessions) _row(s, now)],
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: navy),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          cellAlignments: {6: pw.Alignment.center, 7: pw.Alignment.centerRight},
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        ),
    ],
  ));
  return doc.save();
}

/// Classeur Excel : une feuille « Historique » (avec total) et une « Résumé ».
Uint8List buildHistoryXlsx({
  required String parkingName,
  required HistoryFilter filter,
  required List<ParkingSession> sessions,
  required DateTime now,
}) {
  String esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);
  String col(int i) => String.fromCharCode(65 + i);
  String cellStr(String ref, String v, {int style = 0}) =>
      '<c r="$ref" t="inlineStr"${style > 0 ? ' s="$style"' : ''}><is><t xml:space="preserve">${esc(v)}</t></is></c>';
  String cellNum(String ref, num v, {int style = 0}) =>
      '<c r="$ref"${style > 0 ? ' s="$style"' : ''}><v>$v</v></c>';

  // Feuille 1 : historique
  final rows = StringBuffer();
  rows.write('<row r="1">${cellStr('A1', 'PARKFASO - $parkingName - ${_period(filter)}', style: 1)}</row>');
  rows.write('<row r="3">');
  for (var i = 0; i < _headers.length; i++) {
    rows.write(cellStr('${col(i)}3', _headers[i], style: 2));
  }
  rows.write('</row>');
  var r = 4;
  for (final s in sessions) {
    final v = _row(s, now);
    rows.write('<row r="$r">');
    for (var i = 0; i < v.length; i++) {
      final ref = '${col(i)}$r';
      rows.write(i == 6 || i == 7 ? cellNum(ref, int.parse(v[i]), style: i == 7 ? 3 : 0) : cellStr(ref, v[i]));
    }
    rows.write('</row>');
    r++;
  }
  if (sessions.isNotEmpty) {
    rows.write('<row r="$r">${cellStr('A$r', 'TOTAL', style: 2)}'
        '<c r="H$r" s="4"><f>SUM(H4:H${r - 1})</f></c></row>');
  }
  final sheet1 = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetViews><sheetView workbookViewId="0"><pane ySplit="3" topLeftCell="A4" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
      '<cols><col min="1" max="1" width="16" customWidth="1"/><col min="2" max="2" width="11" customWidth="1"/>'
      '<col min="3" max="3" width="14" customWidth="1"/><col min="4" max="5" width="18" customWidth="1"/>'
      '<col min="6" max="7" width="10" customWidth="1"/><col min="8" max="8" width="12" customWidth="1"/>'
      '<col min="9" max="9" width="14" customWidth="1"/></cols>'
      '<sheetData>$rows</sheetData>'
      '${sessions.isEmpty ? '' : '<autoFilter ref="A3:I${3 + sessions.length}"/>'}'
      '</worksheet>';

  // Feuille 2 : résumé par type
  final byType = <VehicleType, (int, int)>{};
  for (final s in sessions) {
    final (n, t) = byType[s.vehicleType] ?? (0, 0);
    byType[s.vehicleType] = (n + 1, t + s.total);
  }
  final sum = StringBuffer()
    ..write('<row r="1">${cellStr('A1', 'Type', style: 2)}${cellStr('B1', 'Entrées', style: 2)}'
        '${cellStr('C1', 'Montant (FCFA)', style: 2)}</row>');
  var sr = 2;
  for (final e in byType.entries) {
    sum.write('<row r="$sr">${cellStr('A$sr', e.key.label)}${cellNum('B$sr', e.value.$1)}'
        '${cellNum('C$sr', e.value.$2, style: 3)}</row>');
    sr++;
  }
  sum.write('<row r="$sr">${cellStr('A$sr', 'TOTAL', style: 2)}${cellNum('B$sr', sessions.length, style: 2)}'
      '${cellNum('C$sr', sessions.fold<int>(0, (a, s) => a + s.total), style: 4)}</row>');
  final sheet2 = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<cols><col min="1" max="3" width="16" customWidth="1"/></cols>'
      '<sheetData>$sum</sheetData></worksheet>';

  const styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0"/></numFmts>'
      '<fonts count="3"><font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="14"/><color rgb="FF0E3A5B"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>'
      '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FF0E3A5B"/></patternFill></fill></fills>'
      '<borders count="1"><border/></borders>'
      '<cellStyleXfs count="1"><xf/></cellStyleXfs>'
      '<cellXfs count="5"><xf/>'
      '<xf fontId="1" applyFont="1"/>'
      '<xf fontId="2" fillId="2" applyFont="1" applyFill="1"/>'
      '<xf numFmtId="164" applyNumberFormat="1"/>'
      '<xf numFmtId="164" fontId="2" fillId="2" applyNumberFormat="1" applyFont="1" applyFill="1"/>'
      '</cellXfs></styleSheet>';

  final files = <String, String>{
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Historique" sheetId="1" r:id="rId1"/><sheet name="Résumé" sheetId="2" r:id="rId2"/></sheets>'
        '${sessions.isEmpty ? '' : '<definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">Historique!\$A\$3:\$I\$${3 + sessions.length}</definedName></definedNames>'}'
        '</workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
    'xl/worksheets/sheet1.xml': sheet1,
    'xl/worksheets/sheet2.xml': sheet2,
    'xl/styles.xml': styles,
  };
  final archive = Archive();
  for (final e in files.entries) {
    final bytes = utf8.encode(e.value);
    archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Nom de fichier : PARKFASO_Parking-Central_2026-10-21.pdf
String exportFileName(String parkingName, HistoryFilter f, String ext) {
  String d(DateTime x) => x.toIso8601String().substring(0, 10);
  final slug = parkingName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
  final period = d(f.from) == d(f.to) ? d(f.from) : '${d(f.from)}_${d(f.to)}';
  return 'PARKFASO_${slug}_$period.$ext';
}
