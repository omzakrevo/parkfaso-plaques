// PARKFASO — Suivi des parkings à distance (données publiées sur GitHub).

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/github_sync.dart';
import '../core/models.dart';
import '../tickets/ticket_scan_screen.dart';
import 'app_controller.dart';
import 'home_screen.dart';
import 'parkfaso_theme.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

String ago(DateTime? t, DateTime now) {
  if (t == null) return 'jamais synchronisé';
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'à l\'instant';
  if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
  if (d.inHours < 24) return 'il y a ${d.inHours} h';
  return 'il y a ${d.inDays} j';
}

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  Future<List<RemoteParking>>? _future;

  void _reload(AppController app) => setState(() => _future = app.sync.fetchRemote());

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final configured = app.sync.state != SyncState.off;
    if (configured && _future == null) _future = app.sync.fetchRemote();
    final now = app.clock();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parkings à distance'),
        actions: [
          if (configured) IconButton(onPressed: () => _reload(app), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: !configured
          ? ListView(padding: const EdgeInsets.all(16), children: [
              const EmptyState(
                icon: Icons.cloud_off,
                title: 'Synchronisation non configurée',
                subtitle: 'Reliez ce téléphone au dépôt GitHub de vos parkings pour suivre '
                    'les entrées et les recettes de chaque parking à distance.',
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AppScope(controller: app, child: const SyncSettingsScreen()))),
                icon: const Icon(Icons.settings),
                label: const Text('Configurer'),
              ),
            ])
          : FutureBuilder<List<RemoteParking>>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ListView(padding: const EdgeInsets.all(16), children: [
                    EmptyState(icon: Icons.wifi_off, title: 'Lecture impossible', subtitle: '${snap.error}'),
                    OutlinedButton(onPressed: () => _reload(app), child: const Text('Réessayer')),
                  ]);
                }
                final list = snap.data;
                if (list == null) return const Center(child: CircularProgressIndicator());
                if (list.isEmpty) {
                  return const EmptyState(icon: Icons.inbox, title: 'Aucun parking publié',
                      subtitle: 'Les parkings apparaissent après leur première synchronisation.');
                }
                final inside = list.fold<int>(0, (a, p) => a + p.stats.inside);
                final today = list.fold<int>(0, (a, p) => a + p.stats.todayTotal);
                final month = list.fold<int>(0, (a, p) => a + p.stats.monthTotal);
                return RefreshIndicator(
                  onRefresh: () async => _reload(app),
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(gradient: ParkColors.headerGradient,
                          borderRadius: BorderRadius.circular(18)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${list.length} parking${list.length > 1 ? 's' : ''}',
                            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: KpiTile(label: 'Présents', value: inside, icon: Icons.local_parking, onDark: true)),
                          const SizedBox(width: 8),
                          Expanded(child: KpiTile(label: 'Aujourd\'hui', value: today, icon: Icons.today, onDark: true, money: true)),
                          const SizedBox(width: 8),
                          Expanded(child: KpiTile(label: 'Ce mois', value: month, icon: Icons.calendar_month, onDark: true, money: true)),
                        ]),
                      ]),
                    ).animate().fadeIn().slideY(begin: 0.1, end: 0),
                    const SizedBox(height: 16),
                    for (final (i, p) in list.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _RemoteCard(parking: p, now: now).entrance(i, baseMs: 80),
                      ),
                  ]),
                );
              },
            ),
    );
  }
}

class _RemoteCard extends StatelessWidget {
  const _RemoteCard({required this.parking, required this.now});
  final RemoteParking parking;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = parking;
    final stale = p.lastSync == null || now.difference(p.lastSync!) > const Duration(minutes: 40);
    final maxDay = p.dailyThisMonth.fold<int>(1, (a, d) => d.total > a ? d.total : a);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AppScope(controller: AppScope.read(context), child: _RemoteDetail(parking: p)))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.local_parking, color: ParkColors.navy),
              const SizedBox(width: 8),
              Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              Icon(Icons.circle, size: 9, color: stale ? ParkColors.warn : ParkColors.green),
              const SizedBox(width: 5),
              Text(ago(p.lastSync, now),
                  style: TextStyle(fontSize: 12, color: stale ? ParkColors.warn : ParkColors.muted)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _mini('Présents', '${p.stats.inside}'),
              _mini('Entrées du jour', '${p.stats.todayCount}'),
              _mini('Recette du jour', '${AnimatedCount.group(p.stats.todayTotal)} F'),
              _mini('Ce mois', '${AnimatedCount.group(p.stats.monthTotal)} F'),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              height: 34,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final d in p.dailyThisMonth)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      height: 3 + 31 * d.total / maxDay,
                      decoration: BoxDecoration(
                        color: d.period.day == now.day ? ParkColors.amber : ParkColors.navy.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _mini(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: ParkColors.muted)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        ]),
      );
}

class _RemoteDetail extends StatelessWidget {
  const _RemoteDetail({required this.parking});
  final RemoteParking parking;

  @override
  Widget build(BuildContext context) {
    final now = AppScope.of(context).clock();
    final inside = parking.sessions.where((s) => s.isInside).toList();
    final recent = parking.sessions.take(50).toList();
    return Scaffold(
      appBar: AppBar(title: Text(parking.name)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
            child: SizedBox(
              height: 200,
              child: RevenueBarChart(
                points: parking.dailyThisMonth,
                label: (p) => '${p.period.day}',
                highlight: (p) => p.period.day == now.day,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel('Au parking · ${inside.length}'),
        if (inside.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Aucun véhicule présent.')))
        else
          Card(child: Column(children: [
            for (final (i, s) in inside.indexed) ...[
              if (i > 0) const Divider(indent: 64),
              SessionTile(session: s, now: now, showDate: true),
            ],
          ])),
        const SizedBox(height: 16),
        SectionLabel('Dernières entrées (ce mois)'),
        Card(child: Column(children: [
          for (final (i, s) in recent.indexed) ...[
            if (i > 0) const Divider(indent: 64),
            SessionTile(session: s, now: now, showDate: true),
          ],
        ])),
        const SizedBox(height: 10),
        Text('Mis à jour ${ago(parking.lastSync, now)} · ${parking.devices} téléphone(s) · '
            'durée moyenne ${_avg(parking.sessions, now)}',
            style: const TextStyle(color: ParkColors.muted, fontSize: 12)),
      ]),
    );
  }

  String _avg(List<dynamic> s, DateTime now) {
    final exited = parking.sessions.where((x) => !x.isInside).toList();
    if (exited.isEmpty) return '-';
    final mins = exited.fold<int>(0, (a, x) => a + x.stayAt(now).inMinutes) ~/ exited.length;
    return formatDuration(Duration(minutes: mins));
  }
}

/// Utilisé par les tests pour vérifier l'agrégat.
ParkingStats remoteTotals(List<RemoteParking> l) => ParkingStats(
      inside: l.fold(0, (a, p) => a + p.stats.inside),
      todayCount: l.fold(0, (a, p) => a + p.stats.todayCount),
      todayTotal: l.fold(0, (a, p) => a + p.stats.todayTotal),
      monthTotal: l.fold(0, (a, p) => a + p.stats.monthTotal),
    );
