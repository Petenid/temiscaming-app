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
import '../weather/weather_card.dart';
import '../weather/weather_data.dart';
import '../weather/weather_repository.dart';
import '../weather/weather_screen.dart';
import '../weather/weather_widgets.dart';

/// Home screen (DESIGN §7): the boil-water banner when one is in effect, the
/// weather alert banner, a warning if the Town's alerts can't be checked,
/// this week's bin, the weather, the next few events, and a placeholder for
/// the features still to come.
class TodayScreen extends StatelessWidget {
  const TodayScreen({
    super.key,
    required this.settings,
    required this.repository,
    required this.collection,
    required this.events,
    required this.weather,
    required this.onOpenEvents,
    required this.appBarActions,
  });

  final AppSettings settings;
  final AlertsRepository repository;
  final CollectionRepository collection;
  final EventsRepository events;
  final WeatherRepository weather;

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
          listenable: Listenable.merge([repository, weather]),
          builder: (context, _) {
            final now = DateTime.now();
            final boil = repository.alerts
                .where((a) => a.isBoilWaterInEffect(now))
                .firstOrNull;
            // Warnings, watches and advisories; statements stay on the Weather screen (spec D4).
            final weatherAlerts = [
              for (final a in weather.weather?.alertsInEffect(now) ?? const <WeatherAlert>[]) if (a.inBanner) a,
            ];
            void openWeather() => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => WeatherScreen(settings: settings, repository: weather),
              ),
            );
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
                if (weatherAlerts.isNotEmpty) ...[
                  WeatherAlertBanner(alerts: weatherAlerts, language: language, onTap: openWeather),
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
                WeatherCard(settings: settings, repository: weather, onOpen: openWeather),
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
