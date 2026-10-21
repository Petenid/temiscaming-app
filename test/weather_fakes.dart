import 'package:community/collection/schedule.dart';
import 'package:community/weather/weather_data.dart';
import 'package:community/weather/weather_repository.dart';

/// Weather held in memory; tests set it and the screens update.
class FakeWeatherRepository extends WeatherRepository {
  FakeWeatherRepository({Weather? weather, bool useDefault = true, bool loading = false, bool failed = false})
    : _weather = weather ?? (useDefault ? SampleWeather.normal() : null),
      _loading = loading,
      _failed = failed;

  Weather? _weather;
  bool _loading;
  final bool _failed;

  @override
  Weather? get weather => _weather;
  @override
  bool get loading => _loading;
  @override
  bool get failed => _failed;

  void set(Weather? weather) {
    _weather = weather;
    _loading = false;
    notifyListeners();
  }
}

/// Sample weather modelled on the backend's first live run (2026-10-21,
/// 1 a.m.: 1.9 °C at the dam, wind chill −4, no condition text at night),
/// placed around now so it always counts as recent.
class SampleWeather {
  static DateTime ago(Duration d) => DateTime.now().subtract(d);
  static DateTime day(int fromToday) => addDays(dateOnly(DateTime.now()), fromToday);

  static Conditions reading({Duration age = const Duration(minutes: 25), String? conditionEn, String? conditionFr}) =>
      Conditions(
        observedAt: ago(age),
        temperatureC: 1.9,
        conditionFr: conditionFr,
        conditionEn: conditionEn,
        windKmh: 4,
        windDir: 'SW',
        gustKmh: 27,
        windChill: -4,
        humidityPct: 94,
      );

  static List<ForecastDay> week({int startDay = 0}) => [
    ForecastDay(date: day(startDay), wmoCode: 3, highC: 16.3, lowC: -0.9, rainMm: 0, snowCm: 0, gustMaxKmh: 31),
    ForecastDay(date: day(startDay + 1), wmoCode: 61, highC: 11.6, lowC: 1.7, rainMm: 6.2, snowCm: 0, gustMaxKmh: 30),
    ForecastDay(date: day(startDay + 2), wmoCode: 2, highC: 10.6, lowC: -3.7, rainMm: 0, snowCm: 0, gustMaxKmh: 12),
    ForecastDay(date: day(startDay + 3), wmoCode: 0, highC: 14.9, lowC: -3.8, rainMm: 0, snowCm: 0, gustMaxKmh: 23),
    ForecastDay(date: day(startDay + 4), wmoCode: 73, highC: 1.1, lowC: -6.7, rainMm: 0, snowCm: 4.3, gustMaxKmh: 52),
    ForecastDay(date: day(startDay + 5), wmoCode: 0, highC: 11.5, lowC: 1.6, rainMm: 0, snowCm: 0, gustMaxKmh: 28),
    ForecastDay(date: day(startDay + 6), wmoCode: 0, highC: 6.5, lowC: -2.5, rainMm: 0, snowCm: 0, gustMaxKmh: 12),
  ];

  /// Tonight's real frost advisory text (ECCC), as if it covered Témiscaming.
  static WeatherAlert frostAdvisory({DateTime? expiresAt}) => WeatherAlert(
    id: '165538168887825634202610190504',
    type: WeatherAlertType.advisory,
    titleFr: 'Gel (avis)',
    titleEn: 'Frost (advisory)',
    areaFr: 'secteur de Témiscaming',
    areaEn: 'Témiscaming area',
    bodyFr: 'Les températures chuteront près ou sous le point de congélation au cours de la nuit.\n\n'
        'Des dommages aux plantes, aux arbres et aux cultures sont possibles.',
    bodyEn: 'Temperatures will drop to near or below the freezing mark overnight tonight.\n\n'
        'Damage to plants, trees, and crops is possible.',
    publishedAt: ago(const Duration(hours: 2)),
    endsAt: DateTime.now().add(const Duration(hours: 8)),
    expiresAt: expiresAt ?? DateTime.now().add(const Duration(hours: 9)),
    sourceUrlFr: 'https://meteo.gc.ca/fr/location/index.html?coords=46.722,-79.093',
    sourceUrlEn: 'https://weather.gc.ca/en/location/index.html?coords=46.722,-79.093',
  );

  static WeatherAlert freezingRainWarning() => WeatherAlert(
    id: '2',
    type: WeatherAlertType.warning,
    titleFr: 'Pluie verglaçante (avertissement)',
    titleEn: 'Freezing rain (warning)',
    areaFr: 'secteur de Témiscaming',
    areaEn: 'Témiscaming area',
    bodyFr: 'Exemple de texte d’avertissement pour les tests.',
    bodyEn: 'Sample warning text for tests.',
    publishedAt: ago(const Duration(hours: 1)),
    expiresAt: DateTime.now().add(const Duration(hours: 12)),
    sourceUrlFr: 'https://meteo.gc.ca/fr/location/index.html?coords=46.722,-79.093',
    sourceUrlEn: 'https://weather.gc.ca/en/location/index.html?coords=46.722,-79.093',
  );

  static WeatherAlert specialStatement() => WeatherAlert(
    id: '3',
    type: WeatherAlertType.statement,
    titleFr: 'Bulletin météorologique spécial',
    titleEn: 'Special weather statement',
    areaFr: 'secteur de Témiscaming',
    areaEn: 'Témiscaming area',
    bodyFr: 'Exemple de bulletin pour les tests.',
    bodyEn: 'Sample statement for tests.',
    publishedAt: ago(const Duration(hours: 3)),
    expiresAt: DateTime.now().add(const Duration(hours: 24)),
    sourceUrlFr: 'https://meteo.gc.ca/fr/location/index.html?coords=46.722,-79.093',
    sourceUrlEn: 'https://weather.gc.ca/en/location/index.html?coords=46.722,-79.093',
  );

  /// Everything fresh, no alerts: the usual night.
  static Weather normal({
    List<WeatherAlert> alerts = const [],
    Conditions? conditions,
    Duration alertsAge = const Duration(minutes: 5),
    Duration forecastAge = const Duration(minutes: 30),
    List<ForecastDay>? days,
  }) => Weather(
    stationFr: 'Barrage Témiscaming',
    stationEn: 'Temiskaming Dam',
    conditions: conditions ?? reading(),
    conditionsCheckedAt: ago(const Duration(minutes: 5)),
    alerts: alerts,
    alertsCheckedAt: ago(alertsAge),
    days: days ?? week(),
    forecastCheckedAt: ago(forecastAge),
  );
}
