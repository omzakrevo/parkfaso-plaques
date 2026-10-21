// PARKFASO — Licences gérées par GitHub, sans base de données.
//
// • Une licence est un texte signé (Ed25519) par OMZAKREVO avec la clé privée.
//   L'application la vérifie HORS LIGNE avec la clé publique ci-dessous :
//   impossible de fabriquer ou modifier une licence (nombre de parkings, date).
// • Les licences révoquées sont listées dans le dépôt GitHub public
//   (licences/revoquees.json). L'application relit cette liste quand elle a
//   Internet (au plus une fois par jour) et la garde en mémoire.
// • Sans licence : essai gratuit de 7 jours, 1 parking.
//
// Création / révocation : page docs/licences/index.html (voir LICENCES.md).

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'park_store.dart';

/// Clé publique OMZAKREVO (la clé privée correspondante ne quitte jamais le propriétaire).
const kLicencePublicKey = 'JWxlKDtnSsFuvf0FCQLqPkYkr8uCgM0BRsphKJciOhQ=';

const kRevocationUrl =
    'https://raw.githubusercontent.com/omzakrevo/parkfaso-plaques/main/licences/revoquees.json';

const kTrialDays = 7;

class Licence {
  const Licence({
    required this.id,
    required this.client,
    required this.maxParkings,
    required this.issuedAt,
    this.expiresAt,
  });

  final String id;
  final String client;
  final int maxParkings;
  final DateTime issuedAt;

  /// null = licence à vie.
  final DateTime? expiresAt;

  bool isExpired(DateTime now) => expiresAt != null && now.isAfter(expiresAt!);
}

enum LicenceStatus { trial, active, trialOver, expired, revoked, invalid }

class LicenceState {
  const LicenceState(this.status, {this.licence, this.trialEnds, this.message});

  final LicenceStatus status;
  final Licence? licence;
  final DateTime? trialEnds;
  final String? message;

  /// L'application peut enregistrer des entrées.
  bool get canOperate => status == LicenceStatus.active || status == LicenceStatus.trial;

  int get maxParkings => status == LicenceStatus.active ? licence!.maxParkings : 1;

  String describe(DateTime now) => switch (status) {
        LicenceStatus.active => licence!.expiresAt == null
            ? 'Licence ${licence!.id} · ${licence!.client} · illimitée'
            : 'Licence ${licence!.id} · ${licence!.client} · jusqu\'au '
                '${_d(licence!.expiresAt!)}',
        LicenceStatus.trial =>
          'Essai gratuit · ${trialEnds!.difference(now).inDays + 1} jour(s) restant(s)',
        LicenceStatus.trialOver => 'Période d\'essai terminée',
        LicenceStatus.expired => 'Licence expirée le ${_d(licence!.expiresAt!)}',
        LicenceStatus.revoked => 'Licence ${licence?.id ?? ''} révoquée',
        LicenceStatus.invalid => message ?? 'Licence invalide',
      };

  static String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class LicenceException implements Exception {
  const LicenceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Lecture et vérification d'une clé de licence « `PKF1.données.signature` ».
class LicenceVerifier {
  LicenceVerifier({String publicKeyB64 = kLicencePublicKey})
      : _publicKey = SimplePublicKey(base64.decode(publicKeyB64), type: KeyPairType.ed25519);

  final SimplePublicKey _publicKey;
  final _algo = Ed25519();

  static String _clean(String key) => key.trim().replaceAll(RegExp(r'\s+'), '');

  Future<Licence> verify(String rawKey) async {
    final key = _clean(rawKey);
    final parts = key.split('.');
    if (parts.length != 3 || parts[0] != 'PKF1') {
      throw const LicenceException('Format de licence inconnu.');
    }
    final List<int> payload;
    final List<int> sig;
    try {
      payload = base64Url.decode(base64Url.normalize(parts[1]));
      sig = base64Url.decode(base64Url.normalize(parts[2]));
    } catch (_) {
      throw const LicenceException('Licence abîmée (copie incomplète ?).');
    }
    final ok = await _algo.verify(payload, signature: Signature(sig, publicKey: _publicKey));
    if (!ok) throw const LicenceException('Licence non authentique.');
    final m = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    final exp = (m['e'] as String?) ?? '';
    return Licence(
      id: m['id'] as String,
      client: m['c'] as String,
      maxParkings: (m['p'] as num).toInt(),
      issuedAt: DateTime.parse(m['i'] as String),
      // Valide jusqu'à la fin du jour indiqué.
      expiresAt: exp.isEmpty ? null : DateTime.parse(exp).add(const Duration(hours: 23, minutes: 59)),
    );
  }
}

/// État de la licence de ce téléphone.
class LicenceService {
  LicenceService(this.store, {LicenceVerifier? verifier, http.Client? client, DateTime Function()? clock,
      this.revocationUrl = kRevocationUrl})
      : verifier = verifier ?? LicenceVerifier(),
        _http = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final ParkStore store;
  final LicenceVerifier verifier;
  final http.Client _http;
  final DateTime Function() _clock;
  final String revocationUrl;

  Future<DateTime> _trialStart() async {
    final v = await store.meta('trial_start');
    if (v != null) return DateTime.parse(v);
    final now = _clock();
    await store.setMeta('trial_start', now.toIso8601String());
    return now;
  }

  Future<Set<String>> _revokedCache() async {
    final v = await store.meta('revoked_ids');
    return v == null ? <String>{} : (jsonDecode(v) as List).cast<String>().toSet();
  }

  /// État actuel (hors ligne).
  Future<LicenceState> current() async {
    final now = _clock();
    final key = await store.meta('licence_key');
    if (key == null) {
      final ends = (await _trialStart()).add(const Duration(days: kTrialDays));
      return now.isAfter(ends)
          ? LicenceState(LicenceStatus.trialOver, trialEnds: ends)
          : LicenceState(LicenceStatus.trial, trialEnds: ends);
    }
    try {
      final lic = await verifier.verify(key);
      if ((await _revokedCache()).contains(lic.id)) return LicenceState(LicenceStatus.revoked, licence: lic);
      if (lic.isExpired(now)) return LicenceState(LicenceStatus.expired, licence: lic);
      return LicenceState(LicenceStatus.active, licence: lic);
    } on LicenceException catch (e) {
      return LicenceState(LicenceStatus.invalid, message: e.message);
    }
  }

  /// Active une licence saisie ou scannée. Lève [LicenceException] si refusée.
  Future<LicenceState> activate(String key) async {
    final lic = await verifier.verify(key);
    if (lic.isExpired(_clock())) throw const LicenceException('Cette licence a déjà expiré.');
    await refreshRevocations();
    if ((await _revokedCache()).contains(lic.id)) {
      throw const LicenceException('Cette licence a été révoquée.');
    }
    await store.setMeta('licence_key', key.trim());
    return current();
  }

  /// Relit la liste des licences révoquées sur GitHub (au plus une fois par jour,
  /// sauf [force]). Sans Internet, la dernière liste connue est conservée.
  Future<bool> refreshRevocations({bool force = false}) async {
    final last = await store.meta('revoked_checked');
    if (!force && last != null && _clock().difference(DateTime.parse(last)) < const Duration(hours: 20)) {
      return true;
    }
    try {
      final r = await _http.get(Uri.parse(revocationUrl)).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return false;
      final ids = ((jsonDecode(r.body) as Map<String, dynamic>)['revoquees'] as List? ?? const [])
          .map((e) => e is Map ? e['id'] as String : e as String)
          .toList();
      await store.setMeta('revoked_ids', jsonEncode(ids));
      await store.setMeta('revoked_checked', _clock().toIso8601String());
      return true;
    } catch (_) {
      return false;
    }
  }
}
