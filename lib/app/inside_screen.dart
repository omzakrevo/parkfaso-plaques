// PARKFASO — Véhicules encore au parking (pas encore sortis).

import 'package:flutter/material.dart';

import '../plaque/plate_models.dart';
import 'app_controller.dart';
import 'home_screen.dart';
import 'parkfaso_theme.dart';
import 'session_sheet.dart';

enum InsideSort { oldest, newest, plate }

class InsideScreen extends StatefulWidget {
  const InsideScreen({super.key});

  @override
  State<InsideScreen> createState() => _InsideScreenState();
}

class _InsideScreenState extends State<InsideScreen> {
  VehicleType? _type;
  InsideSort _sort = InsideSort.oldest;
  String _query = '';
  List<ParkingSession>? _list;
  int _rev = -1;

  Future<void> _load(AppController app) async {
    final l = await app.sessions!.inside(type: _type);
    if (mounted) setState(() => _list = l);
  }

  List<ParkingSession> _visible() {
    final q = _query.toUpperCase().replaceAll(' ', '');
    final l = (_list ?? const <ParkingSession>[])
        .where((s) => q.isEmpty ||
            s.licensePlate.replaceAll(' ', '').contains(q) ||
            s.ticketBase.contains(q))
        .toList();
    switch (_sort) {
      case InsideSort.oldest:
        l.sort((a, b) => a.enteredAt.compareTo(b.enteredAt));
      case InsideSort.newest:
        l.sort((a, b) => b.enteredAt.compareTo(a.enteredAt));
      case InsideSort.plate:
        l.sort((a, b) => a.licensePlate.compareTo(b.licensePlate));
    }
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (_rev != app.revision) {
      _rev = app.revision;
      _load(app);
    }
    final items = _visible();
    final now = app.clock();
    return Scaffold(
      appBar: AppBar(
        title: Text('Au parking · ${_list?.length ?? 0}'),
        actions: [
          PopupMenuButton<InsideSort>(
            tooltip: 'Trier',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: InsideSort.oldest, child: Text('Les plus anciens d\'abord')),
              PopupMenuItem(value: InsideSort.newest, child: Text('Les plus récents d\'abord')),
              PopupMenuItem(value: InsideSort.plate, child: Text('Par plaque')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(app),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          TextField(
            key: const Key('inside-search'),
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Plaque ou n° de ticket',
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              ChoiceChip(
                label: const Text('Tous'),
                selected: _type == null,
                onSelected: (_) {
                  setState(() => _type = null);
                  _load(app);
                },
              ),
              for (final t in app.parking!.enabledVehicles)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    avatar: Icon(t.icon, size: 16, color: _type == t ? Colors.white : vehicleColor(t)),
                    label: Text(t.label),
                    selected: _type == t,
                    selectedColor: vehicleColor(t),
                    labelStyle: TextStyle(color: _type == t ? Colors.white : null, fontWeight: FontWeight.w700),
                    onSelected: (_) {
                      setState(() => _type = t);
                      _load(app);
                    },
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 14),
          if (_list == null)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else if (items.isEmpty)
            const EmptyState(icon: Icons.local_parking, title: 'Aucun véhicule au parking',
                subtitle: 'Tous les véhicules sont sortis.')
          else
            Card(
              child: Column(children: [
                for (final (i, s) in items.indexed) ...[
                  if (i > 0) const Divider(indent: 64),
                  SessionTile(
                    key: ValueKey(s.id),
                    session: s,
                    now: now,
                    showDate: now.difference(s.enteredAt).inHours >= 20,
                    onTap: () => showSessionSheet(context, s),
                  ).entrance(i),
                ],
              ]),
            ),
        ]),
      ),
    );
  }
}
