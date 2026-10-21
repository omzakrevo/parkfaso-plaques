import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parkfaso_plaque/app/app_controller.dart';
import 'package:parkfaso_plaque/app/history_screen.dart' as history;
import 'package:parkfaso_plaque/core/auth.dart';
import 'package:parkfaso_plaque/core/github_sync.dart';
import 'package:parkfaso_plaque/core/licence.dart';
import 'package:parkfaso_plaque/core/park_store.dart';
import 'package:parkfaso_plaque/main.dart';
import 'package:parkfaso_plaque/plaque/plate_camera_source.dart';
import 'package:parkfaso_plaque/plaque/plate_image_preprocessor.dart';
import 'package:parkfaso_plaque/plaque/plate_models.dart';
import 'package:parkfaso_plaque/plaque/plate_ocr_service.dart';
import 'package:parkfaso_plaque/plaque/plate_parser.dart';
import 'package:parkfaso_plaque/plaque/plate_photo_store.dart';
import 'package:parkfaso_plaque/tickets/bluetooth_printer.dart';
import 'package:parkfaso_plaque/tickets/tickets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'bluetooth_printer_test.dart' show FakeBtApi;

class FakeCamera implements PlateCameraSource {
  int shots = 0;
  @override
  Future<void> initialize() async {}
  @override
  double get portraitAspectRatio => 3 / 4;
  @override
  Widget buildPreview() => const ColoredBox(color: Colors.grey);
  @override
  Future<String> takePicture() async => '/inexistant/photo_${shots++}.jpg';
  @override
  bool get hasTorch => false;
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
  FakeOcr(this.plates) : super(engine: NullEngine());
  final List<String> plates;
  int i = 0;
  @override
  Future<PlateRecognitionResult> recognize(String photoPath, {NormalizedRect crop = NormalizedRect.guide}) async {
    final p = i < plates.length ? plates[i] : '';
    i++;
    return PlateRecognitionResult(
        parse: parser.parse([if (p.isNotEmpty) OcrLine(p, top: 0, height: 80)]),
        photoPath: photoPath, elapsed: Duration.zero, passes: 1);
  }
}

class RecordingPrinter implements TicketPrinter {
  final numbers = <String>[];
  @override
  Future<void> printTickets(List<TicketDocument> tickets) async => numbers.addAll(tickets.map((t) => t.number));
}

class Harness {
  late AppController app;
  late ParkStore store;
  final printer = RecordingPrinter();
  DateTime now = DateTime(2026, 10, 21, 9, 0);
  late SimpleKeyPair kp;
  late String pub;
  final exports = <String, Uint8List>{};
  List<String> scanCodes = [];

  Future<String> licence({int parkings = 3, String exp = ''}) async {
    final bytes = utf8.encode(jsonEncode({'v': 1, 'id': 'LTEST', 'c': 'Client test', 'p': parkings,
      'i': '2026-10-01', 'e': exp}));
    final sig = await Ed25519().sign(bytes, keyPair: kp);
    String b(List<int> x) => base64Url.encode(x).replaceAll('=', '');
    return 'PKF1.${b(bytes)}.${b(sig.bytes)}';
  }

  Future<void> boot(WidgetTester tester, {List<String> plates = const []}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    history.shareExport = (name, bytes, mime) async => exports[name] = bytes;
    await tester.runAsync(() async {
      kp = await Ed25519().newKeyPair();
      pub = base64.encode((await kp.extractPublicKey()).bytes);
    });
    final db = await openParkDatabase(inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate,
        singleInstance: false);
    store = ParkStore(db);
    app = AppController(
      store: store,
      auth: AuthService(store, clock: () => now),
      licences: LicenceService(store, verifier: LicenceVerifier(publicKeyB64: pub), clock: () => now,
          client: MockClient((_) async => http.Response('{"revoquees":[]}', 200))),
      sync: SyncService(store, clock: () => now),
      printer: BluetoothThermalPrinter(api: FakeBtApi()),
      ticketPrinter: printer,
      ocr: FakeOcr(plates),
      photoStore: PlatePhotoStore(keepPhotos: false, retentionDays: 7),
      cameraFactory: FakeCamera.new,
      scannerBuilder: (onCode) => Column(children: [
        for (final c in scanCodes) TextButton(key: Key('scan:$c'), onPressed: () => onCode(c), child: Text(c)),
      ]),
      clock: () => now,
    );
    await app.load();
    await tester.pumpWidget(StartupGate(init: () async => app));
    await tester.pumpAndSettle();
  }

  Future<void> pin(WidgetTester tester, String code) async {
    for (final d in code.split('')) {
      await tester.tap(find.byKey(Key('pin-$d')).last);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  /// Assistant de premier démarrage → administrateur connecté.
  Future<void> setup(WidgetTester tester, {String parking = 'Parking Central'}) async {
    await tester.tap(find.byKey(const Key('setup-start')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('setup-parking')), parking);
    await tester.tap(find.byKey(const Key('setup-next-parking')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('setup-admin')), 'Zachari');
    await tester.tap(find.byKey(const Key('setup-next-admin')));
    await tester.pumpAndSettle();
    await pin(tester, '2580');
    await pin(tester, '2580');
    await tester.tap(find.byKey(const Key('setup-finish')));
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
    await tester.pumpAndSettle();
  }

  /// Entrée d'une moto (casque « Aucun »), photo de la plaque, confirmation.
  Future<void> motoEntry(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('vehicle-moto')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('helmet-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('photo-plate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('capture-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-plate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-no-print')));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('premier démarrage : parking + administrateur + essai → tableau de bord', (tester) async {
    final h = Harness();
    await h.boot(tester);
    expect(find.text('Bienvenue sur PARKFASO'), findsOneWidget);
    await h.setup(tester);
    expect(find.text('Parking Central'), findsOneWidget);
    expect(find.textContaining('Bonjour Zachari'), findsOneWidget);
    expect(find.textContaining('Essai gratuit'), findsOneWidget);
    for (final t in ['Accueil', 'Présents', 'Historique', 'Rapports', 'Réglages']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(t)), findsOneWidget);
    }
    expect((await h.store.users()).single.isAdmin, isTrue);
  });

  testWidgets('entrée, présents, recherche, historique, exports, sortie, rapports', (tester) async {
    final h = Harness();
    await h.boot(tester, plates: ['11 AB 2345', '03 CD 9876']);
    await h.setup(tester);

    await h.motoEntry(tester);
    h.now = h.now.add(const Duration(minutes: 30));
    await h.motoEntry(tester);
    expect(h.printer.numbers, ['PCA-000001-C', 'PCA-000002-C']);
    expect(h.app.stats.inside, 2);
    expect(h.app.stats.todayTotal, 200);

    // Présents : les 2 motos, recherche par plaque
    await h.tab(tester, 'Présents');
    expect(find.text('Au parking · 2'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('inside-search')), 'cd 98');
    await tester.pumpAndSettle();
    expect(find.text('03 CD 9876'), findsOneWidget);
    expect(find.text('11 AB 2345'), findsNothing);

    // Sortie manuelle depuis la fiche
    await tester.tap(find.text('03 CD 9876'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-exit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Sorti'), findsWidgets);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(h.app.stats.inside, 1);

    // Historique : filtre « Sortis », recherche, exports
    await h.tab(tester, 'Historique');
    expect(find.text('2 entrées'), findsOneWidget);
    await tester.tap(find.byKey(const Key('status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sortis').last);
    await tester.pumpAndSettle();
    expect(find.text('1 entrées'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('history-search')), '11ab');
    await tester.tap(find.byKey(const Key('history-search-go')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucun résultat'), findsOneWidget);

    await tester.tap(find.byKey(const Key('export-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exporter en Excel'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(h.exports.keys.single, 'PARKFASO_Parking-Central_2026-10-21.xlsx');
    final zip = ZipDecoder().decodeBytes(h.exports.values.single);
    expect(zip.findFile('xl/worksheets/sheet1.xml'), isNotNull);

    // Rapports : chiffre d'affaires du jour
    await h.tab(tester, 'Rapports');
    expect(find.text('Aujourd\'hui'), findsWidgets);
    await tester.tap(find.text('Par mois'));
    await tester.pumpAndSettle();
    expect(find.text('Octobre'), findsOneWidget);
  });

  testWidgets('scan du ticket à la sortie, par le gardien', (tester) async {
    final h = Harness();
    await h.boot(tester, plates: ['11 AB 2345']);
    await h.setup(tester);
    await h.motoEntry(tester);
    h.scanCodes = ['PKF1|PCA-000001-C|11AB2345|2026-10-21T09:00'];
    h.now = DateTime(2026, 10, 21, 11, 30);
    await tester.tap(find.byKey(const Key('open-scan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('scan:${h.scanCodes.first}')));
    await tester.pumpAndSettle();
    expect(find.text('Au parking'), findsOneWidget);
    expect(find.text('2 h 30'), findsOneWidget);
    await tester.tap(find.byKey(const Key('validate-exit')));
    await tester.pumpAndSettle();
    expect(find.text('Sortie validée'), findsOneWidget);
    final s = (await h.app.sessions!.findByTicket('PCA-000001'))!;
    expect(s.exitedBy, 'Zachari');
  });

  testWidgets('administrateur modifie les tarifs ; le gardien n\'a pas accès aux réglages', (tester) async {
    final h = Harness();
    await h.boot(tester);
    await h.setup(tester);

    await h.tab(tester, 'Réglages');
    await tester.tap(find.byKey(const Key('open-prices')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('price-moto')), '150');
    await tester.tap(find.byKey(const Key('save-prices')));
    await tester.pumpAndSettle();
    expect(h.app.parking!.prices[VehicleType.moto], 150);

    // Création d'un gardien
    await tester.tap(find.byKey(const Key('open-users')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-user')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('user-name')), 'Issa');
    await tester.enterText(find.byKey(const Key('user-pin')), '1234');
    await tester.tap(find.byKey(const Key('user-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Issa'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Déconnexion → connexion du gardien
    await tester.tap(find.byKey(const Key('settings-logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('user-Issa')));
    await tester.pumpAndSettle();
    await h.pin(tester, '0000');
    expect(find.text('Code incorrect'), findsOneWidget);
    await h.pin(tester, '1234');
    expect(find.textContaining('Bonjour Issa'), findsOneWidget);
    expect(find.text('150 FCFA'), findsOneWidget, reason: 'nouveau tarif moto');
    final nav = find.byType(NavigationBar);
    expect(find.descendant(of: nav, matching: find.text('Rapports')), findsNothing);
    await h.tab(tester, 'Plus');
    expect(find.byKey(const Key('open-prices')), findsNothing);
    expect(find.byKey(const Key('open-users')), findsNothing);
  });

  testWidgets('licence : essai limité à 1 parking, licence 3 parkings, essai terminé', (tester) async {
    final h = Harness();
    await h.boot(tester);
    await h.setup(tester);
    await h.tab(tester, 'Réglages');
    await tester.tap(find.byKey(const Key('open-parkings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-parking')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-parking-name')), 'Gare Routière');
    await tester.tap(find.byKey(const Key('new-parking-ok')));
    await tester.pumpAndSettle();
    expect(find.textContaining('limité à 1 parking'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Activation d'une licence 3 parkings
    final key = await tester.runAsync(() => h.licence(parkings: 3));
    await tester.scrollUntilVisible(find.byKey(const Key('enter-licence')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const Key('enter-licence')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('enter-licence')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('licence-field')), key!);
    await tester.tap(find.byKey(const Key('activate-licence')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(h.app.licence.status, LicenceStatus.active);
    expect(find.textContaining('Client test'), findsWidgets);

    await tester.scrollUntilVisible(find.byKey(const Key('open-parkings')), -200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('open-parkings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-parking')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-parking-name')), 'Gare Routière');
    await tester.tap(find.byKey(const Key('new-parking-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Gare Routière'), findsOneWidget);
    await tester.tap(find.text('Utiliser'));
    await tester.pumpAndSettle();
    expect(h.app.parking!.name, 'Gare Routière');
    expect(await h.app.sessions!.nextTicketBase(), 'GRA-000001');
  });

  testWidgets('essai terminé : entrées bloquées, message licence', (tester) async {
    final h = Harness();
    await h.boot(tester);
    await h.setup(tester);
    h.now = h.now.add(const Duration(days: 8));
    h.app.licence = await h.app.licences.current();
    await h.app.refreshStats();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vehicle-moto')));
    await tester.pumpAndSettle();
    expect(find.text('Licence requise'), findsOneWidget);
  });
}
