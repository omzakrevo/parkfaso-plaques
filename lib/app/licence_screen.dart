// PARKFASO — Saisie / scan d'une licence.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/licence.dart';
import 'app_controller.dart';
import 'parkfaso_theme.dart';

/// Carte d'état de la licence + bouton pour en saisir une.
class LicenceCard extends StatelessWidget {
  const LicenceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final st = app.licence;
    final ok = st.status == LicenceStatus.active;
    final trial = st.status == LicenceStatus.trial;
    final color = ok ? ParkColors.green : (trial ? ParkColors.warn : ParkColors.red);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ok ? Icons.verified : (trial ? Icons.hourglass_bottom : Icons.lock_outline), color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(st.describe(app.clock()),
                  key: const Key('licence-status'), style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            ),
          ]),
          if (ok || trial)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 34),
              child: Text('Parkings autorisés : ${st.maxParkings} · utilisés : ${app.parkings.length}',
                  style: const TextStyle(color: ParkColors.muted, fontSize: 12.5)),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('enter-licence'),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const LicenceEntryScreen())),
              icon: const Icon(Icons.key, size: 18),
              label: Text(ok ? 'Changer de licence' : 'Saisir une licence'),
            ),
          ),
        ]),
      ),
    );
  }
}

class LicenceEntryScreen extends StatefulWidget {
  const LicenceEntryScreen({super.key, this.popOnSuccess = true});
  final bool popOnSuccess;

  @override
  State<LicenceEntryScreen> createState() => _LicenceEntryScreenState();
}

class _LicenceEntryScreenState extends State<LicenceEntryScreen> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _activate(String key) async {
    if (key.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = AppScope.read(context);
    try {
      await app.activateLicence(key);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: ParkColors.green,
        content: Text('Licence activée : ${app.licence.licence!.client}'),
      ));
      if (widget.popOnSuccess) Navigator.of(context).pop();
    } on LicenceException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _QrGrab()));
    if (code != null) {
      _ctrl.text = code;
      await _activate(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Licence')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Collez la licence reçue d\'OMZAKREVO INFORMATIQUE (WhatsApp, SMS…) '
            'ou scannez son QR code.', style: TextStyle(color: ParkColors.muted)),
        const SizedBox(height: 14),
        TextField(
          key: const Key('licence-field'),
          controller: _ctrl,
          minLines: 3,
          maxLines: 5,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
          decoration: InputDecoration(hintText: 'PKF1.…', errorText: _error, errorMaxLines: 3),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              label: const Text('Scanner'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              key: const Key('activate-licence'),
              onPressed: _busy ? null : () => _activate(_ctrl.text),
              icon: _busy
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Icon(Icons.lock_open, size: 20),
              label: const Text('Activer'),
            ),
          ),
        ]),
        const SizedBox(height: 22),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text('La licence est vérifiée sur le téléphone, même sans Internet. '
                'Une licence modifiée ou révoquée est refusée.',
                style: TextStyle(color: ParkColors.muted, fontSize: 13)),
          ),
        ).animate().fadeIn(delay: 200.ms),
      ]),
    );
  }
}

/// Lecture d'un QR (licence).
class _QrGrab extends StatefulWidget {
  const _QrGrab();

  @override
  State<_QrGrab> createState() => _QrGrabState();
}

class _QrGrabState extends State<_QrGrab> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('QR de la licence'), backgroundColor: Colors.black,
            foregroundColor: Colors.white),
        body: MobileScanner(
          onDetect: (c) {
            final v = c.barcodes.firstOrNull?.rawValue;
            if (v != null && !_done && v.startsWith('PKF1.')) {
              _done = true;
              Navigator.of(context).pop(v);
            }
          },
        ),
      );
}
