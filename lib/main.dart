// Application de démonstration du module « immatriculation » de PARKFASO.
// Permet d'essayer la caméra + OCR sur un téléphone Android sans le reste de
// PARKFASO : les tickets s'affichent à l'écran au lieu d'être imprimés.

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'plaque/moto_entry_screen.dart';
import 'plaque/plate_database.dart';
import 'plaque/plate_models.dart';
import 'plaque/plate_ocr_service.dart';
import 'plaque/plate_photo_store.dart';
import 'tickets/moto_tickets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openDatabase(
    p.join(await getDatabasesPath(), 'parkfaso_demo.db'),
    version: 1,
    onCreate: (db, _) => db.execute('''
      CREATE TABLE parking_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticket_number TEXT NOT NULL,
        vehicle_type TEXT NOT NULL,
        entered_at TEXT NOT NULL,
        helmet_count INTEGER NOT NULL DEFAULT 0,
        amount INTEGER NOT NULL DEFAULT 0
      )'''),
  );
  await const PlateColumnsMigration().apply(db);
  runApp(DemoApp(db: db));
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key, required this.db});

  final Database db;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PARKFASO — Plaques',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF0D47A1), useMaterial3: true),
      home: DemoHome(db: db),
    );
  }
}

class DemoHome extends StatefulWidget {
  const DemoHome({super.key, required this.db});

  final Database db;

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  final _ocr = PlateOcrService();
  PaperWidth _paper = PaperWidth.mm58;

  MotoEntrySettings get _settings => MotoEntrySettings(
        parkingName: 'Parking Central',
        motoPrice: 100,
        helmetPrice: 0,
        paperWidth: _paper,
      );

  @override
  void dispose() {
    _ocr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PARKFASO')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SegmentedButton<PaperWidth>(
            segments: const [
              ButtonSegment(value: PaperWidth.mm58, label: Text('58 mm')),
              ButtonSegment(value: PaperWidth.mm80, label: Text('80 mm')),
            ],
            selected: {_paper},
            onSelectionChanged: (v) => setState(() => _paper = v.first),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 96,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MotoEntryScreen(
                  settings: _settings,
                  ocr: _ocr,
                  repository: SqfliteMotoSessionRepository(widget.db),
                  printer: PreviewTicketPrinter(context, _paper),
                  photoStore: PlatePhotoStore(keepPhotos: false, retentionDays: 7),
                ),
              )),
              icon: const Icon(Icons.two_wheeler, size: 40),
              label: const Text('MOTO', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Affiche les tickets à l'écran (démonstration sans imprimante).
class PreviewTicketPrinter implements TicketPrinter {
  PreviewTicketPrinter(this.context, this.paper);

  final BuildContext context;
  final PaperWidth paper;

  @override
  Future<void> printTickets(List<TicketDocument> tickets) async {
    final r = TicketTextRenderer(paper);
    final text = tickets.map((t) => r.render(t).join('\n')).join('\n\n✂ - - - - - - - - - - - -\n\n');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${tickets.length} tickets'),
        content: SingleChildScrollView(
          child: Text(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }
}
