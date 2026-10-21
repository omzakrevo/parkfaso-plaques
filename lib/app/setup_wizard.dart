// PARKFASO — Premier démarrage : parking, administrateur, licence.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/licence.dart';
import '../core/models.dart';
import 'app_controller.dart';
import 'licence_screen.dart';
import 'login_screen.dart';
import 'parkfaso_theme.dart';

class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  int _step = 0;
  final _parking = TextEditingController();
  final _admin = TextEditingController();
  String? _firstPin;
  String? _error;
  bool _busy = false;

  Future<void> _finish() async {
    final app = AppScope.read(context);
    setState(() => _busy = true);
    try {
      if (app.parkings.isEmpty) await app.createParking(_parking.text);
      if (!await app.store.hasAdmin()) {
        final u = await app.auth.createUser(_admin.text, _firstPin!, UserRole.admin);
        await app.auth.login(u, _firstPin!);
      }
      await app.completeSetup();
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final steps = [_welcome(), _parkingStep(), _adminStep(), _pinStep(), _licenceStep(app)];
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: ParkColors.headerGradient),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(children: [
                for (var i = 0; i < steps.length; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i <= _step ? ParkColors.amber : Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                      position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(a), child: c),
                ),
                child: KeyedSubtree(key: ValueKey(_step), child: steps[_step]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _frame({required String title, String? subtitle, required List<Widget> children}) =>
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 14.5)),
          ],
          const SizedBox(height: 24),
          ...children,
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5), fontWeight: FontWeight.w600)),
            ),
        ]),
      );

  Widget _next(String label, VoidCallback? onTap, {Key? key}) => SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: key,
          style: FilledButton.styleFrom(backgroundColor: ParkColors.amber, foregroundColor: ParkColors.navyDark),
          onPressed: onTap,
          child: Text(label),
        ),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        fillColor: Colors.white,
      );

  Widget _welcome() => _frame(
        title: 'Bienvenue sur PARKFASO',
        subtitle: 'Gestion de parking : entrées, tickets, plaques, sorties et chiffre d\'affaires.',
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset('assets/logo/parkfaso_logo.png', width: 132, height: 132,
                  errorBuilder: (_, _, _) => const SizedBox(width: 132, height: 132)),
            ).animate().scale(duration: 600.ms, curve: Curves.elasticOut).fadeIn(),
          ),
          const SizedBox(height: 32),
          for (final (i, (icon, text)) in [
            (Icons.local_parking, 'Plusieurs parkings, suivis à distance'),
            (Icons.print, 'Tickets Bluetooth avec QR code'),
            (Icons.bar_chart, 'Historique, rapports, export PDF / Excel'),
          ].indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Icon(icon, color: ParkColors.amber),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
              ]),
            ).entrance(i + 3, baseMs: 90),
          const SizedBox(height: 24),
          _next('Commencer', () => setState(() => _step = 1), key: const Key('setup-start')),
        ],
      );

  Widget _parkingStep() => _frame(
        title: 'Votre parking',
        subtitle: 'Son nom apparaît sur les tickets. Vous pourrez en ajouter d\'autres.',
        children: [
          TextField(
            key: const Key('setup-parking'),
            controller: _parking,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: _dec('Ex. Parking Central'),
            onSubmitted: (_) => _parking.text.trim().isEmpty ? null : setState(() => _step = 2),
          ),
          const SizedBox(height: 20),
          _next('Continuer', () {
            if (_parking.text.trim().isEmpty) return setState(() => _error = 'Indiquez le nom du parking.');
            setState(() {
              _error = null;
              _step = 2;
            });
          }, key: const Key('setup-next-parking')),
        ],
      );

  Widget _adminStep() => _frame(
        title: 'Compte administrateur',
        subtitle: 'L\'administrateur gère les tarifs, les gardiens, les rapports et les parkings.',
        children: [
          TextField(
            key: const Key('setup-admin'),
            controller: _admin,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: _dec('Votre nom'),
          ),
          const SizedBox(height: 20),
          _next('Choisir mon code PIN', () {
            if (_admin.text.trim().isEmpty) return setState(() => _error = 'Indiquez votre nom.');
            setState(() {
              _error = null;
              _step = 3;
            });
          }, key: const Key('setup-next-admin')),
        ],
      );

  Widget _pinStep() => _frame(
        title: _firstPin == null ? 'Code PIN (4 chiffres)' : 'Confirmez le code',
        subtitle: 'Il sera demandé pour ouvrir l\'application et accéder aux réglages.',
        children: [
          PinPad(
            key: ValueKey(_firstPin == null),
            onComplete: (pin) async {
              if (_firstPin == null) {
                setState(() => _firstPin = pin);
                return true;
              }
              if (pin != _firstPin) {
                setState(() {
                  _firstPin = null;
                  _error = 'Les deux codes sont différents. Recommencez.';
                });
                return false;
              }
              setState(() {
                _error = null;
                _step = 4;
              });
              return true;
            },
          ),
        ],
      );

  Widget _licenceStep(AppController app) => _frame(
        title: 'Licence',
        subtitle: app.licence.status == LicenceStatus.active
            ? app.licence.describe(app.clock())
            : 'Activez votre licence, ou commencez l\'essai gratuit de $kTrialDays jours (1 parking).',
        children: [
          if (app.licence.status != LicenceStatus.active)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AppScope(controller: app, child: const LicenceEntryScreen()))),
                icon: const Icon(Icons.key),
                label: const Text('J\'ai une licence'),
              ),
            ),
          const SizedBox(height: 12),
          _next(
            _busy
                ? 'Préparation…'
                : app.licence.status == LicenceStatus.active
                    ? 'Terminer'
                    : 'Commencer l\'essai gratuit',
            _busy ? null : _finish,
            key: const Key('setup-finish'),
          ),
        ],
      );
}
