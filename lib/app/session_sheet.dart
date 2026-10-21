// PARKFASO — Fiche d'un véhicule : détails, sortie manuelle, réimpression.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../plaque/plate_models.dart';
import '../tickets/ticket_scan_screen.dart';
import '../tickets/tickets.dart';
import 'app_controller.dart';
import 'parkfaso_theme.dart';

Future<void> showSessionSheet(BuildContext context, ParkingSession s) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AppScope(controller: AppScope.read(context), child: _SessionSheet(session: s)),
    );

class _SessionSheet extends StatefulWidget {
  const _SessionSheet({required this.session});
  final ParkingSession session;

  @override
  State<_SessionSheet> createState() => _SessionSheetState();
}

class _SessionSheetState extends State<_SessionSheet> {
  late ParkingSession s = widget.session;
  bool _busy = false;

  Future<void> _exit(AppController app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Valider la sortie ?'),
        content: Text('Sans scanner le ticket ${s.ticketBase}. Vérifiez la plaque du véhicule.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Valider')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final now = app.clock();
    await app.sessions!.markExited(s.id!, now);
    await app.changed();
    if (!mounted) return;
    setState(() {
      s = s.copyWith(exitedAt: now, exitedBy: app.auth.user?.name);
      _busy = false;
    });
  }

  Future<void> _reprint(AppController app) async {
    setState(() => _busy = true);
    try {
      await app.ticketPrinter.printTickets([TicketBuilder(app.parking!.toSettings(paper: app.printer.paper)).buildClient(s)]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(backgroundColor: ParkColors.green, content: Text('Ticket client réimprimé')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(backgroundColor: ParkColors.red, content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final now = app.clock();
    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(width: 110, child: Text(l, style: const TextStyle(color: ParkColors.muted))),
            Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            VehicleAvatar(s.vehicleType, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.vehicleType.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                Text(s.ticketBase, style: const TextStyle(color: ParkColors.muted)),
              ]),
            ),
            if (s.hasPlate) PlateBadge(s.licensePlate, size: 17),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: ParkColors.surface, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              row('Entrée', '${formatDateTime(s.enteredAt)}${s.enteredBy != null ? ' · ${s.enteredBy}' : ''}'),
              row('Sortie', s.exitedAt == null
                  ? 'Encore au parking'
                  : '${formatDateTime(s.exitedAt!)}${s.exitedBy != null ? ' · ${s.exitedBy}' : ''}'),
              row('Durée', formatDuration(s.stayAt(now))),
              if (s.helmetCount > 0) row('Casques', '${s.helmetCount}'),
              row('Payé', '${s.total} FCFA'),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _reprint(app),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Réimprimer'),
              ),
            ),
            if (s.isInside) ...[
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  key: const Key('sheet-exit'),
                  style: FilledButton.styleFrom(backgroundColor: ParkColors.green),
                  onPressed: _busy ? null : () => _exit(app),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Valider la sortie'),
                ),
              ),
            ],
          ]),
          if (!s.isInside)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Row(children: [
                Icon(Icons.check_circle, color: ParkColors.green, size: 18),
                SizedBox(width: 6),
                Text('Sorti', style: TextStyle(color: ParkColors.green, fontWeight: FontWeight.w800)),
              ]),
            ).animate().fadeIn().scale(begin: const Offset(0.9, 0.9)),
        ]),
      ),
    );
  }
}
