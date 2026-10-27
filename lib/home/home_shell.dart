import 'package:flutter/material.dart';

import '../alerts/alerts_screen.dart';
import '../events/events_screen.dart';
import '../l10n/app_localizations.dart';
import '../more/more_screen.dart';
import '../services.dart';
import '../settings/app_settings.dart';
import '../settings_screen.dart';
import 'today_screen.dart';

/// The main app after first launch: a bottom bar with Today, Alerts,
/// Events and More (DESIGN §7; More since Milestone 7, roads spec D13).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.settings, required this.services});

  final AppSettings settings;
  final AppServices services;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _eventsTab = 2;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = [
      IconButton(
        icon: const Icon(Icons.settings_outlined),
        // The tooltip doubles as the screen-reader label.
        tooltip: l10n.settingsTitle,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(
              settings: widget.settings,
              push: widget.services.push,
              reminders: widget.services.reminders,
              collection: widget.services.collection,
            ),
          ),
        ),
      ),
    ];
    return Scaffold(
      // IndexedStack keeps each tab's scroll position when switching.
      body: IndexedStack(
        index: _tab,
        children: [
          TodayScreen(
            settings: widget.settings,
            repository: widget.services.alerts,
            collection: widget.services.collection,
            events: widget.services.events,
            weather: widget.services.weather,
            fire: widget.services.fire,
            roads: widget.services.roads,
            push: widget.services.push,
            onOpenEvents: () => setState(() => _tab = _eventsTab),
            appBarActions: actions,
          ),
          AlertsScreen(
            settings: widget.settings,
            repository: widget.services.alerts,
            appBarActions: actions,
          ),
          EventsScreen(
            settings: widget.settings,
            repository: widget.services.events,
            calendar: widget.services.calendar,
            appBarActions: actions,
          ),
          MoreScreen(settings: widget.settings, services: widget.services),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.today_outlined),
            selectedIcon: const Icon(Icons.today),
            label: l10n.todayTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.campaign_outlined),
            selectedIcon: const Icon(Icons.campaign),
            label: l10n.alertsTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.event_outlined),
            selectedIcon: const Icon(Icons.event),
            label: l10n.eventsTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu),
            selectedIcon: const Icon(Icons.menu_open),
            label: l10n.moreTitle,
          ),
        ],
      ),
    );
  }
}
