// PARKFASO — Rapports : chiffre d'affaires par jour, par mois, par véhicule.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/models.dart';
import '../core/park_store.dart';
import '../plaque/plate_models.dart';
import 'app_controller.dart';
import 'parkfaso_theme.dart';
import 'remote_screen.dart';

const _months = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc'];
const _monthsLong = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre',
  'octobre', 'novembre', 'décembre'];

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportData {
  _ReportData(this.days, this.months, this.byVehicle, this.monthByVehicle);
  final List<RevenuePoint> days;
  final List<RevenuePoint> months;
  final Map<VehicleType, RevenuePoint> byVehicle;
  final Map<VehicleType, RevenuePoint> monthByVehicle;
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _monthly = false;
  bool _allParkings = false;
  int _year = 0;
  Future<_ReportData>? _data;
  String _key = '';

  Future<_ReportData> _load(AppController app) async {
    final now = app.clock();
    final stores = _allParkings
        ? [for (final p in app.parkings) ParkSessionStore(app.store.db, parking: p)]
        : [app.sessions!];
    final dayFrom = HistoryFilter.dayStart(now).subtract(const Duration(days: 13));
    List<RevenuePoint> sum(List<List<RevenuePoint>> lists) => [
          for (var i = 0; i < lists.first.length; i++)
            RevenuePoint(lists.first[i].period, lists.fold(0, (a, l) => a + l[i].count),
                lists.fold(0, (a, l) => a + l[i].total)),
        ];
    Map<VehicleType, RevenuePoint> merge(List<Map<VehicleType, RevenuePoint>> maps) {
      final out = <VehicleType, RevenuePoint>{};
      for (final m in maps) {
        for (final e in m.entries) {
          final o = out[e.key];
          out[e.key] = RevenuePoint(e.value.period, (o?.count ?? 0) + e.value.count, (o?.total ?? 0) + e.value.total);
        }
      }
      return out;
    }

    final yearStart = DateTime(_year), yearEnd = DateTime(_year, 12, 31, 23, 59, 59);
    return _ReportData(
      sum([for (final s in stores) await s.revenueByDay(dayFrom, now)]),
      sum([for (final s in stores) await s.revenueByMonth(_year)]),
      merge([for (final s in stores) await s.byVehicle(yearStart, yearEnd)]),
      merge([for (final s in stores) await s.byVehicle(DateTime(now.year, now.month), HistoryFilter.dayEnd(now))]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final now = app.clock();
    if (_year == 0) _year = now.year;
    final key = '${app.revision}-${app.parking?.id}-$_allParkings-$_year';
    if (key != _key) {
      _key = key;
      _data = _load(app);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapports'),
        actions: [
          TextButton.icon(
            key: const Key('open-remote'),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => AppScope(controller: app, child: const RemoteScreen()))),
            icon: const Icon(Icons.cloud_outlined, size: 20),
            label: const Text('À distance'),
          ),
        ],
      ),
      body: FutureBuilder<_ReportData>(
        future: _data,
        builder: (context, snap) {
          final d = snap.data;
          if (d == null) return const Center(child: CircularProgressIndicator());
          final today = d.days.last;
          final thisMonth = d.months[now.month - 1];
          final yearTotal = d.months.fold<int>(0, (a, m) => a + m.total);
          final activeDays = d.days.where((x) => x.count > 0).length;
          final avg = activeDays == 0 ? 0 : d.days.fold<int>(0, (a, x) => a + x.total) ~/ activeDays;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            if (app.parkings.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: false, label: Text(app.parking!.name, overflow: TextOverflow.ellipsis)),
                    const ButtonSegment(value: true, label: Text('Tous mes parkings')),
                  ],
                  selected: {_allParkings},
                  onSelectionChanged: (v) => setState(() => _allParkings = v.first),
                ),
              ),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.1,
              children: [
                KpiTile(label: 'Aujourd\'hui', value: today.total, money: true, icon: Icons.today,
                    color: ParkColors.green),
                KpiTile(label: 'Ce mois (${_monthsLong[now.month - 1]})', value: thisMonth.total, money: true,
                    icon: Icons.calendar_month, color: ParkColors.navy),
                KpiTile(label: 'Année $_year', value: yearTotal, money: true, icon: Icons.trending_up,
                    color: const Color(0xFF7C3AED)),
                KpiTile(label: 'Moyenne / jour (14 j)', value: avg, money: true, icon: Icons.functions,
                    color: const Color(0xFFF97316)),
              ].indexed.map((e) => e.$2.entrance(e.$1, baseMs: 70)).toList(),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: SegmentedButton<bool>(
                  key: const Key('report-mode'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Par jour'), icon: Icon(Icons.view_week, size: 18)),
                    ButtonSegment(value: true, label: Text('Par mois'), icon: Icon(Icons.calendar_view_month, size: 18)),
                  ],
                  selected: {_monthly},
                  onSelectionChanged: (v) => setState(() => _monthly = v.first),
                ),
              ),
              if (_monthly) ...[
                IconButton(onPressed: () => setState(() => _year--), icon: const Icon(Icons.chevron_left)),
                Text('$_year', style: const TextStyle(fontWeight: FontWeight.w800)),
                IconButton(
                    onPressed: _year >= now.year ? null : () => setState(() => _year++),
                    icon: const Icon(Icons.chevron_right)),
              ],
            ]),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 18, 14, 8),
                child: SizedBox(
                  height: 220,
                  child: RevenueBarChart(
                    key: ValueKey('chart-$_monthly-$_year'),
                    points: _monthly ? d.months : d.days,
                    label: (pt) => _monthly ? _months[pt.period.month - 1] : '${pt.period.day}',
                    highlight: (pt) => _monthly
                        ? pt.period.month == now.month && pt.period.year == now.year
                        : pt.period.day == now.day && pt.period.month == now.month,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            SectionLabel(_monthly ? 'Détail par mois · $_year' : 'Détail des 14 derniers jours'),
            Card(
              child: Column(children: [
                for (final (i, pt) in (_monthly ? d.months : d.days.reversed.toList()).indexed) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    dense: true,
                    title: Text(_monthly
                        ? '${_monthsLong[pt.period.month - 1][0].toUpperCase()}${_monthsLong[pt.period.month - 1].substring(1)}'
                        : '${pt.period.day.toString().padLeft(2, '0')}/${pt.period.month.toString().padLeft(2, '0')}/${pt.period.year}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${pt.count} entrée${pt.count > 1 ? 's' : ''}'),
                    trailing: Text('${AnimatedCount.group(pt.total)} FCFA',
                        style: TextStyle(fontWeight: FontWeight.w800,
                            color: pt.total > 0 ? ParkColors.ink : ParkColors.muted)),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 18),
            SectionLabel(_monthly ? 'Par type de véhicule · $_year' : 'Par type de véhicule · ce mois'),
            _VehicleBreakdown(data: _monthly ? d.byVehicle : d.monthByVehicle),
          ]);
        },
      ),
    );
  }
}

class RevenueBarChart extends StatelessWidget {
  const RevenueBarChart({super.key, required this.points, required this.label, required this.highlight});
  final List<RevenuePoint> points;
  final String Function(RevenuePoint) label;
  final bool Function(RevenuePoint) highlight;

  @override
  Widget build(BuildContext context) {
    final maxY = points.fold<int>(0, (a, p) => p.total > a ? p.total : a);
    // Graduations rondes : 100, 250, 500, 1 000, 2 500…
    double step = 100;
    for (final s in [100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000, 250000, 500000, 1000000]) {
      step = s.toDouble();
      if (maxY / s <= 4) break;
    }
    final top = maxY == 0 ? 400.0 : ((maxY / step).floor() + 1) * step;
    String short(double v) => v >= 1000000
        ? '${(v / 1000000).toStringAsFixed(1)}M'
        : v >= 1000
            ? '${(v / 1000).round()}k'
            : v.round().toString();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => BarChart(
        BarChartData(
          maxY: top,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: maxY == 0 ? 100 : step,
            getDrawingHorizontalLine: (_) => const FlLine(color: ParkColors.line, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                interval: maxY == 0 ? 100 : step,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(short(v), style: const TextStyle(fontSize: 10, color: ParkColors.muted)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(label(points[i]),
                        style: TextStyle(fontSize: 10, fontWeight: highlight(points[i]) ? FontWeight.w800 : FontWeight.w500,
                            color: highlight(points[i]) ? ParkColors.navy : ParkColors.muted)),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => ParkColors.navyDark,
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${label(points[group.x])}\n${AnimatedCount.group(points[group.x].total)} F\n'
                '${points[group.x].count} entrées',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ),
          barGroups: [
            for (final (i, pt) in points.indexed)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: pt.total * t,
                  width: points.length > 20 ? 7 : 14,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: highlight(pt)
                        ? const [Color(0xFFE59A00), ParkColors.amber]
                        : const [ParkColors.navy, ParkColors.navyLight],
                  ),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

class _VehicleBreakdown extends StatelessWidget {
  const _VehicleBreakdown({required this.data});
  final Map<VehicleType, RevenuePoint> data;

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold<int>(0, (a, p) => a + p.total);
    if (total == 0) {
      return const Card(child: EmptyState(icon: Icons.pie_chart_outline, title: 'Pas encore de recettes'));
    }
    final sorted = data.entries.toList()..sort((a, b) => b.value.total.compareTo(a.value.total));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          for (final (i, e) in sorted.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                VehicleAvatar(e.key, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(e.key.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('${AnimatedCount.group(e.value.total)} F · ${e.value.count}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: e.value.total / total),
                        duration: Duration(milliseconds: 700 + i * 120),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, _) => LinearProgressIndicator(
                          value: v,
                          minHeight: 7,
                          backgroundColor: ParkColors.surface,
                          color: vehicleColor(e.key),
                        ),
                      ),
                    ),
                  ]),
                ),
              ]),
            ).animate().fadeIn(delay: (i * 80).ms),
        ]),
      ),
    );
  }
}
