import 'package:flutter/material.dart';

import '../alerts/alert_widgets.dart' show urgentColor;
import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../widgets/dates.dart';
import 'weather_data.dart';
import 'weather_format.dart';
import 'weather_repository.dart';

/// Amber for weather alerts: noticeable, but not the urgent red reserved
/// for boil water and fire bans (weather spec D4). Contrast ≥ 7:1 both ways.
({Color background, Color foreground}) weatherAlertColors(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
    ? (background: const Color(0xFFFFE08A), foreground: const Color(0xFF3D2E00))
    : (background: const Color(0xFF4A3800), foreground: const Color(0xFFFFE08A));

/// Today's banner while a warning, watch or advisory covers Témiscaming:
/// "Advisory · Environment Canada / Frost (advisory) / +1 more weather alert".
class WeatherAlertBanner extends StatelessWidget {
  const WeatherAlertBanner({super.key, required this.alerts, required this.language, required this.onTap});

  /// The banner's alerts (statements left out), most serious first.
  final List<WeatherAlert> alerts;
  final AppLanguage language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = weatherAlertColors(context);
    final first = alerts.first;
    final shownIn = first.displayLanguage(language);
    return Material(
      color: colors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: colors.foreground, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.weatherAlertBannerHeader(alertTypeLabel(l10n, first.type)),
                      style: textTheme.labelLarge?.copyWith(color: colors.foreground),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      first.title(language),
                      locale: shownIn.locale,
                      style: textTheme.titleMedium?.copyWith(
                        color: colors.foreground,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (alerts.length > 1) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.weatherAlertMore(alerts.length - 1),
                        style: textTheme.bodyMedium?.copyWith(color: colors.foreground),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.foreground),
            ],
          ),
        ),
      ),
    );
  }
}

/// A health line in the app's usual style: icon + words, red when there's
/// a problem (principle 3: silence must never look like safety).
class WeatherStatusLine extends StatelessWidget {
  const WeatherStatusLine({super.key, required this.text, required this.problem});

  final String text;
  final bool problem;

  @override
  Widget build(BuildContext context) {
    final color = problem ? urgentColor(context) : Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(problem ? Icons.error_outline : Icons.check_circle_outline, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
        ),
      ],
    );
  }
}

/// What to say about the weather alerts check, or null when all is well
/// and [onlyWhenProblem] is set (Today). "No weather alerts" is never
/// decided here: only the Weather screen says it, after a recent check.
({String text, bool problem})? alertsHealth(
  BuildContext context,
  WeatherRepository repository,
  DateTime now, {
  bool onlyWhenProblem = false,
}) {
  final l10n = AppLocalizations.of(context);
  if (repository.loading) return null;
  final w = repository.weather;
  if (repository.failed) return (text: l10n.weatherLoadFailed, problem: true);
  if (w == null || w.alertsCheckedAt == null) return (text: l10n.weatherAlertsNeverChecked, problem: true);
  if (w.alertsStale(now)) {
    return (text: l10n.weatherAlertsCheckFailedSince(formatWhen(context, w.alertsCheckedAt!)), problem: true);
  }
  if (onlyWhenProblem) return null;
  return (text: l10n.weatherAlertsLastChecked(formatWhen(context, w.alertsCheckedAt!)), problem: false);
}
