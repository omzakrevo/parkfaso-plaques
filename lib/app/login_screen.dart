// PARKFASO — Connexion : choix du compte puis code PIN.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/models.dart';
import 'app_controller.dart';
import 'parkfaso_theme.dart';

/// Pavé numérique pour saisir un PIN de 4 à 6 chiffres.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onComplete,
    this.length = 4,
    this.error,
    this.dark = true,
    this.minLength = 4,
  });

  /// Retourne true si le PIN est accepté (sinon le pavé tremble et se vide).
  final Future<bool> Function(String pin) onComplete;
  final int length;
  final int minLength;
  final String? error;
  final bool dark;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  int _shake = 0;
  bool _busy = false;

  Future<void> _tap(String d) async {
    if (_busy || _pin.length >= widget.length) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    if (_pin.length == widget.length) await _submit();
  }

  Future<void> _submit() async {
    if (_pin.length < widget.minLength) return;
    setState(() => _busy = true);
    final ok = await widget.onComplete(_pin);
    if (!mounted) return;
    if (!ok) {
      HapticFeedback.heavyImpact();
      setState(() {
        _shake++;
        _pin = '';
      });
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.dark ? Colors.white : ParkColors.navy;
    Widget key(String label, {VoidCallback? onTap, IconData? icon, Key? k}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: PressableScale(
          onTap: onTap,
          child: Container(
            key: k,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.dark ? Colors.white.withValues(alpha: 0.10) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: widget.dark ? Colors.white12 : ParkColors.line),
            ),
            child: icon != null
                ? Icon(icon, color: fg)
                : Text(
                    label,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: fg),
                  ),
          ),
        ),
      ),
    );
    // Clavier physique (PC) : chiffres, Retour arrière, Entrée.
    return Focus(
      autofocus: true,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final ch = e.character;
        if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
          _tap(ch);
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.backspace && _pin.isNotEmpty) {
          setState(() => _pin = _pin.substring(0, _pin.length - 1));
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _submit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? ParkColors.amber : Colors.transparent,
                    border: Border.all(color: i < _pin.length ? ParkColors.amber : fg.withValues(alpha: 0.4), width: 2),
                  ),
                ),
            ],
          ).animate(key: ValueKey(_shake), target: _shake > 0 ? 1 : 0).shakeX(hz: 6, amount: 8, duration: 400.ms),
          SizedBox(
            height: 26,
            child: widget.error == null
                ? null
                : Center(
                    child: Text(
                      widget.error!,
                      style: const TextStyle(color: Color(0xFFFCA5A5), fontWeight: FontWeight.w600),
                    ),
                  ),
          ),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(
              children: [for (final d in row) key(d, onTap: () => _tap(d), k: Key('pin-$d'))],
            ),
          Row(
            children: [
              key(
                '',
                icon: Icons.backspace_outlined,
                onTap: () {
                  if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
                },
              ),
              key('0', onTap: () => _tap('0'), k: const Key('pin-0')),
              key(
                '',
                icon: Icons.check_rounded,
                onTap: _pin.length >= widget.minLength ? _submit : null,
                k: const Key('pin-ok'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<AppUser>? _users;
  AppUser? _selected;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _users ??= null;
    AppScope.read(context).store.users().then((u) {
      if (mounted) setState(() => _users = u);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: ParkColors.headerGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset(
                        'assets/logo/parkfaso_logo.png',
                        width: 72,
                        height: 72,
                        errorBuilder: (_, _, _) => const SizedBox(width: 72, height: 72),
                      ),
                    ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
                    const SizedBox(height: 10),
                    Text(
                      app.parking?.name ?? 'PARKFASO',
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 22),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _selected == null ? _userList() : _pinStep(app),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _userList() {
    final users = _users;
    if (users == null) return const CircularProgressIndicator(color: Colors.white);
    return Column(
      key: const ValueKey('users'),
      children: [
        const Text(
          'Qui êtes-vous ?',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < users.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PressableScale(
              onTap: () => setState(() {
                _selected = users[i];
                _error = null;
              }),
              child: Container(
                key: Key('user-${users[i].name}'),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: users[i].isAdmin ? ParkColors.amber : Colors.white24,
                      child: Text(
                        users[i].name.characters.first.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: users[i].isAdmin ? ParkColors.navy : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        users[i].name,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(users[i].role.label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right, color: Colors.white54),
                  ],
                ),
              ),
            ).entrance(i),
          ),
      ],
    );
  }

  Widget _pinStep(AppController app) {
    final u = _selected!;
    final lock = app.auth.lockRemaining;
    return Column(
      key: const ValueKey('pin'),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () => setState(() => _selected = null),
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
            ),
            Text(
              u.name,
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 8),
        PinPad(
          error: lock != null ? 'Trop d\'essais : patientez ${lock.inSeconds + 1} s' : _error,
          onComplete: (pin) async {
            final ok = await app.auth.login(u, pin);
            if (!ok && mounted) setState(() => _error = 'Code incorrect');
            return ok;
          },
        ),
      ],
    );
  }
}
