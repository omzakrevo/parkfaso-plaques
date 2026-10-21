// PARKFASO — Réglages. L'administrateur gère tarifs, parkings, comptes,
// synchronisation et licence ; le gardien n'a accès qu'à l'imprimante et à son PIN.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/auth.dart';
import '../core/github_sync.dart';
import '../core/models.dart';
import '../plaque/plate_models.dart';
import '../tickets/printer_settings_screen.dart';
import 'app_controller.dart';
import 'licence_screen.dart';
import 'login_screen.dart';
import 'parkfaso_theme.dart';
import 'remote_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final u = app.auth.user;
    // Pendant l'animation de déconnexion, l'écran est encore affiché un instant.
    if (u == null || app.parking == null) return const Scaffold();
    void open(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppScope(controller: app, child: w)));
    Widget tile(int i, IconData icon, Color color, String title, String sub, VoidCallback onTap, {Key? key}) =>
        ListTile(
          key: key,
          onTap: onTap,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
        ).entrance(i);
    return Scaffold(
      appBar: AppBar(title: Text(app.isAdmin ? 'Réglages' : 'Plus')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: u.isAdmin ? ParkColors.amber : ParkColors.navy,
              child: Text(u.name.characters.first.toUpperCase(),
                  style: TextStyle(color: u.isAdmin ? ParkColors.navy : Colors.white, fontWeight: FontWeight.w800)),
            ),
            title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${u.role.label} · ${app.parking?.name ?? ''}'),
            trailing: TextButton.icon(
              key: const Key('settings-logout'),
              onPressed: app.auth.logout,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sortir'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (app.isAdmin) ...[
          const SectionLabel('Parking'),
          Card(child: Column(children: [
            tile(0, Icons.sell_outlined, const Color(0xFFF97316), 'Tarifs et options',
                '${app.parking!.name} · moto ${app.parking!.prices[VehicleType.moto] ?? 0} F',
                () => open(ParkingEditScreen(parking: app.parking!)), key: const Key('open-prices')),
            const Divider(indent: 64),
            tile(1, Icons.local_parking, ParkColors.navy, 'Mes parkings',
                '${app.parkings.length} / ${app.licence.maxParkings} autorisé(s)',
                () => open(const ParkingsScreen()), key: const Key('open-parkings')),
            const Divider(indent: 64),
            tile(2, Icons.group_outlined, const Color(0xFF7C3AED), 'Comptes',
                'Gardiens et administrateurs', () => open(const UsersScreen()), key: const Key('open-users')),
          ])),
          const SizedBox(height: 16),
          const SectionLabel('Suivi'),
          Card(child: Column(children: [
            tile(3, Icons.cloud_sync_outlined, const Color(0xFF0891B2), 'Synchronisation GitHub',
                app.sync.state == SyncState.off ? 'Non configurée' : 'Dernière : ${ago(app.sync.lastSync, app.clock())}',
                () => open(const SyncSettingsScreen()), key: const Key('open-sync')),
            const Divider(indent: 64),
            tile(4, Icons.public, ParkColors.green, 'Parkings à distance', 'Recettes et présents de chaque parking',
                () => open(const RemoteScreen())),
          ])),
          const SizedBox(height: 16),
        ],
        const SectionLabel('Ce téléphone'),
        Card(child: Column(children: [
          tile(5, Icons.print_outlined, ParkColors.navy, 'Imprimante',
              app.printer.device?.name ?? 'Aucune imprimante choisie',
              () => open(PrinterSettingsScreen(printer: app.printer, parkingName: app.parking?.name ?? ''))),
          const Divider(indent: 64),
          tile(6, Icons.pin_outlined, ParkColors.warn, 'Changer mon code PIN', 'Code à 4 chiffres',
              () => open(ChangePinScreen(user: u))),
          if (app.isAdmin) ...[
            const Divider(indent: 64),
            tile(7, Icons.smartphone, ParkColors.muted, 'Lettre du téléphone : ${app.deviceLetter}',
                'Distingue les tickets si plusieurs téléphones par parking', () => _pickLetter(context, app)),
          ],
        ])),
        if (app.isAdmin) ...[
          const SizedBox(height: 16),
          const SectionLabel('Licence'),
          const LicenceCard(),
        ],
        const SizedBox(height: 20),
        const Center(
          child: Text('PARKFASO · OMZAKREVO INFORMATIQUE\nToujours une solution !',
              textAlign: TextAlign.center, style: TextStyle(color: ParkColors.muted, fontSize: 12)),
        ),
      ]),
    );
  }

  Future<void> _pickLetter(BuildContext context, AppController app) async {
    final l = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Lettre de ce téléphone'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in 'ABCDEFGH'.split(''))
                ChoiceChip(
                  label: Text(c),
                  selected: c == app.deviceLetter,
                  labelStyle: TextStyle(color: c == app.deviceLetter ? Colors.white : null),
                  onSelected: (_) => Navigator.pop(ctx, c),
                ),
            ]),
          ),
        ],
      ),
    );
    if (l != null) await app.setDeviceLetter(l);
  }
}

/// Tarifs et options d'un parking (administrateur).
class ParkingEditScreen extends StatefulWidget {
  const ParkingEditScreen({super.key, required this.parking});
  final Parking parking;

  @override
  State<ParkingEditScreen> createState() => _ParkingEditScreenState();
}

class _ParkingEditScreenState extends State<ParkingEditScreen> {
  late final _name = TextEditingController(text: widget.parking.name);
  late final _prices = {
    for (final t in VehicleType.values) t: TextEditingController(text: '${widget.parking.prices[t] ?? 0}'),
  };
  late final _helmet = TextEditingController(text: '${widget.parking.helmetPrice}');
  late bool _plateRequired = !widget.parking.allowEmptyPlate;
  late final Set<VehicleType> _enabled = widget.parking.enabledVehicles.toSet();
  bool _saving = false;

  Future<void> _save() async {
    final app = AppScope.read(context);
    if (_name.text.trim().isEmpty || _enabled.isEmpty) return;
    setState(() => _saving = true);
    await app.saveParking(widget.parking.copyWith(
      name: _name.text.trim(),
      prices: {for (final e in _prices.entries) e.key: int.tryParse(e.value.text) ?? 0},
      helmetPrice: int.tryParse(_helmet.text) ?? 0,
      allowEmptyPlate: !_plateRequired,
      enabledVehicles: [for (final t in VehicleType.values) if (_enabled.contains(t)) t],
    ));
    await app.sync.pushAll().catchError((_) {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: ParkColors.green, content: Text('Tarifs enregistrés')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Scaffold(
      appBar: AppBar(title: const Text('Tarifs et options')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SectionLabel('Nom du parking'),
        TextField(controller: _name, textCapitalization: TextCapitalization.words),
        const SizedBox(height: 18),
        const SectionLabel('Prix du ticket (FCFA)'),
        Card(
          child: Column(children: [
            for (final (i, t) in VehicleType.values.indexed) ...[
              if (i > 0) const Divider(indent: 64),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  VehicleAvatar(t, size: 38),
                  const SizedBox(width: 12),
                  Expanded(child: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700))),
                  Switch(
                    value: _enabled.contains(t),
                    onChanged: (v) => setState(() => v ? _enabled.add(t) : _enabled.remove(t)),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      key: Key('price-${t.name}'),
                      controller: _prices[t],
                      enabled: _enabled.contains(t),
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      decoration: const InputDecoration(suffixText: ' F'),
                    ),
                  ),
                ]),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 18),
        const SectionLabel('Options'),
        Card(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                const Expanded(child: Text('Prix par casque', style: TextStyle(fontWeight: FontWeight.w700))),
                SizedBox(
                  width: 96,
                  child: TextField(
                    key: const Key('price-helmet'),
                    controller: _helmet,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(suffixText: ' F'),
                  ),
                ),
              ]),
            ),
            const Divider(),
            SwitchListTile(
              value: _plateRequired,
              onChanged: (v) => setState(() => _plateRequired = v),
              title: const Text('Immatriculation obligatoire', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Sinon, le gardien peut la laisser vide'),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          key: const Key('save-prices'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Enregistrer'),
        ),
      ]),
    );
  }
}

/// Liste des parkings (mode SaaS).
class ParkingsScreen extends StatelessWidget {
  const ParkingsScreen({super.key});

  Future<void> _add(BuildContext context, AppController app) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau parking'),
        content: TextField(
          key: const Key('new-parking-name'),
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Ex. Parking du Marché'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(key: const Key('new-parking-ok'), onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Créer')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await app.createParking(name);
    } on StateError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: ParkColors.red, content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes parkings')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-parking'),
        onPressed: () => _add(context, app),
        backgroundColor: ParkColors.amber,
        foregroundColor: ParkColors.navyDark,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 90), children: [
        Text('Licence : ${app.parkings.length} / ${app.licence.maxParkings} parking(s).',
            style: const TextStyle(color: ParkColors.muted)),
        const SizedBox(height: 12),
        for (final (i, p) in app.parkings.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.local_parking, color: ParkColors.navy, size: 30),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('Code ${p.code} · moto ${p.prices[VehicleType.moto] ?? 0} F · '
                    'voiture ${p.prices[VehicleType.voiture] ?? 0} F'),
                trailing: p.id == app.parking?.id
                    ? const Chip(label: Text('Actif'), backgroundColor: Color(0x2216A34A))
                    : TextButton(onPressed: () => app.switchParking(p), child: const Text('Utiliser')),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AppScope(controller: app, child: ParkingEditScreen(parking: p)))),
              ),
            ).entrance(i),
          ),
      ]),
    );
  }
}

/// Comptes gardiens et administrateurs.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<AppUser>? _users;

  Future<void> _load() async {
    final u = await AppScope.read(context).store.users();
    if (mounted) setState(() => _users = u);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _add(AppController app) async {
    final name = TextEditingController();
    final pin = TextEditingController();
    var role = UserRole.gardien;
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Nouveau compte'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const Key('user-name'), controller: name, autofocus: true,
                textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'Nom')),
            const SizedBox(height: 10),
            TextField(
              key: const Key('user-pin'),
              controller: pin,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(hintText: 'Code PIN (4 chiffres)', counterText: ''),
            ),
            const SizedBox(height: 10),
            SegmentedButton<UserRole>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: UserRole.gardien, label: Text('Gardien')),
                ButtonSegment(value: UserRole.admin, label: Text('Admin')),
              ],
              selected: {role},
              onSelectionChanged: (v) => set(() => role = v.first),
            ),
            if (error != null)
              Padding(padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: const TextStyle(color: ParkColors.red))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              key: const Key('user-ok'),
              onPressed: () async {
                try {
                  await app.auth.createUser(name.text, pin.text, role);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on ArgumentError catch (e) {
                  set(() => error = '${e.message}');
                }
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await _load();
  }

  Future<void> _remove(AppController app, AppUser u) async {
    final admins = _users!.where((x) => x.isAdmin).length;
    if (u.isAdmin && admins <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: ParkColors.red, content: Text('Il faut garder au moins un administrateur.')));
      return;
    }
    await app.store.deleteUser(u.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Comptes')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-user'),
        onPressed: () => _add(app),
        backgroundColor: ParkColors.amber,
        foregroundColor: ParkColors.navyDark,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Ajouter', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _users == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 90), children: [
              for (final (i, u) in _users!.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: u.isAdmin ? ParkColors.amber : ParkColors.navy.withValues(alpha: 0.1),
                        child: Text(u.name.characters.first.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w800, color: ParkColors.navy)),
                      ),
                      title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(u.role.label),
                      trailing: PopupMenuButton<String>(
                        onSelected: (k) => k == 'pin'
                            ? Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => AppScope(controller: app, child: ChangePinScreen(user: u))))
                            : _remove(app, u),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'pin', child: Text('Changer le PIN')),
                          PopupMenuItem(value: 'del', child: Text('Désactiver')),
                        ],
                      ),
                    ),
                  ).entrance(i),
                ),
            ]),
    );
  }
}

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key, required this.user});
  final AppUser user;

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  String? _first;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      backgroundColor: ParkColors.navy,
      appBar: AppBar(
        backgroundColor: ParkColors.navy,
        foregroundColor: Colors.white,
        title: Text('PIN de ${widget.user.name}', style: const TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text(_first == null ? 'Nouveau code' : 'Confirmez le code',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            PinPad(
              key: ValueKey(_first == null),
              error: _error,
              onComplete: (pin) async {
                if (_first == null) {
                  setState(() {
                    _first = pin;
                    _error = null;
                  });
                  return true;
                }
                if (pin != _first) {
                  setState(() {
                    _first = null;
                    _error = 'Codes différents';
                  });
                  return false;
                }
                await app.auth.changePin(widget.user, pin);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(backgroundColor: ParkColors.green, content: Text('Code PIN modifié')));
                  Navigator.of(context).pop();
                }
                return true;
              },
            ),
          ]),
        ),
      ),
    );
  }
}

/// Réglage de la synchronisation GitHub.
class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _repo = TextEditingController();
  final _token = TextEditingController();
  bool _busy = false;
  String? _msg;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).sync.config().then((c) {
      if (c != null && mounted) {
        _repo.text = c.repo;
        _token.text = c.token;
        setState(() {});
      }
    });
  }

  Future<void> _save(AppController app) async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final c = SyncConfig(repo: _repo.text.trim(), token: _token.text.trim());
      if (!c.isValid) throw const SyncException('Indiquez « propriétaire/dépôt » et un jeton GitHub complet.');
      await app.sync.saveConfig(c);
      await app.sync.pushAll();
      setState(() {
        _ok = true;
        _msg = 'Connexion réussie, données publiées.';
      });
    } catch (e) {
      setState(() {
        _ok = false;
        _msg = '$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Synchronisation GitHub')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Chaque téléphone publie ses entrées dans un dépôt GitHub PRIVÉ, toutes les 10 minutes '
              'et après chaque entrée. Le propriétaire voit alors tous ses parkings à distance.\n\n'
              '1. Créez un dépôt privé (ex. parkfaso-data).\n'
              '2. Créez un jeton « Fine-grained » limité à ce dépôt, permission « Contents : Read and write ».\n'
              '3. Saisissez-les ci-dessous sur chaque téléphone.',
              style: TextStyle(fontSize: 13.5, height: 1.35),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SectionLabel('Dépôt'),
        TextField(key: const Key('sync-repo'), controller: _repo,
            decoration: const InputDecoration(hintText: 'omzakrevo/parkfaso-data')),
        const SizedBox(height: 12),
        const SectionLabel('Jeton d\'accès'),
        TextField(key: const Key('sync-token'), controller: _token, obscureText: true,
            decoration: const InputDecoration(hintText: 'github_pat_…')),
        const SizedBox(height: 16),
        if (_msg != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_msg!, style: TextStyle(color: _ok ? ParkColors.green : ParkColors.red,
                fontWeight: FontWeight.w700)),
          ),
        FilledButton.icon(
          key: const Key('sync-save'),
          onPressed: _busy ? null : () => _save(app),
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : const Icon(Icons.cloud_upload_outlined),
          label: const Text('Tester et synchroniser'),
        ),
        const SizedBox(height: 10),
        if (app.sync.state != SyncState.off)
          TextButton(
            onPressed: () async {
              await app.sync.saveConfig(null);
              _repo.clear();
              _token.clear();
              setState(() => _msg = 'Synchronisation désactivée.');
            },
            child: const Text('Désactiver la synchronisation'),
          ),
        const SizedBox(height: 8),
        ListenableBuilder(
          listenable: app.sync,
          builder: (context, _) => Text(
            app.sync.state == SyncState.off
                ? 'Non configurée'
                : 'Dernière synchronisation : ${ago(app.sync.lastSync, app.clock())}'
                    '${app.sync.lastError != null ? '\n${app.sync.lastError}' : ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: ParkColors.muted),
          ),
        ),
      ]),
    );
  }
}

/// Vérifie un PIN (pour usage futur : actions sensibles).
Future<bool> confirmAdminPin(BuildContext context, AuthService auth) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: ParkColors.navy,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: PinPad(onComplete: (pin) async {
        final good = await auth.checkAdminPin(pin);
        if (good && ctx.mounted) Navigator.pop(ctx, true);
        return good;
      }),
    ),
  );
  return ok ?? false;
}
