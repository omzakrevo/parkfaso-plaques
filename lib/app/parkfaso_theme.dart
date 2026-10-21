// PARKFASO — Thème compact : boutons de 44–48 px, marges réduites, typographie
// sobre. Lisible en plein soleil, rapide à utiliser d'une main.

import 'package:flutter/material.dart';

class ParkColors {
  static const navy = Color(0xFF0E3A5B);
  static const green = Color(0xFF1E8E4E);
  static const amber = Color(0xFFF2A900);
  static const red = Color(0xFFC62828);
  static const warn = Color(0xFFB45309);
  static const surface = Color(0xFFF6F7F9);
  static const line = Color(0xFFE2E5EA);
  static const muted = Color(0xFF6B7280);
}

ThemeData buildParkTheme({String? fontFamily}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: ParkColors.navy,
    primary: ParkColors.navy,
    surface: Colors.white,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: ParkColors.surface,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: ParkColors.navy,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: ParkColors.navy),
      toolbarHeight: 52,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: ParkColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        shape: shape,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: shape,
        side: const BorderSide(color: ParkColors.line),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: ParkColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: ParkColors.line)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(0, 42),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        selectedBackgroundColor: ParkColors.navy,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: ParkColors.line),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: const DividerThemeData(color: ParkColors.line, space: 1),
  );
}

/// Petit titre de section.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
                    letterSpacing: 0.6, color: ParkColors.muted)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Plaque affichée comme une vraie plaque (cadre noir, fond blanc).
class PlateBadge extends StatelessWidget {
  const PlateBadge(this.plate, {super.key, this.size = 22});
  final String plate;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: size * 0.6, vertical: size * 0.22),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black87, width: 2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(plate,
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: 1.5,
                color: Colors.black)),
      );
}
