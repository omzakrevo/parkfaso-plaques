// PARKFASO — Historique : filtres, recherche, totaux, export PDF / Excel.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/exporter.dart';
import '../core/models.dart';
import '../plaque/plate_models.dart';
import '../tickets/tickets.dart';
import 'app_controller.dart';
import 'home_screen.dart';
import 'parkfaso_theme.dart';
import 'session_sheet.dart';

/// Partage un fichier exporté (WhatsApp, e-mail, Drive…). Remplaçable en test.
Future<void> Function(String fileName, Uint8List bytes, String mime) shareExport = _systemShare;

Future<void> _systemShare(String fileName, Uint8List bytes, String mime) async {
  final dir = await getTemporaryDirectory();
  final f = File(p.join(dir.path, fileName));
  await f.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: mime)], subject: fileName));
}

enum PeriodPreset { today, yesterday, week, month, custom }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  HistoryFilter? _filter;
  PeriodPreset _preset = PeriodPreset.today;
  List<ParkingSession>? _items;
  int _rev = -1;
  bool _exporting = false;
  final _search = TextEditingController();

  HistoryFilter _base(AppController app) => _filter ??= HistoryFilter.today(app.clock());

  Future<void> _load(AppController app) async {
    final f = _base(app);
    final list = await app.sessions!.history(f);
    if (mounted) setState(() => _items = list);
  }

  void _setPreset(AppController app, PeriodPreset p) async {
    final now = app.clock();
    final today = HistoryFilter.dayStart(now);
    DateTimeRange? range;
    switch (p) {
      case PeriodPreset.today:
        range = DateTimeRange(start: today, end: today);
      case PeriodPreset.yesterday:
        final y = today.subtract(const Duration(days: 1));
        range = DateTimeRange(start: y, end: y);
      case PeriodPreset.week:
        range = DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
      case PeriodPreset.month:
        range = DateTimeRange(start: DateTime(now.year, now.month), end: today);
      case PeriodPreset.custom:
        range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2024),
          lastDate: today,
          initialDateRange: DateTimeRange(start: _base(app).from, end: HistoryFilter.dayStart(_base(app).to)),
          helpText: 'Choisir la période',
          saveText: 'Valider',
        );
        if (range == null) return;
    }
    setState(() {
      _preset = p;
      _filter = _base(app).copyWith(from: HistoryFilter.dayStart(range!.start), to: HistoryFilter.dayEnd(range.end));
      _items = null;
    });
    _load(app);
  }

  void _update(AppController app, HistoryFilter f) {
    setState(() {
      _filter = f;
      _items = null;
    });
    _load(app);
  }

  Future<void> _export(AppController app, String kind) async {
    final items = _items ?? const <ParkingSession>[];
    final f = _base(app);
    setState(() => _exporting = true);
    try {
      final name = app.parking!.name;
      if (kind == 'pdf') {
        final bytes = await buildHistoryPdf(parkingName: name, filter: f, sessions: items, now: app.clock());
        await shareExport(exportFileName(name, f, 'pdf'), bytes, 'application/pdf');
      } else {
        final bytes = buildHistoryXlsx(parkingName: name, filter: f, sessions: items, now: app.clock());
        await shareExport(exportFileName(name, f, 'xlsx'), bytes,
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(backgroundColor: ParkColors.red, content: Text('Export impossible : $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _periodLabel(HistoryFilter f) {
    final a = formatDate(f.from), b = formatDate(f.to);
    return a == b ? a : '$a → $b';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (_rev != app.revision) {
      _rev = app.revision;
      _load(app);
    }
    final f = _base(app);
    final items = _items;
    final total = items?.fold<int>(0, (a, s) => a + s.total) ?? 0;
    final now = app.clock();
    const presets = {
      PeriodPreset.today: 'Aujourd\'hui',
      PeriodPreset.yesterday: 'Hier',
      PeriodPreset.week: '7 jours',
      PeriodPreset.month: 'Ce mois',
      PeriodPreset.custom: 'Période…',
    };

    // Regroupement par jour (en-têtes de section).
    final groups = <DateTime, List<ParkingSession>>{};
    for (final s in items ?? const <ParkingSession>[]) {
      groups.putIfAbsent(HistoryFilter.dayStart(s.enteredAt), () => []).add(s);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)),
            )
          else
            PopupMenuButton<String>(
              key: const Key('export-menu'),
              tooltip: 'Exporter',
              icon: const Icon(Icons.ios_share),
              onSelected: (k) => _export(app, k),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'pdf', key: Key('export-pdf'),
                    child: ListTile(leading: Icon(Icons.picture_as_pdf, color: Color(0xFFDC2626)),
                        title: Text('Exporter en PDF'))),
                PopupMenuItem(value: 'xlsx', key: Key('export-xlsx'),
                    child: ListTile(leading: Icon(Icons.table_chart, color: Color(0xFF16A34A)),
                        title: Text('Exporter en Excel'))),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(app),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          TextField(
            key: const Key('history-search'),
            controller: _search,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (v) => _update(app, f.copyWith(query: v)),
            onChanged: (v) {
              if (v.isEmpty) _update(app, f.copyWith(query: ''));
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Rechercher une plaque ou un ticket',
              suffixIcon: IconButton(
                key: const Key('history-search-go'),
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _update(app, f.copyWith(query: _search.text)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final e in presets.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: Key('period-${e.key.name}'),
                    label: Text(e.value),
                    selected: _preset == e.key,
                    labelStyle: TextStyle(color: _preset == e.key ? Colors.white : null, fontWeight: FontWeight.w700),
                    onSelected: (_) => _setPreset(app, e.key),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _Dropdown<VehicleType?>(
                value: f.vehicleType,
                items: {null: 'Tous les véhicules', for (final t in app.parking!.enabledVehicles) t: t.label},
                onChanged: (v) => _update(app, v == null ? f.copyWith(clearVehicle: true) : f.copyWith(vehicleType: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Dropdown<StatusFilter>(
                key: const Key('status-filter'),
                value: f.status,
                items: const {
                  StatusFilter.all: 'Entrés et sortis',
                  StatusFilter.inside: 'Encore présents',
                  StatusFilter.exited: 'Sortis',
                },
                onChanged: (v) => _update(app, f.copyWith(status: v)),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          // Résumé de la sélection
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: ParkColors.headerGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_periodLabel(f), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                  const SizedBox(height: 2),
                  AnimatedCount(items?.length ?? 0, suffix: ' entrées',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const Text('Total', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                AnimatedCount(total, money: true, suffix: ' FCFA', key: const Key('history-total'),
                    style: const TextStyle(color: ParkColors.amber, fontSize: 18, fontWeight: FontWeight.w900)),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          if (items == null)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else if (items.isEmpty)
            EmptyState(
              icon: f.query.isEmpty ? Icons.event_busy : Icons.search_off,
              title: f.query.isEmpty ? 'Aucune entrée sur cette période' : 'Aucun résultat pour « ${f.query} »',
              subtitle: f.query.isEmpty ? null : 'La recherche porte sur la période choisie.',
            )
          else
            for (final (gi, g) in groups.entries.indexed) ...[
              if (groups.length > 1)
                Padding(
                  padding: EdgeInsets.only(top: gi == 0 ? 0 : 12, bottom: 6, left: 2),
                  child: Row(children: [
                    Text(formatDate(g.key),
                        style: const TextStyle(fontWeight: FontWeight.w800, color: ParkColors.navy)),
                    const Spacer(),
                    Text('${g.value.length} · ${AnimatedCount.group(g.value.fold(0, (a, s) => a + s.total))} F',
                        style: const TextStyle(color: ParkColors.muted, fontWeight: FontWeight.w600)),
                  ]),
                ),
              Card(
                child: Column(children: [
                  for (final (i, s) in g.value.indexed) ...[
                    if (i > 0) const Divider(indent: 64),
                    SessionTile(session: s, now: now, onTap: () => showSessionSheet(context, s))
                        .entrance(i),
                  ],
                ]),
              ),
            ],
          if (items != null && items.length >= 500)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('500 premières entrées affichées : réduisez la période pour tout voir.',
                  style: TextStyle(color: ParkColors.muted, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({super.key, required this.value, required this.items, required this.onChanged});
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ParkColors.line),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            isExpanded: true,
            value: value,
            borderRadius: BorderRadius.circular(12),
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: ParkColors.ink),
            items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => onChanged(v as T),
          ),
        ),
      );
}
