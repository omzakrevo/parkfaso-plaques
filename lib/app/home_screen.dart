// PARKFASO — Accueil : chiffres du jour, nouvelle entrée, scan de sortie.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/github_sync.dart';
import '../core/licence.dart';
import '../core/models.dart';
import '../plaque/plate_models.dart';
import '../plaque/vehicle_entry_screen.dart';
import '../tickets/printer_settings_screen.dart';
import '../tickets/ticket_scan_screen.dart';
import '../tickets/tickets.dart';
import 'app_controller.dart';
import 'licence_screen.dart';
import 'parkfaso_theme.dart';
import 'session_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenTab});

  /// Ouvre un autre onglet (ex. « Présents »).
  final ValueChanged<int>? onOpenTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ParkingSession> _recent = const [];
  int _rev = -1;

  Future<void> _loadRecent(AppController app) async {
    final s = app.sessions;
    if (s == null) return;
    final now = app.clock();
    final list = await s.history(
        HistoryFilter(from: now.subtract(const Duration(days: 2)), to: HistoryFilter.dayEnd(now)),
        limit: 5);
    if (mounted) setState(() => _recent = list);
  }

  bool _guardLicence(AppController app) {
    if (app.licence.canOperate) return true;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_outline, color: ParkColors.red),
        title: const Text('Licence requise'),
        content: Text('${app.licence.describe(app.clock())}.\n'
            'Contactez OMZAKREVO INFORMATIQUE pour activer votre licence.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LicenceEntryScreen()));
            },
            child: const Text('Saisir la licence'),
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _openEntry(AppController app, VehicleType type) async {
    if (!_guardLicence(app)) return;
    final p = app.parking!;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VehicleEntryScreen(
        vehicleType: type,
        settings: p.toSettings(paper: app.printer.paper),
        ocr: app.ocr,
        repository: app.sessions!,
        printer: app.ticketPrinter,
        photoStore: app.photoStore,
        cameraFactory: app.cameraFactory,
        clock: app.clock,
      ),
    ));
    await app.changed();
  }

  Future<void> _openScan(AppController app) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TicketScanScreen(
        service: TicketScanService(app.sessions!, clock: app.clock),
        scannerBuilder: app.scannerBuilder,
      ),
    ));
    await app.changed();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (_rev != app.revision) {
      _rev = app.revision;
      _loadRecent(app);
    }
    final p = app.parking;
    if (p == null) return const SizedBox();
    return RefreshIndicator(
      onRefresh: () async {
        await app.refreshStats();
        await _loadRecent(app);
      },
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: _header(app, p)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          sliver: SliverList.list(children: [
            if (app.licence.status == LicenceStatus.trial)
              _banner(Icons.hourglass_bottom, ParkColors.warn, app.licence.describe(app.clock()),
                  'Activer', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LicenceEntryScreen()))),
            if (!app.licence.canOperate)
              _banner(Icons.lock_outline, ParkColors.red, app.licence.describe(app.clock()),
                  'Licence', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LicenceEntryScreen()))),
            ListenableBuilder(
              listenable: app.printer,
              builder: (context, _) => app.printer.isConfigured
                  ? const SizedBox.shrink()
                  : _banner(Icons.print_disabled_outlined, ParkColors.warn, 'Aucune imprimante choisie',
                      'Choisir', () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PrinterSettingsScreen(printer: app.printer, parkingName: p.name)))),
            ),
            const SectionLabel('Nouvelle entrée'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.45,
              children: [
                for (final (i, t) in p.enabledVehicles.indexed)
                  _VehicleTile(
                    type: t,
                    price: '${AnimatedCount.group(p.prices[t] ?? 0)} FCFA',
                    onTap: () => _openEntry(app, t),
                  ).entrance(i, baseMs: 60),
              ],
            ),
            const SizedBox(height: 14),
            PressableScale(
              onTap: () => _openScan(app),
              child: Container(
                key: const Key('open-scan'),
                height: 58,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFF6B91A), ParkColors.amber]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: ParkColors.amber.withValues(alpha: 0.35), blurRadius: 14,
                      offset: const Offset(0, 6))],
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.qr_code_scanner, color: ParkColors.navyDark),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text('Scanner un ticket · sortie', overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ParkColors.navyDark, fontWeight: FontWeight.w800, fontSize: 15.5)),
                  ),
                ]),
              ),
            ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2, end: 0, delay: 300.ms),
            const SizedBox(height: 22),
            SectionLabel('Dernières entrées',
                trailing: TextButton(
                  onPressed: () => widget.onOpenTab?.call(2),
                  child: const Text('Tout voir'),
                )),
            if (_recent.isEmpty)
              const EmptyState(icon: Icons.two_wheeler, title: 'Aucune entrée récente',
                  subtitle: 'Les véhicules enregistrés apparaîtront ici.')
            else
              Card(
                child: Column(children: [
                  for (final (i, s) in _recent.indexed) ...[
                    if (i > 0) const Divider(indent: 64),
                    SessionTile(session: s, now: app.clock(), onTap: () => showSessionSheet(context, s))
                        .entrance(i),
                  ],
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _header(AppController app, Parking p) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 10, 16, 18),
      decoration: const BoxDecoration(
        gradient: ParkColors.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset('assets/logo/parkfaso_logo.png', width: 38, height: 38,
                errorBuilder: (_, _, _) => const SizedBox(width: 38, height: 38)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              key: const Key('switch-parking'),
              onTap: app.isAdmin && app.parkings.length > 1 ? () => _pickParking(app) : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(p.name, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  if (app.isAdmin && app.parkings.length > 1)
                    const Icon(Icons.expand_more, color: Colors.white70),
                ]),
                Text('Bonjour ${app.auth.user?.name ?? ''} · ${app.auth.user?.role.label ?? ''}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              ]),
            ),
          ),
          _SyncDot(sync: app.sync),
          ListenableBuilder(
            listenable: app.printer,
            builder: (context, _) => IconButton(
              tooltip: 'Imprimante',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PrinterSettingsScreen(printer: app.printer, parkingName: p.name))),
              icon: IconTheme(
                data: const IconThemeData(color: Colors.white),
                child: PrinterStatusDot(state: app.printer.state),
              ),
            ),
          ),
          IconButton(
            key: const Key('logout'),
            tooltip: 'Changer d\'utilisateur',
            onPressed: app.auth.logout,
            icon: const Icon(Icons.logout, color: Colors.white),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: KpiTile(label: 'Présents', value: app.stats.inside, icon: Icons.local_parking,
              onDark: true)),
          const SizedBox(width: 8),
          Expanded(child: KpiTile(label: 'Entrées', value: app.stats.todayCount, icon: Icons.login,
              onDark: true)),
          const SizedBox(width: 8),
          Expanded(child: KpiTile(label: 'Recette', value: app.stats.todayTotal, icon: Icons.payments,
              onDark: true, money: true)),
        ]).animate().fadeIn(duration: 400.ms).slideY(begin: 0.15, end: 0),
      ]),
    );
  }

  Widget _banner(IconData icon, Color color, String text, String action, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Material(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13))),
                Text(action, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                Icon(Icons.chevron_right, color: color),
              ]),
            ),
          ),
        ),
      ).animate().fadeIn().slideX(begin: -0.05, end: 0);

  Future<void> _pickParking(AppController app) async {
    final p = await showModalBottomSheet<Parking>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Choisir le parking', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          for (final x in app.parkings)
            ListTile(
              leading: const Icon(Icons.local_parking, color: ParkColors.navy),
              title: Text(x.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: x.id == app.parking?.id ? const Icon(Icons.check_circle, color: ParkColors.green) : null,
              onTap: () => Navigator.pop(ctx, x),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (p != null) await app.switchParking(p);
  }
}

class _SyncDot extends StatelessWidget {
  const _SyncDot({required this.sync});
  final SyncService sync;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: sync,
        builder: (context, _) {
          if (sync.state == SyncState.off) return const SizedBox.shrink();
          final (icon, color) = switch (sync.state) {
            SyncState.syncing => (Icons.cloud_sync, ParkColors.amber),
            SyncState.error => (Icons.cloud_off, const Color(0xFFFCA5A5)),
            _ => (Icons.cloud_done, const Color(0xFF86EFAC)),
          };
          final icn = Icon(icon, color: color, size: 22);
          return Tooltip(
            message: sync.lastError ?? 'Synchronisé',
            child: sync.state == SyncState.syncing
                ? icn.animate(onPlay: (c) => c.repeat()).fade(begin: 0.4, end: 1, duration: 600.ms)
                : icn,
          );
        },
      );
}

class _VehicleTile extends StatelessWidget {
  const _VehicleTile({required this.type, required this.price, required this.onTap});

  final VehicleType type;
  final String price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = vehicleColor(type);
    return PressableScale(
      onTap: onTap,
      child: Container(
        key: Key('vehicle-${type.name}'),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ParkColors.line),
          boxShadow: [BoxShadow(color: c.withValues(alpha: 0.10), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Stack(children: [
          Positioned(
            right: -14,
            bottom: -18,
            child: Icon(type.icon, size: 92, color: c.withValues(alpha: 0.07)),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              VehicleAvatar(type, size: 42),
              const Spacer(),
              Text(type.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(price, style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Ligne d'un véhicule (listes : accueil, présents, historique).
class SessionTile extends StatelessWidget {
  const SessionTile({super.key, required this.session, required this.now, this.onTap, this.showDate = false});
  final ParkingSession session;
  final DateTime now;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final s = session;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: VehicleAvatar(s.vehicleType),
      title: Row(children: [
        if (s.hasPlate) PlateBadge(s.licensePlate, size: 13) else Text(s.vehicleType.label,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(s.ticketBase, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: ParkColors.muted, fontSize: 12)),
        ),
      ]),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${showDate ? formatDateTime(s.enteredAt) : 'Entrée ${formatTime(s.enteredAt)}'}'
          '${s.exitedAt != null ? ' → ${formatTime(s.exitedAt!)}' : ''} · ${formatDuration(s.stayAt(now))}',
          style: const TextStyle(fontSize: 12.5),
        ),
      ),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end,
          children: [
        Text('${AnimatedCount.group(s.total)} F', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        StatusPill(inside: s.isInside),
      ]),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.inside});
  final bool inside;

  @override
  Widget build(BuildContext context) {
    final c = inside ? ParkColors.green : ParkColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(inside ? 'Présent' : 'Sorti',
          style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}
