import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../settings_screen.dart';
import '../widgets/centered_scroll_column.dart';

/// Home screen. A placeholder until Milestone 1 adds real content.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.todayTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            // The tooltip doubles as the screen-reader label.
            tooltip: l10n.settingsTitle,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(settings: settings),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: CenteredScrollColumn(
          children: [
            Text(
              l10n.todayComingSoon,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
