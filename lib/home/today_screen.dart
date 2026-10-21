import 'package:flutter/material.dart';

import '../alerts/alert_detail_screen.dart';
import '../alerts/alert_widgets.dart';
import '../alerts/alerts_repository.dart';
import '../collection/collection_card.dart';
import '../collection/collection_repository.dart';
import '../collection/collection_screen.dart';
import '../events/events_card.dart';
import '../events/events_repository.dart';
import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';

/// Home screen: the boil-water banner when one is in effect, a warning if
/// the Town's alerts can't be checked, this week's bin, the next few events,
/// and a placeholder for the features still to come (weather — DESIGN §7).
class TodayScreen extends StatelessWidget {
  const TodayScreen({
    super.key,
    required this.settings,
    required this.repository,
    required this.collection,
    required this.events,
    required this.onOpenEvents,
    required this.appBarActions,
  });

  final AppSettings settings;
  final AlertsRepository repository;
  final CollectionRepository collection;
  final EventsRepository events;

  /// Switches to the Events tab.
  final VoidCallback onOpenEvents;
  final List<Widget> appBarActions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = settings.language ?? AppLanguage.fr;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.todayTitle), actions: appBarActions),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: repository,
          builder: (context, _) {
            final now = DateTime.now();
            final boil = repository.alerts
                .where((a) => a.isBoilWaterInEffect(now))
                .firstOrNull;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (boil != null) ...[
                  BoilWaterBanner(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AlertDetailScreen(alert: boil, language: language),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SourceHealthLine(repository: repository, onlyWhenStale: true),
                const SizedBox(height: 8),
                CollectionCard(
                  settings: settings,
                  repository: collection,
                  onOpenSchedule: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CollectionScreen(settings: settings, repository: collection),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                EventsCard(settings: settings, repository: events, onOpenEvents: onOpenEvents),
                const SizedBox(height: 24),
                Text(
                  l10n.todayComingSoon,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
