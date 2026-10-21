// Today's weather card and banner, and the Weather screen (weather spec §6,
// §8 step 2). Principle 3 cases: an old reading, a stale alerts check and a
// never-run backend must never look like "all clear".
import 'dart:io';

import 'package:community/settings/app_settings.dart';
import 'package:community/weather/weather_card.dart';
import 'package:community/weather/weather_codes.dart';
import 'package:community/weather/weather_data.dart';
import 'package:community/weather/weather_format.dart';
import 'package:community/weather/weather_screen.dart';
import 'package:community/weather/weather_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'weather_fakes.dart';

const _en = {'language': 'en', 'sector': 'town'};
const _fr = {'language': 'fr', 'sector': 'town'};

Future<void> _pump(WidgetTester tester, Map<String, Object> prefs, FakeWeatherRepository weather) =>
    pumpApp(tester, prefs, null, null, null, null, null, null, weather);

/// Scrolls the visible list until [finder] is on screen.
Future<void> _scrollTo(WidgetTester tester, Finder finder) => tester.scrollUntilVisible(
  finder, 200, scrollable: find.byType(Scrollable).hitTestable().first,
);

Finder _inCard(Finder f) => find.descendant(of: find.byType(WeatherCard), matching: f);

Future<void> _openWeather(WidgetTester tester, AppLanguage language) async {
  final title = _inCard(find.text(stringsFor(language).weatherTitle));
  await _scrollTo(tester, title);
  await scrollAndTap(tester, title);
  expect(find.byType(WeatherScreen), findsOneWidget);
}

void main() {
  group('labels and formatting', () {
    test('every WMO code the backend accepts has its own label in both languages', () {
      // Same list as functions/src/weather/forecast.ts WMO_CODES.
      final ts = File('functions/src/weather/forecast.ts').readAsStringSync();
      final list = RegExp(r'WMO_CODES = \[([\d,\s]+)\]').firstMatch(ts)!.group(1)!;
      final backend = {
        for (final s in list.split(',')) if (s.trim().isNotEmpty) int.parse(s.trim()),
      };
      expect(wmoCodes.keys.toSet(), backend);
      for (final language in AppLanguage.values) {
        final l10n = stringsFor(language);
        for (final code in backend) {
          expect(wmoText(l10n, code), isNot(l10n.wmoUnknown), reason: 'code $code');
          expect(wmoText(l10n, code), isNotEmpty);
        }
        expect(wmoText(l10n, 42), l10n.wmoUnknown);
      }
    });

    test('whole numbers use a real minus sign, and −0 is 0', () {
      expect(wholeNumber(1.9), '2');
      expect(wholeNumber(-3.7), '−4');
      expect(wholeNumber(-0.4), '0');
    });

    test('wind in French uses O for ouest; variable wind is written out', () {
      final fr = stringsFor(AppLanguage.fr);
      expect(windDirection(fr, AppLanguage.fr, 'SW'), 'SO');
      expect(windDirection(fr, AppLanguage.fr, 'VR'), 'variable');
      expect(windDirection(stringsFor(AppLanguage.en), AppLanguage.en, 'WNW'), 'WNW');
      expect(formatWind(stringsFor(AppLanguage.en), AppLanguage.en, SampleWeather.reading()),
          'Wind SW 4 km/h, gusts 27 km/h');
      expect(formatWind(fr, AppLanguage.fr, SampleWeather.reading()), 'Vent SO 4 km/h, rafales 27 km/h');
    });

    test('reads the Firestore document as the backend writes it', () {
      final w = Weather.fromMap({
        'station_fr': 'Barrage Témiscaming',
        'station_en': 'Temiskaming Dam',
        'conditions': {
          'observed_at': DateTime.utc(2026, 10, 21, 5), 'temperature_c': 1, 'condition_fr': null,
          'condition_en': null, 'eccc_icon': null, 'wind_kmh': 4, 'wind_dir': 'S', 'gust_kmh': 27,
          'wind_chill': -4, 'humidex': null, 'humidity_pct': 94,
        },
        'conditions_checked_at': DateTime.utc(2026, 10, 21, 5, 7),
        'alerts': <Object?>[],
        'alerts_checked_at': DateTime.utc(2026, 10, 21, 5, 7),
        'days': [
          {'date': '2026-10-21', 'wmo_code': 3, 'high_c': 16.3, 'low_c': -0.9, 'precip_mm': 0, 'rain_mm': 0,
           'snow_cm': 0, 'wind_max_kmh': 10.1, 'gust_max_kmh': 31.3, 'wind_dir_deg': 203,
           'sunrise': '2026-10-21T07:42', 'sunset': '2026-10-21T18:18'},
          {'date': 'not a date', 'wmo_code': 3, 'high_c': 1, 'low_c': 0},
        ],
        'forecast_checked_at': DateTime.utc(2026, 10, 21, 4, 36),
      });
      expect(w.conditions!.temperatureC, 1);
      expect(w.conditions!.conditionEn, isNull);
      expect(w.days.single.date, DateTime(2026, 10, 21));
      expect(w.days.single.highC, 16.3);
      expect(w.alerts, isEmpty);
    });

    test('an expired alert and yesterday\'s forecast drop out', () {
      final now = DateTime.now();
      final w = SampleWeather.normal(
        alerts: [SampleWeather.frostAdvisory(expiresAt: now.subtract(const Duration(minutes: 1)))],
        days: SampleWeather.week(startDay: -1),
      );
      expect(w.alertsInEffect(now), isEmpty);
      expect(w.daysFrom(now).first.date, SampleWeather.day(0));
      expect(w.daysFrom(now), hasLength(6));
    });
  });

  for (final (prefs, language) in [(_en, AppLanguage.en), (_fr, AppLanguage.fr)]) {
    final strings = stringsFor(language);
    testWidgets('Today card: temperature, wind chill, station and today\'s forecast (${language.name})', (tester) async {
      await _pump(tester, prefs, FakeWeatherRepository());
      await _scrollTo(tester, find.byType(WeatherCard));
      expect(_inCard(find.text(language == AppLanguage.en ? '2°C' : '2 °C')), findsOneWidget);
      expect(_inCard(find.text(language == AppLanguage.en ? 'Wind chill −4' : 'Refroidissement éolien −4')), findsOneWidget);
      expect(_inCard(find.textContaining(language == AppLanguage.en ? 'Temiskaming Dam station' : 'Station Barrage Témiscaming')),
          findsOneWidget);
      expect(_inCard(find.text(language == AppLanguage.en
          ? 'Today: Cloudy, High 16° · Low −1°'
          : 'Aujourd’hui : Nuageux, Max 16° · Min −1°')), findsOneWidget);
      // No alerts and all fresh: no banner, no warning line.
      expect(find.byType(WeatherAlertBanner), findsNothing);
      expect(_inCard(find.byType(WeatherStatusLine)), findsNothing);
    });

    testWidgets('a weather advisory: amber banner on Today, full ECCC text on the Weather screen (${language.name})', (tester) async {
      final frost = SampleWeather.frostAdvisory();
      await _pump(tester, prefs, FakeWeatherRepository(weather: SampleWeather.normal(alerts: [frost])));
      expect(find.byType(WeatherAlertBanner), findsOneWidget);
      expect(find.text(strings.weatherAlertBannerHeader(strings.weatherAlertTypeAdvisory)), findsOneWidget);
      expect(find.text(frost.title(language)), findsOneWidget);
      expect(find.text(strings.weatherAlertMore(1)), findsNothing);

      await scrollAndTap(tester, find.byType(WeatherAlertBanner));
      expect(find.byType(WeatherScreen), findsOneWidget);
      expect(find.text(frost.body(language)), findsOneWidget);
      expect(find.text(strings.weatherNoAlerts), findsNothing);
    });
  }

  testWidgets('several alerts: the most serious leads, "+1 more"', (tester) async {
    await _pump(tester, _en, FakeWeatherRepository(weather: SampleWeather.normal(
      alerts: [SampleWeather.freezingRainWarning(), SampleWeather.frostAdvisory()],
    )));
    expect(find.text('Warning · Environment Canada'), findsOneWidget);
    expect(find.text('Freezing rain (warning)'), findsOneWidget);
    expect(find.text('+1 more weather alert'), findsOneWidget);
  });

  testWidgets('a special weather statement stays off Today but shows on the Weather screen', (tester) async {
    await _pump(tester, _en, FakeWeatherRepository(weather: SampleWeather.normal(
      alerts: [SampleWeather.specialStatement()],
    )));
    expect(find.byType(WeatherAlertBanner), findsNothing);
    await _openWeather(tester, AppLanguage.en);
    expect(find.text('Special weather statement'), findsOneWidget);
    expect(find.text('Statement'), findsOneWidget);
  });

  testWidgets('Weather screen with no alerts after a fresh check: says so, then now, 7 days and sources', (tester) async {
    await _pump(tester, _en, FakeWeatherRepository());
    await _openWeather(tester, AppLanguage.en);
    expect(find.text('No weather alerts for Témiscaming.'), findsOneWidget);
    expect(find.textContaining('Alerts checked: '), findsOneWidget);
    expect(find.text('Wind SW 4 km/h, gusts 27 km/h'), findsOneWidget);
    expect(find.text('Humidity 94%'), findsOneWidget);
    await _scrollTo(tester, find.text('Computer forecast for Témiscaming'));
    await _scrollTo(tester, find.text('Rain 6 mm'));
    await _scrollTo(tester, find.text('Snow 4 cm · Gusts up to 52 km/h'));
    await _scrollTo(tester, find.textContaining('Not reviewed by a meteorologist'));
    expect(find.text("Environment Canada's official forecast for the region"), findsOneWidget);
  });

  group('silence must never look like safety (principle 3)', () {
    testWidgets('alerts check over an hour old: red on Today, never "no weather alerts"', (tester) async {
      await _pump(tester, _en, FakeWeatherRepository(
        weather: SampleWeather.normal(alertsAge: const Duration(hours: 2)),
      ));
      await _scrollTo(tester, find.byType(WeatherCard));
      expect(_inCard(find.textContaining("Couldn't check weather alerts since")), findsOneWidget);
      await _openWeather(tester, AppLanguage.en);
      expect(find.textContaining("Couldn't check weather alerts since"), findsOneWidget);
      expect(find.text('No weather alerts for Témiscaming.'), findsNothing);
    });

    testWidgets('a reading over 3 hours old hides the temperature', (tester) async {
      await _pump(tester, _en, FakeWeatherRepository(
        weather: SampleWeather.normal(conditions: SampleWeather.reading(age: const Duration(hours: 4))),
      ));
      await _scrollTo(tester, find.byType(WeatherCard));
      expect(_inCard(find.text('No recent reading from the station.')), findsOneWidget);
      expect(find.text('2°C'), findsNothing);
      // The forecast still shows.
      expect(_inCard(find.textContaining('Today: Cloudy')), findsOneWidget);
    });

    testWidgets('backend never run: says so, no "no weather alerts"', (tester) async {
      await _pump(tester, _en, FakeWeatherRepository(useDefault: false));
      await _scrollTo(tester, find.byType(WeatherCard));
      expect(_inCard(find.text("The weather hasn't been checked yet.")), findsOneWidget);
      await _openWeather(tester, AppLanguage.en);
      expect(find.text("Weather alerts haven't been checked yet."), findsOneWidget);
      expect(find.text('No weather alerts for Témiscaming.'), findsNothing);
      expect(find.text('No forecast available yet.'), findsOneWidget);
    });

    testWidgets('weather that can\'t load says so', (tester) async {
      await _pump(tester, _en, FakeWeatherRepository(useDefault: false, failed: true));
      await _scrollTo(tester, find.byType(WeatherCard));
      expect(_inCard(find.text("Couldn't load the weather.")), findsOneWidget);
    });

    testWidgets('forecast over 8 hours old: red line under the forecast', (tester) async {
      await _pump(tester, _en, FakeWeatherRepository(
        weather: SampleWeather.normal(forecastAge: const Duration(hours: 9)),
      ));
      await _openWeather(tester, AppLanguage.en);
      await _scrollTo(tester, find.textContaining("Couldn't update the forecast since"));
    });
  });
}
