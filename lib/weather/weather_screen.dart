import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../widgets/dates.dart';
import '../widgets/links.dart';
import 'weather_codes.dart';
import 'weather_data.dart';
import 'weather_format.dart';
import 'weather_repository.dart';
import 'weather_widgets.dart';

/// ECCC's page for Témiscaming: the official regional forecast and alerts
/// (weather spec D10: linked, not shown in the app).
final _ecccPageFr = Uri.parse('https://meteo.gc.ca/fr/location/index.html?coords=46.722,-79.093');
final _ecccPageEn = Uri.parse('https://weather.gc.ca/en/location/index.html?coords=46.722,-79.093');
final _openMeteo = Uri.parse('https://open-meteo.com/');

/// The Weather screen (weather spec §6): alerts with ECCC's full text,
/// conditions now at the station, the 7-day forecast, and where each comes from.
class WeatherScreen extends StatelessWidget {
  const WeatherScreen({super.key, required this.settings, required this.repository, this.now});

  final AppSettings settings;
  final WeatherRepository repository;

  /// For tests; defaults to the current time.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = settings.language ?? AppLanguage.fr;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.weatherTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: repository,
          builder: (context, _) {
            final at = now ?? DateTime.now();
            final w = repository.weather;
            if (repository.loading && w == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ..._alerts(context, w, at, language),
                const SizedBox(height: 24),
                ..._now(context, w, at, language),
                const SizedBox(height: 24),
                ..._forecast(context, w, at),
                const SizedBox(height: 24),
                ..._sources(context, w, language),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(header: true, child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
  );

  List<Widget> _alerts(BuildContext context, Weather? w, DateTime at, AppLanguage language) {
    final l10n = AppLocalizations.of(context);
    final health = alertsHealth(context, repository, at);
    final inEffect = w?.alertsInEffect(at) ?? const <WeatherAlert>[];
    return [
      _heading(context, l10n.weatherAlertsHeading),
      for (final a in inEffect) ...[
        _AlertCard(alert: a, language: language),
        const SizedBox(height: 12),
      ],
      // "No weather alerts" only right after a successful check (spec D5).
      if (inEffect.isEmpty && health != null && !health.problem) ...[
        Text(l10n.weatherNoAlerts, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 8),
      ],
      if (health != null) WeatherStatusLine(text: health.text, problem: health.problem),
    ];
  }

  List<Widget> _now(BuildContext context, Weather? w, DateTime at, AppLanguage language) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final c = w?.conditions;
    final station = w?.station(language);
    final r = c != null && c.isRecent(at) && c.temperatureC != null ? c : null;
    final condition = r?.condition(language);
    final wind = r == null ? '' : formatWind(l10n, language, r);
    return [
      _heading(context, l10n.weatherNowHeading),
      if (r == null)
        Text(c == null ? l10n.weatherNeverChecked : l10n.weatherNoRecentReading, style: textTheme.bodyLarge)
      else ...[
        Text(formatTemperature(l10n, r.temperatureC!), style: textTheme.displaySmall),
        if (condition != null) Text(condition, style: textTheme.titleMedium),
        const SizedBox(height: 8),
        if (r.windChill != null) Text(l10n.weatherWindChill(wholeNumber(r.windChill!)), style: textTheme.bodyLarge),
        if (r.humidex != null) Text(l10n.weatherHumidex(wholeNumber(r.humidex!)), style: textTheme.bodyLarge),
        if (wind.isNotEmpty) Text(wind, style: textTheme.bodyLarge),
        if (r.humidityPct != null) Text(l10n.weatherHumidity(wholeNumber(r.humidityPct!)), style: textTheme.bodyLarge),
      ],
      if (c != null && station != null) ...[
        const SizedBox(height: 8),
        Text(
          l10n.weatherStationAt(station, formatWhen(context, c.observedAt, now: at)),
          style: textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    ];
  }

  List<Widget> _forecast(BuildContext context, Weather? w, DateTime at) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final days = w?.daysFrom(at) ?? const <ForecastDay>[];
    final checked = w?.forecastCheckedAt;
    final stale = w?.forecastStale(at) ?? true;
    return [
      _heading(context, l10n.weatherForecastHeading),
      Text(l10n.weatherForecastNote, style: textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
      const SizedBox(height: 8),
      if (days.isEmpty) Text(l10n.weatherForecastUnavailable, style: textTheme.bodyLarge),
      for (final d in days)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(wmoIcon(d.wmoCode), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(forecastDayName(context, d.date, at), style: textTheme.titleSmall),
                    Text(wmoText(l10n, d.wmoCode), style: textTheme.bodyLarge),
                    Text(formatHighLow(l10n, d), style: textTheme.bodyLarge),
                    if (forecastDetails(l10n, d).isNotEmpty)
                      Text(forecastDetails(l10n, d), style: textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      if (checked != null)
        WeatherStatusLine(
          text: stale
              ? l10n.weatherForecastCheckFailedSince(formatWhen(context, checked))
              : l10n.weatherForecastUpdated(formatWhen(context, checked)),
          problem: stale,
        ),
    ];
  }

  List<Widget> _sources(BuildContext context, Weather? w, AppLanguage language) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final station = w?.station(language) ?? '—';
    return [
      _heading(context, l10n.weatherSourcesHeading),
      Text(l10n.weatherSourceEccc(station), style: textTheme.bodyMedium),
      const SizedBox(height: 8),
      Text(l10n.weatherSourceOpenMeteo, style: textTheme.bodyMedium),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: Text(l10n.weatherOfficialForecastLink),
          onPressed: () => openLink(language == AppLanguage.fr ? _ecccPageFr : _ecccPageEn),
        ),
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: Text(l10n.weatherOpenMeteoLink),
          onPressed: () => openLink(_openMeteo),
        ),
      ),
    ];
  }
}

/// One alert with ECCC's full text (principle 2: we relay, we don't replace).
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.language});

  final WeatherAlert alert;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = weatherAlertColors(context);
    final shownIn = alert.displayLanguage(language);
    final url = alert.sourceUrl(language);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.foreground.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(6)),
              child: Text(
                alertTypeLabel(l10n, alert.type),
                style: textTheme.labelLarge?.copyWith(color: colors.foreground),
              ),
            ),
            const SizedBox(height: 8),
            if (shownIn != language) ...[
              Text(
                shownIn == AppLanguage.fr ? l10n.alertOnlyFrench : l10n.alertOnlyEnglish,
                style: textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 4),
            ],
            Text(alert.title(language), locale: shownIn.locale, style: textTheme.titleMedium),
            if (alert.area(language).isNotEmpty) Text(alert.area(language), style: textTheme.bodyMedium),
            const SizedBox(height: 4),
            if (alert.publishedAt != null)
              Text(l10n.weatherAlertIssued(formatWhen(context, alert.publishedAt!)), style: textTheme.bodyMedium),
            if (alert.endsAt != null)
              Text(l10n.weatherAlertEnds(formatWhen(context, alert.endsAt!)), style: textTheme.bodyMedium),
            const SizedBox(height: 8),
            SelectableText(alert.body(language), style: textTheme.bodyLarge),
            if (url.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: Text(l10n.weatherAlertSourceLink),
                  onPressed: () => openLink(Uri.parse(url)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
