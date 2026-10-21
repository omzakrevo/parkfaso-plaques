// PARKFASO — Système visuel : couleurs, typographie, composants et animations.
//
// Bleu nuit (confiance) + ambre (action / ticket), une couleur par type de
// véhicule, cartes blanches sur fond gris très clair, animations courtes
// (200–450 ms) pour guider l'œil sans ralentir le gardien.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../plaque/plate_models.dart';

class ParkColors {
  static const navy = Color(0xFF0E3A5B);
  static const navyLight = Color(0xFF1B5E8C);
  static const navyDark = Color(0xFF082338);
  static const green = Color(0xFF16A34A);
  static const amber = Color(0xFFF2A900);
  static const red = Color(0xFFDC2626);
  static const warn = Color(0xFFB45309);
  static const surface = Color(0xFFF3F5F9);
  static const line = Color(0xFFE3E7EE);
  static const muted = Color(0xFF6B7280);
  static const ink = Color(0xFF111827);

  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navyDark, navy, navyLight],
  );
}

/// Couleur propre à chaque type de véhicule (tuiles, pastilles, graphiques).
Color vehicleColor(VehicleType t) => switch (t) {
      VehicleType.moto => const Color(0xFFF97316),
      VehicleType.voiture => const Color(0xFF2563EB),
      VehicleType.tricycle => const Color(0xFF7C3AED),
      VehicleType.velo => const Color(0xFF059669),
    };

ThemeData buildParkTheme({String? fontFamily}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: ParkColors.navy,
    primary: ParkColors.navy,
    secondary: ParkColors.amber,
    surface: Colors.white,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: ParkColors.surface,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
    appBarTheme: const AppBarTheme(
      backgroundColor: ParkColors.surface,
      foregroundColor: ParkColors.navy,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ParkColors.navy),
      toolbarHeight: 54,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: ParkColors.line),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: Colors.white,
      indicatorColor: ParkColors.navy.withValues(alpha: 0.10),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 11.5,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
          color: s.contains(WidgetState.selected) ? ParkColors.navy : ParkColors.muted)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? ParkColors.navy : ParkColors.muted, size: 24)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: shape,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        shape: shape,
        side: const BorderSide(color: ParkColors.line),
        backgroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ParkColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ParkColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ParkColors.navy, width: 1.6)),
    ),
    chipTheme: ChipThemeData(
      side: const BorderSide(color: ParkColors.line),
      backgroundColor: Colors.white,
      selectedColor: ParkColors.navy,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      secondaryLabelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(0, 44),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        selectedBackgroundColor: ParkColors.navy,
        selectedForegroundColor: Colors.white,
        backgroundColor: Colors.white,
        side: const BorderSide(color: ParkColors.line),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: const DividerThemeData(color: ParkColors.line, space: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    ),
  );
}

/// Petit titre de section.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800,
                    letterSpacing: 0.8, color: ParkColors.muted)),
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
        padding: EdgeInsets.symmetric(horizontal: size * 0.55, vertical: size * 0.2),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black87, width: size > 16 ? 2 : 1.5),
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Text(plate,
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: 1.2,
                color: Colors.black, height: 1.1)),
      );
}

/// Pastille ronde colorée avec l'icône du véhicule.
class VehicleAvatar extends StatelessWidget {
  const VehicleAvatar(this.type, {super.key, this.size = 40});
  final VehicleType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = vehicleColor(type);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(type.icon, color: c, size: size * 0.56),
    );
  }
}

/// Nombre qui défile jusqu'à sa valeur (chiffres clés).
class AnimatedCount extends StatelessWidget {
  const AnimatedCount(this.value, {super.key, this.style, this.suffix = '', this.money = false});
  final int value;
  final TextStyle? style;
  final String suffix;
  final bool money;

  static String group(int v) {
    final s = v.abs().toString();
    final b = StringBuffer(v < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text('${money ? group(v.round()) : v.round()}$suffix', style: style),
      );
}

/// Carte de chiffre clé (sur fond clair ou sur le dégradé).
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, required this.icon,
      this.money = false, this.onDark = false, this.color});
  final String label;
  final int value;
  final IconData icon;
  final bool money;
  final bool onDark;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : ParkColors.ink;
    final accent = color ?? (onDark ? ParkColors.amber : ParkColors.navy);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.10) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: onDark ? Colors.white.withValues(alpha: 0.14) : ParkColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                    color: onDark ? Colors.white70 : ParkColors.muted)),
          ),
        ]),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AnimatedCount(value, money: money, suffix: money ? ' F' : '',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: fg, letterSpacing: -0.3)),
        ),
      ]),
    );
  }
}

/// Message « liste vide » illustré.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: ParkColors.navy.withValues(alpha: 0.06), shape: BoxShape.circle),
            child: Icon(icon, size: 36, color: ParkColors.navy.withValues(alpha: 0.5)),
          ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: ParkColors.muted)),
          ],
        ]),
      );
}

/// Effet d'apparition en cascade pour les éléments d'une liste.
extension ParkEntrance on Widget {
  Widget entrance(int index, {int baseMs = 40}) => animate()
      .fadeIn(duration: 320.ms, delay: (index.clamp(0, 12) * baseMs).ms)
      .slideY(begin: 0.12, end: 0, duration: 320.ms, delay: (index.clamp(0, 12) * baseMs).ms,
          curve: Curves.easeOutCubic);
}

/// Bouton qui s'enfonce légèrement au toucher.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.96 : 1,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      );
}
