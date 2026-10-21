import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../widgets/dates.dart';
import 'weather_codes.dart';
import 'weather_format.dart';
import 'weather_repository.dart';
import 'weather_widgets.dart';

/// Today's weather card (weather spec §6): the station's temperature and
/// condition now, then today's forecast. Tapping opens the Weather screen.
class WeatherCard extends StatelessWidget {
  const WeatherCard({
    super.key,
    required this.settings,
    required this.repository,
    required this.onOpen,
    this.now,
  });

  final AppSettings settings;
  final WeatherRepository repository;
  final VoidCallback onOpen;

  /// For tests; defaults to the current time.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final language = settings.language ?? AppLanguage.fr;
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final at = now ?? DateTime.now();
        final w = repository.weather;
        final waiting = repository.loading && w == null;
        final c = w?.conditions;
        // Only a recent reading with a temperature is shown (spec D7).
        final reading = c != null && c.isRecent(at) && c.temperatureC != null ? c : null;
        final today = w?.daysFrom(at).firstOrNull;
        final alertsProblem = alertsHealth(context, repository, at, onlyWhenProblem: true);
        final condition = reading?.condition(language);
        final station = w?.station(language);
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(l10n.weatherTitle, style: textTheme.titleSmall),
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (waiting) const LinearProgressIndicator(),
                  if (reading != null) ...[
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(formatTemperature(l10n, reading.temperatureC!), style: textTheme.displaySmall),
                        if (condition != null) Text(condition, style: textTheme.titleMedium),
                      ],
                    ),
                    if (reading.windChill != null)
                      Text(l10n.weatherWindChill(wholeNumber(reading.windChill!)), style: textTheme.bodyLarge)
                    else if (reading.humidex != null)
                      Text(l10n.weatherHumidex(wholeNumber(reading.humidex!)), style: textTheme.bodyLarge),
                    if (station != null)
                      Text(
                        l10n.weatherStationAt(station, formatWhen(context, reading.observedAt, now: at)),
                        style: textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ] else if (c != null)
                    Text(l10n.weatherNoRecentReading, style: textTheme.bodyLarge),
                  if (today != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(wmoIcon(today.wmoCode), size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.weatherDayLine(
                              forecastDayName(context, today.date, at),
                              wmoText(l10n, today.wmoCode),
                              formatHighLow(l10n, today),
                            ),
                            style: textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (!waiting && !repository.failed && w == null)
                    WeatherStatusLine(text: l10n.weatherNeverChecked, problem: true),
                  if (alertsProblem != null && w != null) ...[
                    const SizedBox(height: 12),
                    WeatherStatusLine(text: alertsProblem.text, problem: alertsProblem.problem),
                  ],
                  if (repository.failed) WeatherStatusLine(text: l10n.weatherLoadFailed, problem: true),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
