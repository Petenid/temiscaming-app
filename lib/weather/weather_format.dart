import 'package:flutter/widgets.dart';

import '../collection/schedule.dart';
import '../events/town_event.dart' show EventWhen, eventWhen;
import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../widgets/dates.dart';
import 'weather_data.dart';

/// A whole number with a real minus sign: "−4" reads better than "-4".
String wholeNumber(double v) {
  final n = v.round();
  return n < 0 ? '−${-n}' : '$n';
}

/// "2 °C" / "2°C".
String formatTemperature(AppLocalizations l10n, double c) => l10n.weatherTemperature(wholeNumber(c));

/// ECCC sends English letters ("SW", "VR"); French uses O for ouest.
String windDirection(AppLocalizations l10n, AppLanguage language, String dir) {
  if (dir == 'VR') return l10n.weatherWindVariable;
  return language == AppLanguage.fr ? dir.replaceAll('W', 'O') : dir;
}

/// "Wind SE 4 km/h, gusts 27 km/h" / "Wind calm".
String formatWind(AppLocalizations l10n, AppLanguage language, Conditions c) {
  final speed = c.windKmh;
  if (speed == null) return '';
  if (speed.round() == 0) return l10n.weatherWindCalm;
  final dir = c.windDir == null ? '' : windDirection(l10n, language, c.windDir!);
  final wind = l10n.weatherWind(dir, wholeNumber(speed)).replaceAll('  ', ' ');
  final gust = c.gustKmh;
  return gust != null && gust > speed ? l10n.weatherWindGusts(wind, wholeNumber(gust)) : wind;
}

/// "Today", "Tomorrow" or "Thu, Oct 22".
String forecastDayName(BuildContext context, DateTime day, DateTime now) {
  final l10n = AppLocalizations.of(context);
  return switch (eventWhen(day, dateOnly(now))) {
    EventWhen.today => l10n.eventToday,
    EventWhen.tomorrow => l10n.eventTomorrow,
    EventWhen.later => formatShortDay(context, day),
  };
}

/// Rain, snow and strong gusts, only when they matter: "Rain 5 mm · Gusts up to 60 km/h".
String forecastDetails(AppLocalizations l10n, ForecastDay d) {
  final parts = <String>[
    if ((d.rainMm ?? 0) >= 1) l10n.weatherRain(wholeNumber(d.rainMm!)),
    if ((d.snowCm ?? 0) >= 1) l10n.weatherSnow(wholeNumber(d.snowCm!)),
    if ((d.gustMaxKmh ?? 0) >= 40) l10n.weatherGustsUpTo(wholeNumber(d.gustMaxKmh!)),
  ];
  return parts.join(' · ');
}

/// "High 16° · Low −1°".
String formatHighLow(AppLocalizations l10n, ForecastDay d) =>
    l10n.weatherHighLow(wholeNumber(d.highC), wholeNumber(d.lowC));

/// The type of alert, written out (never colour alone, DESIGN §7).
String alertTypeLabel(AppLocalizations l10n, WeatherAlertType t) => switch (t) {
  WeatherAlertType.warning => l10n.weatherAlertTypeWarning,
  WeatherAlertType.watch => l10n.weatherAlertTypeWatch,
  WeatherAlertType.advisory => l10n.weatherAlertTypeAdvisory,
  WeatherAlertType.statement => l10n.weatherAlertTypeStatement,
};
