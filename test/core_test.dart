import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parkfaso_plaque/core/auth.dart';
import 'package:parkfaso_plaque/core/exporter.dart';
import 'package:parkfaso_plaque/core/github_sync.dart';
import 'package:parkfaso_plaque/core/licence.dart';
import 'package:parkfaso_plaque/core/models.dart';
import 'package:parkfaso_plaque/core/park_store.dart';
import 'package:parkfaso_plaque/plaque/plate_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<ParkStore> memStore() async {
  sqfliteFfiInit();
  final db = await openParkDatabase(inMemoryDatabasePath, factory: databaseFactoryFfi, singleInstance: false);
  return ParkStore(db);
}

ParkingSession entry(String ticket, DateTime at,
        {VehicleType t = VehicleType.moto, String plate = '', int amount = 100, DateTime? out}) =>
    ParkingSession(
      vehicleType: t,
      ticketBase: ticket,
      enteredAt: at,
      helmetCount: 0,
      vehiclePrice: amount,
      helmetPrice: 0,
      licensePlate: plate,
      plateCaptureMethod: plate.isEmpty ? PlateCaptureMethod.none : PlateCaptureMethod.ocr,
      plateVerified: plate.isNotEmpty,
      exitedAt: out,
    );

/// Licences de test signées avec une clé de test (pas la vraie clé OMZAKREVO).
class TestSigner {
  late SimpleKeyPair kp;
  late String publicB64;
  Future<void> init() async {
    kp = await Ed25519().newKeyPair();
    publicB64 = base64.encode((await kp.extractPublicKey()).bytes);
  }

  Future<String> sign(Map<String, Object?> payload) async {
    final bytes = utf8.encode(jsonEncode(payload));
    final sig = await Ed25519().sign(bytes, keyPair: kp);
    String b(List<int> x) => base64Url.encode(x).replaceAll('=', '');
    return 'PKF1.${b(bytes)}.${b(sig.bytes)}';
  }
}

void main() {
  final now = DateTime(2026, 10, 21, 14, 0);

  group('Parkings et comptes', () {
    test('code de ticket déduit du nom', () {
      expect(Parking.codeFromName('Parking Central'), 'PC');
      expect(Parking.codeFromName('Marché de Rood Woko'), 'MR');
      expect(Parking.codeFromName('Gare'), 'GA');
      expect(Parking.codeFromName('123'), 'PK');
    });

    test('plusieurs parkings, tarifs propres à chacun', () async {
      final store = await memStore();
      final a = await store.createParking('Parking Central');
      final b = await store.createParking('Gare Routière', prices: {VehicleType.moto: 150});
      await store.saveParking(a.copyWith(prices: {...a.prices, VehicleType.moto: 125}));
      final all = await store.parkings();
      expect(all.map((p) => p.name), ['Parking Central', 'Gare Routière']);
      expect(all.first.prices[VehicleType.moto], 125);
      expect((await store.parking(b.id))!.toSettings().priceOf(VehicleType.moto), 150);
    });

    test('PIN : jamais stocké en clair, connexion, blocage après 5 erreurs', () async {
      final store = await memStore();
      var t = now;
      final auth = AuthService(store, clock: () => t);
      final admin = await auth.createUser('Zachari', '2580', UserRole.admin);
      final g = await auth.createUser('Issa', '1234', UserRole.gardien);
      final raw = await store.db.query('users');
      expect(raw.any((r) => r['pin_hash'] == '2580' || r['pin_hash'] == '1234'), isFalse);
      expect(await store.hasAdmin(), isTrue);
      expect(await auth.login(g, '0000'), isFalse);
      expect(await auth.login(g, '1234'), isTrue);
      expect(auth.isAdmin, isFalse);
      expect(await auth.checkAdminPin('2580'), isTrue);
      expect(await auth.checkAdminPin('1234'), isFalse);
      auth.logout();
      for (var i = 0; i < 5; i++) {
        await auth.login(admin, '9999');
      }
      expect(auth.lockRemaining, isNotNull);
      expect(await auth.login(admin, '2580'), isFalse, reason: 'bloqué 30 s');
      t = t.add(const Duration(seconds: 31));
      expect(await auth.login(admin, '2580'), isTrue);
      expect(() => auth.createUser('X', '12', UserRole.gardien), throwsArgumentError);
    });
  });

  group('Historique, recherche, présents, rapports', () {
    late ParkStore store;
    late ParkSessionStore s;
    setUp(() async {
      store = await memStore();
      final p = await store.createParking('Parking Central');
      final other = await store.createParking('Gare');
      s = ParkSessionStore(store.db, parking: p, deviceId: 'dev1', currentUser: 'Issa');
      await s.save(entry('PCA-000001', DateTime(2026, 10, 20, 9), plate: '11 AB 2345', out: DateTime(2026, 10, 20, 12)));
      await s.save(entry('PCA-000002', DateTime(2026, 10, 21, 8), plate: '11 CD 7788'));
      await s.save(entry('PCA-000003', DateTime(2026, 10, 21, 10), t: VehicleType.voiture, amount: 300));
      await s.save(entry('PCA-000004', DateTime(2026, 9, 3, 10), amount: 100, out: DateTime(2026, 9, 3, 11)));
      // Un autre parking ne doit jamais apparaître ici.
      await ParkSessionStore(store.db, parking: other).save(entry('GAA-000001', DateTime(2026, 10, 21, 9)));
    });

    test('numéros de ticket propres au parking et au téléphone', () async {
      expect(await s.nextTicketBase(), 'PCA-000005');
    });

    test('filtre par jour, type et statut', () async {
      final today = HistoryFilter.today(now);
      expect((await s.history(today)).map((x) => x.ticketBase), ['PCA-000003', 'PCA-000002']);
      expect((await s.history(today.copyWith(vehicleType: VehicleType.voiture))).single.ticketBase, 'PCA-000003');
      final week = HistoryFilter(from: DateTime(2026, 10, 15), to: HistoryFilter.dayEnd(now));
      expect((await s.history(week.copyWith(status: StatusFilter.exited))).single.ticketBase, 'PCA-000001');
      expect((await s.history(week.copyWith(status: StatusFilter.inside))).length, 2);
    });

    test('recherche d\'une moto par plaque (avec ou sans espaces) ou ticket', () async {
      expect((await s.search('11ab2345')).single.ticketBase, 'PCA-000001');
      expect((await s.search('CD 77')).single.ticketBase, 'PCA-000002');
      expect((await s.search('000004')).single.ticketBase, 'PCA-000004');
      expect(await s.search('ZZ'), isEmpty);
    });

    test('véhicules encore au parking, du plus ancien au plus récent', () async {
      expect((await s.inside()).map((x) => x.ticketBase), ['PCA-000002', 'PCA-000003']);
      expect((await s.inside(type: VehicleType.voiture)).single.ticketBase, 'PCA-000003');
    });

    test('sortie validée par le gardien connecté', () async {
      final x = (await s.findByTicket('PCA-000002'))!;
      s.currentUser = 'Awa';
      await s.markExited(x.id!, now);
      final y = (await s.findByTicket('PCA-000002'))!;
      expect(y.exitedBy, 'Awa');
      expect(y.enteredBy, 'Issa');
      expect((await s.inside()).length, 1);
    });

    test('chiffre d\'affaires du jour, du mois, par jour et par mois', () async {
      final st = await s.stats(now);
      expect((st.inside, st.todayCount, st.todayTotal, st.monthTotal), (2, 2, 400, 500));
      final days = await s.revenueByDay(DateTime(2026, 10, 19), DateTime(2026, 10, 21));
      expect(days.map((d) => d.total), [0, 100, 400]);
      final months = await s.revenueByMonth(2026);
      expect(months[8].total, 100); // septembre
      expect(months[9].total, 500); // octobre
      final byType = await s.byVehicle(DateTime(2026, 10, 1), HistoryFilter.dayEnd(now));
      expect(byType[VehicleType.voiture]!.total, 300);
      expect(byType[VehicleType.moto]!.count, 2);
    });

    test('export PDF et Excel', () async {
      final list = await s.history(HistoryFilter(from: DateTime(2026, 10, 1), to: HistoryFilter.dayEnd(now)));
      final f = HistoryFilter(from: DateTime(2026, 10, 1), to: now);
      final pdf = await buildHistoryPdf(parkingName: 'Parking Central', filter: f, sessions: list, now: now);
      expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
      final xlsx = buildHistoryXlsx(parkingName: 'Parking Central', filter: f, sessions: list, now: now);
      final zip = ZipDecoder().decodeBytes(xlsx);
      final sheet = utf8.decode(zip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
      expect(sheet, contains('11 CD 7788'));
      expect(sheet, contains('SUM(H4:H6)'));
      expect(zip.findFile('xl/worksheets/sheet2.xml'), isNotNull);
      expect(exportFileName('Parking Central', f, 'xlsx'), 'PARKFASO_Parking-Central_2026-10-01_2026-10-21.xlsx');
      expect(formatMoney(1250000), '1 250 000 FCFA');
    });
  });

  group('Licences', () {
    late TestSigner signer;
    setUpAll(() async {
      signer = TestSigner();
      await signer.init();
    });

    Future<LicenceService> service(ParkStore store, {List<String> revoked = const [], DateTime? at}) async =>
        LicenceService(store,
            verifier: LicenceVerifier(publicKeyB64: signer.publicB64),
            clock: () => at ?? now,
            client: MockClient((_) async => http.Response(jsonEncode({'revoquees': revoked}), 200)));

    test('essai de 7 jours puis blocage', () async {
      final store = await memStore();
      expect((await (await service(store)).current()).status, LicenceStatus.trial);
      final later = await service(store, at: now.add(const Duration(days: 8)));
      final st = await later.current();
      expect(st.status, LicenceStatus.trialOver);
      expect(st.canOperate, isFalse);
    });

    test('licence authentique : activée, nombre de parkings respecté', () async {
      final store = await memStore();
      final key = await signer.sign({'v': 1, 'id': 'L0001', 'c': 'Parking Ouaga', 'p': 3, 'i': '2026-10-21', 'e': '2027-10-21'});
      final st = await (await service(store)).activate(key);
      expect(st.status, LicenceStatus.active);
      expect(st.maxParkings, 3);
      expect(st.describe(now), contains('21/10/2027'));
    });

    test('licence modifiée ou fausse : refusée', () async {
      final store = await memStore();
      final key = await signer.sign({'v': 1, 'id': 'L0002', 'c': 'X', 'p': 1, 'i': '2026-10-21', 'e': ''});
      final parts = key.split('.');
      final forged = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map;
      forged['p'] = 99;
      final tampered = 'PKF1.${base64Url.encode(utf8.encode(jsonEncode(forged)))}.${parts[2]}';
      final svc = await service(store);
      await expectLater(svc.activate(tampered), throwsA(isA<LicenceException>()));
      await expectLater(svc.activate('n importe quoi'), throwsA(isA<LicenceException>()));
      // La vraie clé de production ne valide pas une licence de test.
      await expectLater(LicenceVerifier().verify(key), throwsA(isA<LicenceException>()));
    });

    test('licence expirée et licence révoquée sur GitHub', () async {
      final store = await memStore();
      final key = await signer.sign({'v': 1, 'id': 'L0003', 'c': 'X', 'p': 1, 'i': '2026-01-01', 'e': '2026-11-30'});
      await (await service(store)).activate(key);
      final dec = await (await service(store, at: DateTime(2026, 12, 1))).current();
      expect(dec.status, LicenceStatus.expired);

      final svc = await service(store, revoked: ['L0003']);
      expect(await svc.refreshRevocations(force: true), isTrue);
      expect((await svc.current()).status, LicenceStatus.revoked);
    });

    test('hors ligne : la dernière liste de révocation est conservée', () async {
      final store = await memStore();
      final offline = LicenceService(store,
          verifier: LicenceVerifier(publicKeyB64: signer.publicB64),
          clock: () => now,
          client: MockClient((_) async => throw Exception('pas de réseau')));
      expect(await offline.refreshRevocations(force: true), isFalse);
      expect((await offline.current()).status, LicenceStatus.trial);
    });
  });

  group('Synchronisation GitHub', () {
    test('publication des fichiers puis lecture à distance', () async {
      final files = <String, String>{}; // chemin → JSON
      var puts = 0;
      final client = MockClient((req) async {
        final path = req.url.path.split('/contents/').length > 1 ? req.url.path.split('/contents/')[1] : '';
        if (req.method == 'GET' && path.isEmpty) {
          return http.Response(jsonEncode({'permissions': {'push': true}}), 200);
        }
        if (req.method == 'PUT') {
          puts++;
          final body = jsonDecode(req.body) as Map;
          files[path] = utf8.decode(base64.decode(body['content'] as String));
          return http.Response(jsonEncode({'content': {'sha': 'sha$puts'}}), 201);
        }
        // GET fichier ou dossier
        if (files.containsKey(path)) {
          return http.Response(
              jsonEncode({'content': base64.encode(utf8.encode(files[path]!)), 'sha': 'x'}), 200);
        }
        final children = files.keys
            .where((k) => k.startsWith('$path/'))
            .map((k) => k.substring(path.length + 1).split('/').first)
            .toSet();
        if (children.isEmpty) return http.Response('{}', 404);
        return http.Response(jsonEncode([for (final c in children) {'name': c}]), 200);
      });

      final store = await memStore();
      final p = await store.createParking('Parking Central');
      final s = ParkSessionStore(store.db, parking: p, deviceId: await store.deviceId());
      await s.save(entry('PCA-000001', DateTime(2026, 10, 21, 8), plate: '11 AB 2345'));
      await s.save(entry('PCA-000002', DateTime(2026, 10, 21, 9), amount: 300, t: VehicleType.voiture,
          out: DateTime(2026, 10, 21, 11)));

      final sync = SyncService(store, client: client, clock: () => now);
      await sync.saveConfig(const SyncConfig(repo: 'omzakrevo/parkfaso-data', token: 'github_pat_0123456789abcdefghij'));
      await sync.pushAll();
      expect(sync.state, SyncState.ok);
      final device = await store.deviceId();
      expect(files.keys, containsAll([
        'parkings/${p.id}/parking.json',
        'parkings/${p.id}/$device/2026-10.json',
        'parkings/${p.id}/$device/etat.json',
      ]));

      // 2e synchro sans changement : seul l'état (heure de synchro) est renvoyé.
      final before = puts;
      await sync.pushAll();
      expect(puts - before, 1);

      final remote = await sync.fetchRemote();
      expect(remote.single.name, 'Parking Central');
      expect(remote.single.stats.inside, 1);
      expect(remote.single.stats.todayTotal, 400);
      expect(remote.single.sessions.first.ticketBase, 'PCA-000002');
      expect(remote.single.lastSync, now);
    });

    test('jeton refusé : message clair', () async {
      final store = await memStore();
      final sync = SyncService(store, client: MockClient((_) async => http.Response('{}', 401)), clock: () => now);
      await expectLater(
          sync.saveConfig(const SyncConfig(repo: 'a/b', token: 'github_pat_0123456789abcdefghij')),
          throwsA(isA<SyncException>().having((e) => e.message, 'm', contains('Jeton'))));
    });
  });
}
