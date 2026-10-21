import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkfaso_plaque/app/home_screen.dart';
import 'package:parkfaso_plaque/app/parkfaso_theme.dart';
import 'package:parkfaso_plaque/plaque/plate_camera_source.dart';
import 'package:parkfaso_plaque/plaque/plate_database.dart';
import 'package:parkfaso_plaque/plaque/plate_image_preprocessor.dart';
import 'package:parkfaso_plaque/plaque/plate_models.dart';
import 'package:parkfaso_plaque/plaque/plate_ocr_service.dart';
import 'package:parkfaso_plaque/plaque/plate_parser.dart';
import 'package:parkfaso_plaque/plaque/plate_photo_store.dart';
import 'package:parkfaso_plaque/tickets/bluetooth_printer.dart';
import 'package:parkfaso_plaque/tickets/ticket_scan_screen.dart';
import 'package:parkfaso_plaque/tickets/tickets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bluetooth_printer_test.dart' show FakeBtApi;

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

class MemoryRepo implements SessionRepository {
  final saved = <ParkingSession>[];
  @override
  Future<String> nextTicketBase() async => 'PK-${(saved.length + 125).toString().padLeft(6, '0')}';
  @override
  Future<int> save(ParkingSession s) async {
    saved.add(s.copyWith(id: saved.length + 1));
    return saved.length;
  }

  @override
  Future<ParkingSession?> findByTicket(String base) async =>
      saved.where((s) => s.ticketBase == base).firstOrNull;
  @override
  Future<void> markExited(int id, DateTime at) async =>
      saved[id - 1] = saved[id - 1].copyWith(exitedAt: at);
}

class RecordingPrinter implements TicketPrinter {
  RecordingPrinter({this.failTimes = 0});
  int failTimes;
  final batches = <List<TicketDocument>>[];
  List<String> get numbers => [for (final b in batches) for (final t in b) t.number];
  @override
  Future<void> printTickets(List<TicketDocument> tickets) async {
    if (failTimes > 0) {
      failTimes--;
      throw const PrinterException('Imprimante éteinte');
    }
    batches.add(tickets);
  }
}

/// Scanner simulé : un bouton par code à « scanner ».
Widget Function(ValueChanged<String>) fakeScanner(List<String> codes) => (onCode) => Column(
      children: [
        for (final c in codes)
          TextButton(key: Key('scan:$c'), onPressed: () => onCode(c), child: Text(c)),
      ],
    );

void main() {
  late MemoryRepo repo;
  late RecordingPrinter printer;
  var now = DateTime(2026, 10, 21, 8, 35);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = MemoryRepo();
    printer = RecordingPrinter();
    now = DateTime(2026, 10, 21, 8, 35);
  });

  Future<void> openApp(WidgetTester tester, FakeOcr ocr,
      {ParkingSettings settings = const ParkingSettings(parkingName: 'Parking Central'),
      List<String> scanCodes = const []}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final bt = BluetoothThermalPrinter(api: FakeBtApi());
    await tester.pumpWidget(MaterialApp(
      theme: buildParkTheme(),
      home: ParkHomeScreen(
        settings: settings,
        ocr: ocr,
        repository: repo,
        printer: bt,
        ticketPrinter: printer,
        photoStore: PlatePhotoStore(keepPhotos: false, retentionDays: 7),
        cameraFactory: FakeCamera.new,
        scannerBuilder: fakeScanner(scanCodes),
        clock: () => now,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> photograph(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('photo-plate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('capture-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('accueil : choix moto, voiture, tricycle, vélo + scan', (tester) async {
    await openApp(tester, FakeOcr(const []));
    for (final t in VehicleType.values) {
      expect(find.byKey(Key('vehicle-${t.name}')), findsOneWidget);
    }
    expect(find.text('100 FCFA'), findsOneWidget); // moto
    expect(find.text('300 FCFA'), findsOneWidget); // voiture
    expect(find.byKey(const Key('open-scan')), findsOneWidget);
    expect(find.text('Aucune imprimante'), findsOneWidget);
  });

  testWidgets('moto : CASQUE → PHOTO → CONFIRMER → ticket client auto, puis tickets moto/casque au choix',
      (tester) async {
    await openApp(tester, FakeOcr([[const OcrLine('11 AB 2345', top: 0, height: 80)]]));
    await tester.tap(find.byKey(const Key('vehicle-moto')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('helmet-1')));
    await tester.pump();
    await photograph(tester);
    expect(find.text('CONFIRMER ET IMPRIMER'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-plate')));
    await tester.pumpAndSettle();

    // Phase 1 : seul le ticket client est sorti
    expect(printer.numbers, ['PK-000125-C']);
    expect(find.text('Ticket client imprimé'), findsOneWidget);
    final s = repo.saved.single;
    expect((s.vehicleType, s.licensePlate, s.plateCaptureMethod, s.helmetCount),
        (VehicleType.moto, '11 AB 2345', PlateCaptureMethod.ocr, 1));

    // Phase 2 : le gardien décide
    expect(find.byKey(const Key('opt-vehicle')), findsOneWidget);
    expect(find.byKey(const Key('opt-helmets')), findsOneWidget);
    await tester.tap(find.byKey(const Key('print-secondary')));
    await tester.pumpAndSettle();
    expect(printer.numbers, ['PK-000125-C', 'PK-000125-M', 'PK-000125-H1']);
    expect(find.byKey(const Key('vehicle-moto')), findsOneWidget, reason: 'retour à l\'accueil');
  });

  testWidgets('phase 2 : ne pas imprimer le ticket moto', (tester) async {
    await openApp(tester, FakeOcr(const []));
    await tester.tap(find.byKey(const Key('vehicle-moto')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('helmet-0')));
    await tester.tap(find.byKey(const Key('save-print')));
    await tester.pumpAndSettle();
    expect(printer.numbers, ['PK-000125-C']);
    await tester.tap(find.byKey(const Key('finish-no-print')));
    await tester.pumpAndSettle();
    expect(printer.numbers, ['PK-000125-C'], reason: 'ticket moto non tiré');
  });

  testWidgets('phase 2 : casques seulement (ticket moto décoché)', (tester) async {
    await openApp(tester, FakeOcr(const []));
    await tester.tap(find.byKey(const Key('vehicle-moto')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('helmet-2')));
    await tester.tap(find.byKey(const Key('save-print')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('opt-vehicle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('print-secondary')));
    await tester.pumpAndSettle();
    expect(printer.numbers, ['PK-000125-C', 'PK-000125-H1', 'PK-000125-H2']);
  });

  testWidgets('immatriculation facultative : enregistrement sans plaque', (tester) async {
    await openApp(tester, FakeOcr(const []));
    await tester.tap(find.byKey(const Key('vehicle-moto')));
    await tester.pumpAndSettle();
    expect(find.text('IMMATRICULATION · FACULTATIF'), findsOneWidget);
    await tester.tap(find.byKey(const Key('helmet-0')));
    await tester.tap(find.byKey(const Key('save-print')));
    await tester.pumpAndSettle();
    expect(repo.saved.single.plateCaptureMethod, PlateCaptureMethod.none);
    expect(printer.numbers, ['PK-000125-C']);
  });

  testWidgets('nombre de casques à indiquer pour une moto', (tester) async {
    await openApp(tester, FakeOcr(const []));
    await tester.tap(find.byKey(const Key('vehicle-moto')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-print')));
    await tester.pumpAndSettle();
    expect(find.text('Indiquez le nombre de casques.'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('plaque obligatoire si le parking l\'exige', (tester) async {
    await openApp(tester, FakeOcr(const []),
        settings: const ParkingSettings(parkingName: 'P', allowEmptyPlate: false));
    await tester.tap(find.byKey(const Key('vehicle-voiture')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-print')));
    await tester.pumpAndSettle();
    expect(find.text('Immatriculation obligatoire dans ce parking.'), findsOneWidget);
  });

  testWidgets('voiture : pas de casque, prix voiture, ticket -V', (tester) async {
    await openApp(tester, FakeOcr(const []));
    await tester.tap(find.byKey(const Key('vehicle-voiture')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('helmet-choice')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('total-amount'))).data, '300 FCFA');
    await tester.enterText(find.byKey(const Key('plate-field')), '11ab2345');
    await tester.tap(find.byKey(const Key('save-print')));
    await tester.pumpAndSettle();
    expect(repo.saved.single.licensePlate, '11 AB 2345');
    expect(repo.saved.single.plateCaptureMethod, PlateCaptureMethod.manual);
    expect(find.byKey(const Key('opt-helmets')), findsNothing);
    await tester.tap(find.byKey(const Key('print-secondary')));
    await tester.pumpAndSettle();
    expect(printer.numbers, ['PK-000125-C', 'PK-000125-V']);
  });

  testWidgets('vélo : ni casque ni plaque', (tester) async {
    await openApp(tester, FakeOcr(const []));
    await tester.tap(find.byKey(const Key('vehicle-velo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('helmet-choice')), findsNothing);
    expect(find.byKey(const Key('plate-field')), findsNothing);
    await tester.tap(find.byKey(const Key('save-print')));
    await tester.pumpAndSettle();
    expect(repo.saved.single.vehicleType, VehicleType.velo);
  });

  testWidgets('imprimante éteinte : session gardée, réimpression du ticket client', (tester) async {
    printer.failTimes = 1;
    await openApp(tester, FakeOcr(const []));
    await tester.tap(find.byKey(const Key('vehicle-moto')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('helmet-0')));
    await tester.tap(find.byKey(const Key('save-print')));
    await tester.pumpAndSettle();
    expect(find.text('Ticket client non imprimé'), findsOneWidget);
    expect(repo.saved, hasLength(1));
    await tester.tap(find.byKey(const Key('reprint-client')));
    await tester.pumpAndSettle();
    expect(find.text('Ticket client imprimé'), findsOneWidget);
    expect(printer.numbers, ['PK-000125-C']);
    expect(repo.saved, hasLength(1), reason: 'pas de double enregistrement');
  });

  group('Scan des tickets', () {
    Future<void> enterMoto(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('vehicle-moto')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('helmet-0')));
      await tester.enterText(find.byKey(const Key('plate-field')), '11 AB 2345');
      await tester.tap(find.byKey(const Key('save-print')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finish-no-print')));
      await tester.pumpAndSettle();
    }

    testWidgets('scan du QR client → infos → valider la sortie → ticket déjà utilisé', (tester) async {
      const qr = 'PKF1|PK-000125-C|11AB2345|2026-10-21T08:35';
      await openApp(tester, FakeOcr(const []), scanCodes: [qr]);
      await enterMoto(tester);

      now = DateTime(2026, 10, 21, 10, 50);
      await tester.tap(find.byKey(const Key('open-scan')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan:$qr')));
      await tester.pumpAndSettle();
      expect(find.text('Au parking'), findsOneWidget);
      expect(find.text('11 AB 2345'), findsOneWidget);
      expect(find.text('2 h 15'), findsOneWidget);
      expect(find.text('100 FCFA'), findsOneWidget);

      await tester.tap(find.byKey(const Key('validate-exit')));
      await tester.pumpAndSettle();
      expect(find.text('Sortie validée'), findsOneWidget);
      expect(repo.saved.single.exitedAt, DateTime(2026, 10, 21, 10, 50));

      // Le même ticket présenté une 2e fois est refusé.
      await tester.tap(find.byKey(const Key('scan-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan:$qr')));
      await tester.pumpAndSettle();
      expect(find.text('Ticket déjà utilisé'), findsOneWidget);
      expect(find.byKey(const Key('validate-exit')), findsNothing);
    });

    testWidgets('QR modifié (autre plaque) : alerte', (tester) async {
      const fake = 'PKF1|PK-000125-M|11CD9999|2026-10-21T08:35';
      await openApp(tester, FakeOcr(const []), scanCodes: [fake]);
      await enterMoto(tester);
      await tester.tap(find.byKey(const Key('open-scan')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan:$fake')));
      await tester.pumpAndSettle();
      expect(find.text('Plaque différente !'), findsOneWidget);
      expect(find.byKey(const Key('validate-exit')), findsNothing);
    });

    testWidgets('ticket casque, ticket inconnu, code étranger', (tester) async {
      const casque = 'PKF1|PK-000125-H1|11AB2345|2026-10-21T08:35';
      const inconnu = 'PKF1|PK-000999-C|11ZZ1111|2026-10-20T07:00';
      await openApp(tester, FakeOcr(const []), scanCodes: [casque, inconnu, 'https://pub.example']);
      await enterMoto(tester);
      await tester.tap(find.byKey(const Key('open-scan')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('scan:$casque')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ticket casque n° 1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('scan-next')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('scan:$inconnu')));
      await tester.pumpAndSettle();
      expect(find.text('Ticket inconnu sur ce téléphone'), findsOneWidget);
      await tester.tap(find.byKey(const Key('scan-next')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('scan:https://pub.example')));
      await tester.pumpAndSettle();
      expect(find.text('Ce n\'est pas un ticket PARKFASO'), findsOneWidget);
    });

    testWidgets('numéro de ticket saisi à la main', (tester) async {
      await openApp(tester, FakeOcr(const []));
      await enterMoto(tester);
      await tester.tap(find.byKey(const Key('open-scan')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('manual-ticket')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('manual-ticket-field')), 'pk125');
      await tester.tap(find.byKey(const Key('manual-ticket-ok')));
      await tester.pumpAndSettle();
      expect(find.text('Au parking'), findsOneWidget);
    });
  });

  test('durées affichées', () {
    expect(formatDuration(const Duration(minutes: 7)), '7 min');
    expect(formatDuration(const Duration(hours: 2, minutes: 5)), '2 h 05');
    expect(formatDuration(const Duration(hours: 27)), '1 j 3 h');
  });
}
