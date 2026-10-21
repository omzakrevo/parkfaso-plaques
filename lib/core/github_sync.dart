// PARKFASO — Synchronisation par GitHub (suivi des parkings à distance).
//
// Chaque client a SON dépôt GitHub privé (ex. omzakrevo/parkfaso-data-client1)
// et un jeton « fine-grained » limité à ce seul dépôt (Contents : lecture/écriture).
//
// Chaque téléphone écrit uniquement ses propres fichiers (aucun conflit) :
//   parkings/<parking>/parking.json              nom, code, tarifs
//   parkings/<parking>/<téléphone>/etat.json     présents, CA du jour/mois, dernière synchro
//   parkings/<parking>/<téléphone>/AAAA-MM.json  toutes les entrées du mois
//
// Le téléphone du propriétaire lit ces fichiers pour afficher tous ses parkings.
// Hors ligne, rien n'est perdu : la synchro suivante renvoie l'état complet.

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../plaque/plate_models.dart';
import 'models.dart';
import 'park_store.dart';

class SyncConfig {
  const SyncConfig({required this.repo, required this.token, this.branch = 'main'});

  /// « propriétaire/dépôt »
  final String repo;
  final String token;
  final String branch;

  bool get isValid => RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(repo) && token.length > 20;
}

class SyncException implements Exception {
  const SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Accès minimal à l'API « contents » de GitHub.
class GitHubContents {
  GitHubContents(this.config, {http.Client? client}) : _http = client ?? http.Client();

  final SyncConfig config;
  final http.Client _http;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${config.token}',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Uri _url(String path) => Uri.parse('https://api.github.com/repos/${config.repo}/contents/$path'
      '?ref=${config.branch}');

  Never _fail(http.Response r) {
    switch (r.statusCode) {
      case 401:
        throw const SyncException('Jeton GitHub refusé (expiré ou incorrect).');
      case 403:
        throw const SyncException('Accès refusé : le jeton doit avoir « Contents : Read and write » sur ce dépôt.');
      case 404:
        throw const SyncException('Dépôt introuvable : vérifiez « propriétaire/dépôt » et l\'accès du jeton.');
      default:
        throw SyncException('GitHub a répondu ${r.statusCode}.');
    }
  }

  /// Lit un fichier JSON. null s'il n'existe pas.
  Future<(Object?, String?)> readJson(String path) async {
    final r = await _http.get(_url(path), headers: _headers).timeout(const Duration(seconds: 15));
    if (r.statusCode == 404) return (null, null);
    if (r.statusCode != 200) _fail(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    final content = utf8.decode(base64.decode((m['content'] as String).replaceAll('\n', '')));
    return (jsonDecode(content), m['sha'] as String?);
  }

  /// Liste un dossier (noms des sous-dossiers / fichiers). Vide s'il n'existe pas.
  Future<List<String>> list(String path) async {
    final r = await _http.get(_url(path), headers: _headers).timeout(const Duration(seconds: 15));
    if (r.statusCode == 404) return const [];
    if (r.statusCode != 200) _fail(r);
    return (jsonDecode(r.body) as List).map((e) => (e as Map)['name'] as String).toList();
  }

  /// Crée ou remplace un fichier JSON. Retourne le nouveau sha.
  Future<String> writeJson(String path, Object data, {String? sha, String? message}) async {
    Future<http.Response> put(String? s) => _http
        .put(Uri.parse('https://api.github.com/repos/${config.repo}/contents/$path'),
            headers: _headers,
            body: jsonEncode({
              'message': message ?? 'PARKFASO : $path',
              'branch': config.branch,
              'content': base64.encode(utf8.encode(const JsonEncoder.withIndent(' ').convert(data))),
              if (s != null) 'sha': s,
            }))
        .timeout(const Duration(seconds: 20));
    var r = await put(sha);
    if (r.statusCode == 409 || r.statusCode == 422) {
      // sha inconnu ou périmé : on relit et on réessaie une fois.
      final (_, fresh) = await readJson(path);
      r = await put(fresh);
    }
    if (r.statusCode != 200 && r.statusCode != 201) _fail(r);
    return ((jsonDecode(r.body) as Map)['content'] as Map)['sha'] as String;
  }

  /// Vérifie l'accès (lecture du dépôt).
  Future<void> check() async {
    final r = await _http
        .get(Uri.parse('https://api.github.com/repos/${config.repo}'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) _fail(r);
    final perms = (jsonDecode(r.body) as Map)['permissions'] as Map?;
    if (perms != null && perms['push'] != true) {
      throw const SyncException('Le jeton peut lire mais pas écrire : activez « Contents : Read and write ».');
    }
  }
}

/// Résumé d'un parking lu à distance.
class RemoteParking {
  const RemoteParking({
    required this.id,
    required this.name,
    required this.stats,
    required this.lastSync,
    required this.devices,
    required this.dailyThisMonth,
    required this.sessions,
  });

  final String id;
  final String name;
  final ParkingStats stats;
  final DateTime? lastSync;
  final int devices;
  final List<RevenuePoint> dailyThisMonth;
  final List<ParkingSession> sessions;
}

enum SyncState { off, idle, syncing, ok, error }

class SyncService extends ChangeNotifier {
  SyncService(this.store, {this.client, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final ParkStore store;
  final http.Client? client;
  final DateTime Function() _clock;

  SyncState state = SyncState.off;
  String? lastError;
  DateTime? lastSync;
  Timer? _debounce;

  Future<SyncConfig?> config() async {
    final repo = await store.meta('sync_repo');
    final token = await store.meta('sync_token');
    if (repo == null || token == null) return null;
    return SyncConfig(repo: repo, token: token);
  }

  Future<void> saveConfig(SyncConfig? c, {bool check = true}) async {
    if (c != null && check) await GitHubContents(c, client: client).check();
    await store.setMeta('sync_repo', c?.repo);
    await store.setMeta('sync_token', c?.token);
    state = c == null ? SyncState.off : SyncState.idle;
    notifyListeners();
  }

  Future<void> load() async {
    final c = await config();
    final last = await store.meta('sync_last');
    lastSync = last == null ? null : DateTime.parse(last);
    state = c == null ? SyncState.off : SyncState.idle;
    notifyListeners();
  }

  /// Synchronise dans 20 s (regroupe plusieurs entrées rapprochées).
  void schedule() {
    if (state == SyncState.off) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 20), () => pushAll().catchError((_) {}));
  }

  /// Publie les données de tous les parkings de ce téléphone.
  Future<void> pushAll() async {
    final c = await config();
    if (c == null) return;
    state = SyncState.syncing;
    lastError = null;
    notifyListeners();
    try {
      final gh = GitHubContents(c, client: client);
      final device = await store.deviceId();
      final now = _clock();
      for (final p in await store.parkings()) {
        final sessions = ParkSessionStore(store.db, parking: p, deviceId: device);
        await _put(gh, 'parkings/${p.id}/parking.json', {
          'id': p.id,
          'name': p.name,
          'code': p.code,
          'prices': {for (final e in p.prices.entries) e.key.dbValue: e.value},
          'helmet_price': p.helmetPrice,
        });
        final months = [DateTime(now.year, now.month), if (now.day <= 3) DateTime(now.year, now.month - 1)];
        for (final m in months) {
          final rows = await sessions.monthRows(m.year, m.month);
          final mine = rows.where((r) => r['device_id'] == null || r['device_id'] == device).toList();
          await _put(gh, 'parkings/${p.id}/$device/${m.year}-${m.month.toString().padLeft(2, '0')}.json', {
            'parking': p.id,
            'device': device,
            'sessions': [for (final r in mine) _compact(r)],
          });
        }
        final st = await sessions.stats(now);
        await _put(gh, 'parkings/${p.id}/$device/etat.json', {
          'inside': st.inside,
          'today_count': st.todayCount,
          'today_total': st.todayTotal,
          'month_total': st.monthTotal,
          'synced_at': now.toIso8601String(),
        }, force: true);
      }
      lastSync = now;
      await store.setMeta('sync_last', now.toIso8601String());
      state = SyncState.ok;
    } catch (e) {
      lastError = e is SyncException ? e.message : 'Pas de connexion Internet (nouvel essai plus tard).';
      state = SyncState.error;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// N'envoie un fichier que si son contenu a changé.
  Future<void> _put(GitHubContents gh, String path, Map<String, Object?> data, {bool force = false}) async {
    final hash = sha1.convert(utf8.encode(jsonEncode(data))).toString();
    final known = await store.meta('sync_hash:$path');
    if (!force && known == hash) return;
    final sha = await store.meta('sync_sha:$path');
    final newSha = await gh.writeJson(path, data, sha: sha);
    await store.setMeta('sync_sha:$path', newSha);
    await store.setMeta('sync_hash:$path', hash);
  }

  static Map<String, Object?> _compact(Map<String, Object?> r) => {
        't': r['ticket_number'],
        'v': r['vehicle_type'],
        'in': r['entered_at'],
        'out': r['exited_at'],
        'h': r['helmet_count'],
        'a': r['amount'],
        'p': r['license_plate'],
        'by': r['entered_by'],
      };

  /// Lit tous les parkings du dépôt (téléphone du propriétaire).
  Future<List<RemoteParking>> fetchRemote() async {
    final c = await config();
    if (c == null) throw const SyncException('Synchronisation non configurée.');
    final gh = GitHubContents(c, client: client);
    final now = _clock();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final out = <RemoteParking>[];
    for (final pid in await gh.list('parkings')) {
      final (info, _) = await gh.readJson('parkings/$pid/parking.json');
      if (info == null) continue;
      final devices = (await gh.list('parkings/$pid')).where((n) => !n.endsWith('.json')).toList();
      var inside = 0;
      DateTime? last;
      final sessions = <ParkingSession>[];
      for (final d in devices) {
        final (etat, _) = await gh.readJson('parkings/$pid/$d/etat.json');
        if (etat is Map) {
          inside += (etat['inside'] as num?)?.toInt() ?? 0;
          final s = DateTime.tryParse(etat['synced_at'] as String? ?? '');
          if (s != null && (last == null || s.isAfter(last))) last = s;
        }
        final (month, _) = await gh.readJson('parkings/$pid/$d/$monthKey.json');
        if (month is Map) {
          for (final r in (month['sessions'] as List? ?? const [])) {
            final m = r as Map;
            sessions.add(ParkingSession(
              vehicleType: VehicleType.fromDb(m['v'] as String?),
              ticketBase: m['t'] as String,
              enteredAt: DateTime.parse(m['in'] as String),
              exitedAt: m['out'] == null ? null : DateTime.parse(m['out'] as String),
              helmetCount: (m['h'] as num?)?.toInt() ?? 0,
              vehiclePrice: (m['a'] as num?)?.toInt() ?? 0,
              helmetPrice: 0,
              licensePlate: (m['p'] as String?) ?? '',
              plateCaptureMethod: PlateCaptureMethod.none,
              plateVerified: false,
              enteredBy: m['by'] as String?,
              parkingId: pid,
            ));
          }
        }
      }
      out.add(RemoteParking(
        id: pid,
        name: (info as Map)['name'] as String? ?? pid,
        stats: summarize(sessions, now, insideOverride: inside),
        lastSync: last,
        devices: devices.length,
        dailyThisMonth: dailyRevenue(sessions, DateTime(now.year, now.month), now),
        sessions: sessions..sort((a, b) => b.enteredAt.compareTo(a.enteredAt)),
      ));
    }
    return out;
  }

  static ParkingStats summarize(List<ParkingSession> s, DateTime now, {int? insideOverride}) {
    final day = DateTime(now.year, now.month, now.day);
    final month = DateTime(now.year, now.month);
    final today = s.where((x) => !x.enteredAt.isBefore(day));
    return ParkingStats(
      inside: insideOverride ?? s.where((x) => x.isInside).length,
      todayCount: today.length,
      todayTotal: today.fold(0, (a, x) => a + x.total),
      monthTotal: s.where((x) => !x.enteredAt.isBefore(month)).fold(0, (a, x) => a + x.total),
    );
  }

  static List<RevenuePoint> dailyRevenue(List<ParkingSession> s, DateTime from, DateTime to) => [
        for (var d = DateTime(from.year, from.month, from.day);
            !d.isAfter(to);
            d = DateTime(d.year, d.month, d.day + 1))
          () {
            final day = s.where((x) =>
                x.enteredAt.year == d.year && x.enteredAt.month == d.month && x.enteredAt.day == d.day);
            return RevenuePoint(d, day.length, day.fold(0, (a, x) => a + x.total));
          }(),
      ];
}
