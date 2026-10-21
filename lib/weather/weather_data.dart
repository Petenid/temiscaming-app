import '../collection/pickup.dart' show parseDay;
import '../collection/schedule.dart';
import '../settings/app_settings.dart';

/// Environment Canada's four kinds of weather alert, most serious first.
enum WeatherAlertType { warning, watch, advisory, statement }

/// One ECCC weather alert covering Témiscaming (weather spec D2), with
/// ECCC's own French and English text.
class WeatherAlert {
  const WeatherAlert({
    required this.id,
    required this.type,
    required this.titleFr,
    required this.titleEn,
    required this.areaFr,
    required this.areaEn,
    required this.bodyFr,
    required this.bodyEn,
    this.publishedAt,
    this.endsAt,
    this.expiresAt,
    required this.sourceUrlFr,
    required this.sourceUrlEn,
  });

  final String id;
  final WeatherAlertType type;
  final String titleFr;
  final String titleEn;
  final String areaFr;
  final String areaEn;
  final String bodyFr;
  final String bodyEn;
  final DateTime? publishedAt;

  /// When ECCC expects the weather event to end.
  final DateTime? endsAt;

  /// When ECCC stops showing the alert; after that it's no longer in effect.
  final DateTime? expiresAt;
  final String sourceUrlFr;
  final String sourceUrlEn;

  /// Statements are informational: Weather screen only, not the Today banner (spec D4).
  bool get inBanner => type != WeatherAlertType.statement;

  bool isInEffect(DateTime now) => expiresAt == null || expiresAt!.isAfter(now);

  /// ECCC gives both languages; if one is ever missing, fall back to the
  /// other, and the screen labels it (DESIGN §5).
  AppLanguage displayLanguage(AppLanguage wanted) {
    final has = wanted == AppLanguage.fr ? titleFr.isNotEmpty : titleEn.isNotEmpty;
    if (has) return wanted;
    return wanted == AppLanguage.fr ? AppLanguage.en : AppLanguage.fr;
  }

  String title(AppLanguage l) => displayLanguage(l) == AppLanguage.fr ? titleFr : titleEn;
  String area(AppLanguage l) => displayLanguage(l) == AppLanguage.fr ? areaFr : areaEn;
  String body(AppLanguage l) => displayLanguage(l) == AppLanguage.fr ? bodyFr : bodyEn;
  String sourceUrl(AppLanguage l) => l == AppLanguage.fr ? sourceUrlFr : sourceUrlEn;

  static WeatherAlert? fromMap(Map<String, Object?> m) {
    final id = m['id'];
    if (id is! String || id.isEmpty) return null;
    final type = WeatherAlertType.values.where((t) => t.name == m['type']).firstOrNull ??
        WeatherAlertType.advisory; // unknown: shown, never hidden (backend does the same)
    String text(String k) => (m[k] as String?) ?? '';
    return WeatherAlert(
      id: id,
      type: type,
      titleFr: text('title_fr'),
      titleEn: text('title_en'),
      areaFr: text('area_fr'),
      areaEn: text('area_en'),
      bodyFr: text('body_fr'),
      bodyEn: text('body_en'),
      publishedAt: m['published_at'] as DateTime?,
      endsAt: m['ends_at'] as DateTime?,
      expiresAt: m['expires_at'] as DateTime?,
      sourceUrlFr: text('source_url_fr'),
      sourceUrlEn: text('source_url_en'),
    );
  }
}

/// The latest reading at the Barrage Témiscaming station. Any value can be
/// missing (at night ECCC sends no condition text): null, never a guess.
class Conditions {
  const Conditions({
    required this.observedAt,
    this.temperatureC,
    this.conditionFr,
    this.conditionEn,
    this.windKmh,
    this.windDir,
    this.gustKmh,
    this.windChill,
    this.humidex,
    this.humidityPct,
  });

  final DateTime observedAt;
  final double? temperatureC;
  final String? conditionFr;
  final String? conditionEn;
  final double? windKmh;

  /// "SE", "NNW", "VR" (variable)… as ECCC sends it, in English letters.
  final String? windDir;
  final double? gustKmh;
  final double? windChill;
  final double? humidex;
  final double? humidityPct;

  /// Older than this, the temperature is hidden: a frozen value would look
  /// like the present (spec D7).
  static const recentFor = Duration(hours: 3);

  bool isRecent(DateTime now) => now.difference(observedAt) <= recentFor;

  String? condition(AppLanguage l) => l == AppLanguage.fr ? conditionFr : conditionEn;

  static Conditions? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, Object?>();
    final observed = m['observed_at'];
    if (observed is! DateTime) return null;
    double? n(String k) => (m[k] as num?)?.toDouble();
    return Conditions(
      observedAt: observed,
      temperatureC: n('temperature_c'),
      conditionFr: m['condition_fr'] as String?,
      conditionEn: m['condition_en'] as String?,
      windKmh: n('wind_kmh'),
      windDir: m['wind_dir'] as String?,
      gustKmh: n('gust_kmh'),
      windChill: n('wind_chill'),
      humidex: n('humidex'),
      humidityPct: n('humidity_pct'),
    );
  }
}

/// One day of the Open-Meteo forecast for Témiscaming (spec D1).
class ForecastDay {
  const ForecastDay({
    required this.date,
    required this.wmoCode,
    required this.highC,
    required this.lowC,
    this.rainMm,
    this.snowCm,
    this.gustMaxKmh,
  });

  /// Local date (midnight).
  final DateTime date;
  final int wmoCode;
  final double highC;
  final double lowC;
  final double? rainMm;
  final double? snowCm;
  final double? gustMaxKmh;

  static ForecastDay? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, Object?>();
    final date = parseDay(m['date'] as String?);
    final code = m['wmo_code'];
    final high = m['high_c'];
    final low = m['low_c'];
    if (date == null || code is! num || high is! num || low is! num) return null;
    return ForecastDay(
      date: date,
      wmoCode: code.toInt(),
      highC: high.toDouble(),
      lowC: low.toDouble(),
      rainMm: (m['rain_mm'] as num?)?.toDouble(),
      snowCm: (m['snow_cm'] as num?)?.toDouble(),
      gustMaxKmh: (m['gust_max_kmh'] as num?)?.toDouble(),
    );
  }
}

/// Firestore `weather/temiscaming`, written by two backend runs. Each part
/// carries the time it was last read successfully: that's its health.
class Weather {
  const Weather({
    this.stationFr,
    this.stationEn,
    this.conditions,
    this.conditionsCheckedAt,
    this.alerts = const [],
    this.alertsCheckedAt,
    this.days = const [],
    this.forecastCheckedAt,
  });

  final String? stationFr;
  final String? stationEn;
  final Conditions? conditions;
  final DateTime? conditionsCheckedAt;
  final List<WeatherAlert> alerts;
  final DateTime? alertsCheckedAt;
  final List<ForecastDay> days;
  final DateTime? forecastCheckedAt;

  /// Checked every 15 minutes: red after 4 missed runs (spec D3).
  static const alertsStaleAfter = Duration(hours: 1);

  /// Open-Meteo's models update every 6 hours; checked hourly.
  static const forecastStaleAfter = Duration(hours: 8);

  String? station(AppLanguage l) => l == AppLanguage.fr ? stationFr ?? stationEn : stationEn ?? stationFr;

  bool alertsStale(DateTime now) =>
      alertsCheckedAt == null || now.difference(alertsCheckedAt!) > alertsStaleAfter;

  bool forecastStale(DateTime now) =>
      forecastCheckedAt == null || now.difference(forecastCheckedAt!) > forecastStaleAfter;

  /// Alerts still in effect, most serious first (the backend sorts them;
  /// expired ones drop out here too, in case the backend has stopped).
  List<WeatherAlert> alertsInEffect(DateTime now) => [
    for (final a in alerts)
      if (a.isInEffect(now)) a,
  ];

  /// Today and later (a stale document may still hold yesterday).
  List<ForecastDay> daysFrom(DateTime now) {
    final today = dateOnly(now);
    return [
      for (final d in days)
        if (!d.date.isBefore(today)) d,
    ];
  }

  factory Weather.fromMap(Map<String, Object?> m) {
    List<Object?> list(String k) => (m[k] as List?)?.cast<Object?>() ?? const [];
    return Weather(
      stationFr: m['station_fr'] as String?,
      stationEn: m['station_en'] as String?,
      conditions: Conditions.fromMap(m['conditions']),
      conditionsCheckedAt: m['conditions_checked_at'] as DateTime?,
      alerts: [
        for (final a in list('alerts'))
          if (a is Map) ?WeatherAlert.fromMap(a.cast<String, Object?>()),
      ],
      alertsCheckedAt: m['alerts_checked_at'] as DateTime?,
      days: [for (final d in list('days')) ?ForecastDay.fromMap(d)],
      forecastCheckedAt: m['forecast_checked_at'] as DateTime?,
    );
  }
}
