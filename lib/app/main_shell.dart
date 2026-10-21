// PARKFASO — Navigation principale (onglets selon le rôle).

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'inside_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final admin = app.isAdmin;
    final pages = <(Widget, NavigationDestination)>[
      (HomeScreen(onOpenTab: (i) => setState(() => _tab = i)),
          const NavigationDestination(icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard), label: 'Accueil')),
      (const InsideScreen(), NavigationDestination(
          icon: Badge(
            isLabelVisible: app.stats.inside > 0,
            label: Text('${app.stats.inside}'),
            child: const Icon(Icons.local_parking_outlined),
          ),
          selectedIcon: const Icon(Icons.local_parking),
          label: 'Présents')),
      (const HistoryScreen(), const NavigationDestination(icon: Icon(Icons.history),
          selectedIcon: Icon(Icons.history_toggle_off), label: 'Historique')),
      if (admin)
        (const ReportsScreen(), const NavigationDestination(icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights), label: 'Rapports')),
      (const SettingsScreen(), NavigationDestination(
          icon: const Icon(Icons.tune_outlined), selectedIcon: const Icon(Icons.tune),
          label: admin ? 'Réglages' : 'Plus')),
    ];
    final tab = _tab.clamp(0, pages.length - 1);
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        child: KeyedSubtree(key: ValueKey('tab$tab-${app.parking?.id}'), child: pages[tab].$1),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [for (final p in pages) p.$2],
      ),
    );
  }
}
