// PARKFASO — État global : parking actif, utilisateur, licence, statistiques.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/auth.dart';
import '../core/github_sync.dart';
import '../core/licence.dart';
import '../core/models.dart';
import '../core/park_store.dart';
import '../plaque/plate_camera_source.dart';
import '../plaque/plate_ocr_service.dart';
import '../plaque/plate_photo_store.dart';
import '../tickets/bluetooth_printer.dart';
import '../tickets/tickets.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    required this.auth,
    required this.licences,
    required this.sync,
    required this.printer,
    required this.ocr,
    required this.photoStore,
    TicketPrinter? ticketPrinter,
    this.cameraFactory,
    this.scannerBuilder,
    DateTime Function()? clock,
  })  : ticketPrinter = ticketPrinter ?? printer,
        clock = clock ?? DateTime.now {
    auth.addListener(_onAuth);
  }

  final ParkStore store;
  final AuthService auth;
  final LicenceService licences;
  final SyncService sync;
  final BluetoothThermalPrinter printer;
  final TicketPrinter ticketPrinter;
  final PlateOcrService ocr;
  final PlatePhotoStore photoStore;
  final PlateCameraSource Function()? cameraFactory;
  final Widget Function(ValueChanged<String> onCode)? scannerBuilder;
  final DateTime Function() clock;

  List<Parking> parkings = const [];
  Parking? parking;
  ParkSessionStore? sessions;
  LicenceState licence = const LicenceState(LicenceStatus.trial);
  ParkingStats stats = ParkingStats.empty;
  bool needsSetup = true;
  String deviceId = '';
  String deviceLetter = 'A';
  Timer? _syncTimer;

  /// Augmente à chaque entrée/sortie : les écrans se rafraîchissent.
  int revision = 0;

  bool get isAdmin => auth.isAdmin;

  Future<void> load() async {
    deviceId = await store.deviceId();
    deviceLetter = await store.deviceLetter();
    needsSetup = !(await store.hasAdmin()) || (await store.parkings()).isEmpty;
    licence = await licences.current();
    await _loadParkings();
    await sync.load();
    // Révocations et synchro en arrière-plan : jamais bloquant.
    unawaited(licences.refreshRevocations().then((_) async {
      licence = await licences.current();
      notifyListeners();
    }).catchError((_) {}));
    sync.removeListener(_autoSync);
    sync.addListener(_autoSync);
    _autoSync();
    notifyListeners();
  }

  /// Synchro automatique toutes les 10 min, seulement si elle est configurée.
  void _autoSync() {
    if (sync.state == SyncState.off) {
      _syncTimer?.cancel();
      _syncTimer = null;
    } else {
      _syncTimer ??= Timer.periodic(const Duration(minutes: 10), (_) => sync.pushAll().catchError((_) {}));
    }
  }

  Future<void> _loadParkings() async {
    parkings = await store.parkings();
    final activeId = await store.activeParkingId();
    parking = parkings.where((p) => p.id == activeId).firstOrNull ?? parkings.firstOrNull;
    sessions = parking == null
        ? null
        : ParkSessionStore(store.db, parking: parking!, deviceId: deviceId, deviceLetter: deviceLetter,
            currentUser: auth.user?.name);
    await refreshStats();
  }

  void _onAuth() {
    sessions?.currentUser = auth.user?.name;
    notifyListeners();
  }

  Future<void> refreshStats() async {
    stats = sessions == null ? ParkingStats.empty : await sessions!.stats(clock());
    notifyListeners();
  }

  /// À appeler après une entrée ou une sortie.
  Future<void> changed() async {
    revision++;
    await refreshStats();
    sync.schedule();
  }

  Future<void> switchParking(Parking p) async {
    await store.setActiveParking(p.id);
    await _loadParkings();
  }

  Future<Parking> createParking(String name) async {
    if (parkings.length >= licence.maxParkings) {
      throw StateError(licence.status == LicenceStatus.active
          ? 'Votre licence autorise ${licence.maxParkings} parking(s).'
          : 'L\'essai gratuit est limité à 1 parking. Activez une licence.');
    }
    final p = await store.createParking(name, now: clock());
    if (parking == null) {
      await store.setActiveParking(p.id);
      // Entrées enregistrées avant la mise à jour multi-parkings : rattachées au 1er parking.
      await store.db.update('parking_sessions', {'parking_id': p.id}, where: 'parking_id IS NULL');
    }
    await _loadParkings();
    return p;
  }

  Future<void> saveParking(Parking p) async {
    await store.saveParking(p);
    await _loadParkings();
  }

  Future<void> setDeviceLetter(String l) async {
    await store.setDeviceLetter(l);
    deviceLetter = await store.deviceLetter();
    await _loadParkings();
  }

  Future<void> completeSetup() async {
    needsSetup = false;
    await _loadParkings();
  }

  Future<void> activateLicence(String key) async {
    licence = await licences.activate(key);
    notifyListeners();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    sync.removeListener(_autoSync);
    auth.removeListener(_onAuth);
    super.dispose();
  }
}

/// Donne accès au contrôleur dans tout l'arbre de widgets.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
