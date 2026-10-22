// PARKFASO — Capacités de l'appareil (téléphone Android / PC Windows).

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Caméra + ML Kit (lecture de plaque, scan QR) : Android / iOS uniquement.
bool get hasMobileCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// PC (Windows / Linux / macOS) : base SQLite « bureau », impression Windows,
/// douchette USB pour le scan des tickets.
bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
