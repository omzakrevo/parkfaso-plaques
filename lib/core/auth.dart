// PARKFASO — Comptes administrateur / gardien avec code PIN.
//
// Le PIN n'est jamais stocké : seul son empreinte SHA-256 salée l'est.
// Après 5 erreurs, la saisie est bloquée 30 secondes.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';
import 'park_store.dart';

String hashPin(String pin, String salt) =>
    sha256.convert(utf8.encode('parkfaso:$salt:$pin')).toString();

bool isValidPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

class AuthService extends ChangeNotifier {
  AuthService(this.store, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final ParkStore store;
  final DateTime Function() _clock;

  AppUser? _user;
  int _failures = 0;
  DateTime? _lockedUntil;

  AppUser? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;

  Duration? get lockRemaining {
    final l = _lockedUntil;
    if (l == null) return null;
    final rem = l.difference(_clock());
    return rem.isNegative ? null : rem;
  }

  Future<AppUser> createUser(String name, String pin, UserRole role) async {
    if (name.trim().isEmpty) throw ArgumentError('Nom obligatoire');
    if (!isValidPin(pin)) throw ArgumentError('Le PIN doit avoir 4 à 6 chiffres');
    final salt = randomId(12);
    final u = AppUser(id: randomId(), name: name.trim(), role: role, pinHash: hashPin(pin, salt), salt: salt);
    await store.saveUser(u);
    return u;
  }

  Future<void> changePin(AppUser u, String pin) async {
    if (!isValidPin(pin)) throw ArgumentError('Le PIN doit avoir 4 à 6 chiffres');
    final salt = randomId(12);
    await store.saveUser(AppUser(
        id: u.id, name: u.name, role: u.role, pinHash: hashPin(pin, salt), salt: salt, active: u.active));
  }

  /// Vérifie le PIN. Retourne true si la connexion réussit.
  Future<bool> login(AppUser u, String pin) async {
    if (lockRemaining != null) return false;
    if (hashPin(pin, u.salt) == u.pinHash) {
      _user = u;
      _failures = 0;
      notifyListeners();
      return true;
    }
    _failures++;
    if (_failures >= 5) {
      _lockedUntil = _clock().add(const Duration(seconds: 30));
      _failures = 0;
    }
    notifyListeners();
    return false;
  }

  /// Vérifie un PIN administrateur (pour une action protégée, sans changer d'utilisateur).
  Future<bool> checkAdminPin(String pin) async {
    for (final u in await store.users()) {
      if (u.isAdmin && hashPin(pin, u.salt) == u.pinHash) return true;
    }
    return false;
  }

  void logout() {
    _user = null;
    notifyListeners();
  }
}
