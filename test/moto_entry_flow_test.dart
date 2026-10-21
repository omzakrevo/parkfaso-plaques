import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkfaso_plaque/plaque/moto_entry_screen.dart';
import 'package:parkfaso_plaque/plaque/plate_camera_source.dart';
import 'package:parkfaso_plaque/plaque/plate_database.dart';
import 'package:parkfaso_plaque/plaque/plate_image_preprocessor.dart';
import 'package:parkfaso_plaque/plaque/plate_models.dart';
import 'package:parkfaso_plaque/plaque/plate_ocr_service.dart';
import 'package:parkfaso_plaque/plaque/plate_parser.dart';
import 'package:parkfaso_plaque/plaque/plate_photo_store.dart';
import 'package:parkfaso_plaque/tickets/moto_tickets.dart';

class FakeCamera implements PlateCameraSource {
  int shots = 0;
  @override
  Future<void> initialize() async {}
  @override
  double get portraitAspectRatio => 3 / 4;
  @override
  Widget buildPreview() => const ColoredBox(color: Colors.grey, key: Key('fake-preview'));
  @override
  Future<String> takePicture() async => '/inexistant/photo_${shots++}.jpg';
  @override
  bool get hasTorch => true;
  @override
  Future<void> setTorch(bool on) async {}
  @override
  Future<void> dispose() async {}
}

class NullEngine implements TextRecognitionEngine {
  @override
  Future<List<OcrLine>> recognize(String imagePath) async => const [];
  @override
  Future<void> close() async {}
}

/// OCR simulé : chaque photo renvoie le résultat de lignes prévu.
class FakeOcr extends PlateOcrService {
  FakeOcr(this.script) : super(engine: NullEngine());
  final List<List<OcrLine>> script;
  int i = 0;

  @override
  Future<PlateRecognitionResult> recognize(String photoPath,
      {NormalizedRect crop = NormalizedRect.guide}) async {
    final lines = i < script.length ? script[i] : const <OcrLine>[];
    i++;
    return PlateRecognitionResult(
        parse: parser.parse(lines), photoPath: photoPath, elapsed: Duration.zero, passes: 1);
  }
}

class MemoryRepo implements MotoSessionRepository {
  final saved = <MotoParkingSession>[];
  @override
  Future<String> nextTicketBase() async => 'PK-${(saved.length + 125).toString().padLeft(6, '0')}';
  @override
  Future<int> save(MotoParkingSession s) async {
    saved.add(s);
    return saved.length;
  }
}

class RecordingPrinter implements TicketPrinter {
  RecordingPrinter({this.failTimes = 0});
  int failTimes;
  final printed = <List<TicketDocument>>[];
  @override
  Future<void> printTickets(List<TicketDocument> tickets) async {
    if (failTimes > 0) {
      failTimes--;
      throw const SocketException('imprimante hors ligne');
    }
    printed.add(tickets);
  }
}

void main() {
  late MemoryRepo repo;
  late RecordingPrinter printer;
  late Directory tmp;

  setUp(() {
    repo = MemoryRepo();
    printer = RecordingPrinter();
    tmp = Directory.systemTemp.createTempSync('pk_flow_');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> openMoto(WidgetTester tester, FakeOcr ocr,
      {MotoEntrySettings? settings}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              key: const Key('btn-moto'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MotoEntryScreen(
                  settings: settings ??
                      const MotoEntrySettings(parkingName: 'Parking Central', motoPrice: 100),
                  ocr: ocr,
                  repository: repo,
                  printer: printer,
                  photoStore: PlatePhotoStore(keepPhotos: false, retentionDays: 7, baseDir: () async => tmp),
                  cameraFactory: FakeCamera.new,
                  clock: () => DateTime(2026, 10, 21, 8, 35),
                ),
              )),
              child: const Text('MOTO'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('btn-moto')));
    await tester.pumpAndSettle();
  }

  Future<void> photograph(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('photo-plate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fake-preview')), findsOneWidget);
    await tester.tap(find.byKey(const Key('capture-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('parcours rapide : MOTO → CASQUE OUI → PHOTO → CONFIRMER → 3 tickets', (tester) async {
    await openMoto(tester, FakeOcr([
      [const OcrLine('BURKINA FASO', top: 0, height: 20), const OcrLine('11 AB 2345', top: 30, height: 80)],
    ]));
    // Tous les éléments demandés sont affichés immédiatement
    expect(find.text('Casque déposé ?'), findsOneWidget);
    expect(find.text('PHOTOGRAPHIER LA PLAQUE'), findsOneWidget);
    expect(find.text('Numéro d\'immatriculation'), findsOneWidget);
    expect(find.text('ENREGISTRER ET IMPRIMER'), findsOneWidget);
    expect(find.text('Montant du stationnement'), findsOneWidget);

    await tester.tap(find.byKey(const Key('helmet-yes')));
    await tester.pump();
    expect(find.byKey(const Key('helmet-count')), findsOneWidget);

    await photograph(tester);
    expect(find.text('Numéro détecté'), findsOneWidget);
    expect(find.text('11 AB 2345'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-plate')));
    await tester.pumpAndSettle();

    expect(repo.saved, hasLength(1));
    final s = repo.saved.single;
    expect(s.licensePlate, '11 AB 2345');
    expect(s.plateCaptureMethod, PlateCaptureMethod.ocr);
    expect(s.plateVerified, isTrue);
    expect(s.helmetCount, 1);
    expect(s.plateOcrRawText, isNull, reason: 'texte brut non conservé');
    expect(s.platePhotoPath, isNull, reason: 'photo non conservée par défaut');

    expect(printer.printed.single.map((t) => t.number), ['PK-000125-C', 'PK-000125-M', 'PK-000125-H1']);
    final r = TicketTextRenderer(PaperWidth.mm58);
    for (final t in printer.printed.single) {
      expect(r.render(t).join('\n'), contains('11 AB 2345'));
    }
    // Retour à l'écran principal
    expect(find.byKey(const Key('btn-moto')), findsOneWidget);
  });

  testWidgets('plaque illisible : rien n\'est pré-rempli, saisie manuelle possible', (tester) async {
    await openMoto(tester, FakeOcr([const []]));
    await tester.tap(find.byKey(const Key('helmet-no')));
    await photograph(tester);

    expect(find.text('Aucune plaque reconnue.'), findsOneWidget);
    expect(find.byKey(const Key('detected-plate')), findsNothing);
    expect(find.byKey(const Key('manual-crop')), findsOneWidget);

    await tester.tap(find.byKey(const Key('correct-plate')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('plate-edit-field')), '11ab2345');
    await tester.tap(find.byKey(const Key('plate-edit-ok')));
    await tester.pumpAndSettle();

    // De retour sur le formulaire, sans impression automatique
    expect(printer.printed, isEmpty);
    expect(tester.widget<TextField>(find.byKey(const Key('plate-field'))).controller!.text, '11 AB 2345');
    expect(find.text('Saisi à la main'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save-print')));
    await tester.pumpAndSettle();
    expect(repo.saved.single.plateCaptureMethod, PlateCaptureMethod.manual);
    expect(printer.printed.single, hasLength(2)); // client + moto, pas de casque
  });

  testWidgets('plaque partiellement effacée : indice affiché, aucun numéro inventé', (tester) async {
    await openMoto(tester, FakeOcr([[const OcrLine('11 AB 23')]]));
    await tester.tap(find.byKey(const Key('helmet-no')));
    await photograph(tester);
    expect(find.textContaining('Plaque incomplète'), findsOneWidget);
    expect(find.textContaining('11 AB 23'), findsOneWidget);
    expect(find.byKey(const Key('confirm-plate')), findsNothing);
  });

  testWidgets('reprendre la photo : nouvelle analyse', (tester) async {
    await openMoto(tester, FakeOcr([const [], [const OcrLine('09 K 1234')]]));
    await tester.tap(find.byKey(const Key('helmet-no')));
    await photograph(tester);
    expect(find.text('Aucune plaque reconnue.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('retake-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('capture-button')));
    await tester.pumpAndSettle();
    expect(find.text('09 K 1234'), findsOneWidget);
  });

  testWidgets('deux plaques dans l\'image : le gardien choisit', (tester) async {
    await openMoto(tester, FakeOcr([
      [const OcrLine('11 AB 2345', top: 0, height: 60), const OcrLine('03 CD 9876', top: 300, height: 60)],
    ]));
    await tester.tap(find.byKey(const Key('helmet-no')));
    await photograph(tester);
    expect(find.text('Plusieurs numéros lus : touchez le bon'), findsOneWidget);
    expect(find.byKey(const Key('confirm-plate')), findsNothing);
    await tester.tap(find.text('03 CD 9876'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-plate')));
    await tester.pumpAndSettle();
    expect(repo.saved.single.licensePlate, '03 CD 9876');
  });

  testWidgets('correction après OCR : méthode MANUEL et relecture avant impression', (tester) async {
    await openMoto(tester, FakeOcr([[const OcrLine('11 AB 2346')]]));
    await tester.tap(find.byKey(const Key('helmet-no')));
    await photograph(tester);
    await tester.tap(find.byKey(const Key('correct-plate')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('plate-edit-field')), '11 AB 2345');
    await tester.tap(find.byKey(const Key('plate-edit-ok')));
    await tester.pumpAndSettle();
    expect(printer.printed, isEmpty);
    await tester.tap(find.byKey(const Key('save-print')));
    await tester.pumpAndSettle();
    expect(repo.saved.single.licensePlate, '11 AB 2345');
    expect(repo.saved.single.plateCaptureMethod, PlateCaptureMethod.manual);
  });

  testWidgets('numéro obligatoire si le parking ne permet pas le champ vide', (tester) async {
    await openMoto(tester, FakeOcr(const []));
    await tester.tap(find.byKey(const Key('helmet-no')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-print')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Numéro obligatoire'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('champ vide autorisé : ticket « NON RENSEIGNEE »', (tester) async {
    await openMoto(tester, FakeOcr(const []),
        settings: const MotoEntrySettings(parkingName: 'P', motoPrice: 100, allowEmptyPlate: true));
    await tester.tap(find.byKey(const Key('helmet-no')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-print')));
    await tester.pumpAndSettle();
    expect(repo.saved.single.plateCaptureMethod, PlateCaptureMethod.none);
    final text = TicketTextRenderer(PaperWidth.mm58).render(printer.printed.single.first).join('\n');
    expect(text, contains('NON RENSEIGNEE'));
  });

  testWidgets('montant mis à jour selon les casques', (tester) async {
    await openMoto(tester, FakeOcr(const []),
        settings: const MotoEntrySettings(parkingName: 'P', motoPrice: 100, helmetPrice: 50));
    await tester.tap(find.byKey(const Key('helmet-yes')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('helmet-plus')));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('total-amount'))).data, '200 FCFA');
  });

  testWidgets('imprimante en panne : session conservée, réimpression possible', (tester) async {
    printer.failTimes = 1;
    await openMoto(tester, FakeOcr([[const OcrLine('11 AB 2345')]]));
    await tester.tap(find.byKey(const Key('helmet-no')));
    await photograph(tester);
    await tester.tap(find.byKey(const Key('confirm-plate')));
    await tester.pumpAndSettle();
    expect(find.text('Impression échouée'), findsOneWidget);
    expect(repo.saved, hasLength(1));
    await tester.tap(find.text('RÉIMPRIMER'));
    await tester.pumpAndSettle();
    expect(printer.printed, hasLength(1));
    expect(repo.saved, hasLength(1), reason: 'pas de double enregistrement');
  });
}
