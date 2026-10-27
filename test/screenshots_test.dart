// Renders each screen to a PNG with real fonts, for visual review.
// Not a pass/fail check: CI runs this with --update-goldens and uploads
// test/screenshots/ as a downloadable artifact.
@Tags(['screenshots'])
library;

import 'dart:async';
import 'dart:io';

import 'package:community/alerts/alert_widgets.dart';
import 'package:community/alerts/town_alert.dart';
import 'package:community/collection/collection_card.dart';
import 'package:community/collection/pickup.dart';
import 'package:community/events/event_widgets.dart';
import 'package:community/events/town_event.dart';
import 'package:community/fire/fire_data.dart';
import 'package:community/fire/fire_widgets.dart';
import 'package:community/l10n/app_localizations.dart';
import 'package:community/power/power_screen.dart';
import 'package:community/power/power_widgets.dart';
import 'package:community/roads/roads_screen.dart';
import 'package:community/roads/roads_widgets.dart';
import 'package:community/settings/app_settings.dart';
import 'package:community/weather/weather_card.dart';
import 'package:community/weather/weather_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'collection_fakes.dart';
import 'events_fakes.dart';
import 'fakes.dart';
import 'fire_fakes.dart';
import 'helpers.dart';
import 'power_fakes.dart';
import 'roads_fakes.dart';
import 'weather_fakes.dart';

/// Tests normally draw text as blocks; load the real Roboto and icon fonts
/// that ship with the Flutter SDK so the screenshots are readable.
Future<void> _loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    fail('Set FLUTTER_ROOT to the Flutter SDK folder to take screenshots.');
  }
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  final files = dir.listSync().whereType<File>().toList();
  ByteData bytesOf(File f) => ByteData.sublistView(f.readAsBytesSync());

  final roboto = FontLoader('Roboto');
  for (final f in files.where((f) => _name(f).startsWith('Roboto-'))) {
    roboto.addFont(Future.value(bytesOf(f)));
  }
  await roboto.load();

  final icons = FontLoader('MaterialIcons');
  for (final f in files.where((f) => _name(f).startsWith('MaterialIcons'))) {
    icons.addFont(Future.value(bytesOf(f)));
  }
  await icons.load();
}

String _name(File f) => f.uri.pathSegments.last;

Future<void> _capture(String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('screenshots/$name.png'),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadRealFonts();
  });

  void phone(WidgetTester tester, {double textScale = 1}) {
    tester.view.physicalSize = const Size(780, 1688); // 390×844 at 2×
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  for (final language in AppLanguage.values) {
    final code = language.name;

    testWidgets('screens in $code', (tester) async {
      phone(tester);
      final strings = stringsFor(language);

      await pumpApp(tester);
      await _capture('1_language');

      await scrollAndTap(tester, find.text(strings.languageName));
      await _capture('${code}_2_sector');

      await scrollAndTap(tester, find.text(strings.sectorTownName));
      await _capture('${code}_3_today');

      await tester.tap(find.byTooltip(strings.settingsTitle));
      await tester.pumpAndSettle();
      await _capture('${code}_4_settings');
    });

    testWidgets('alert screens in $code', (tester) async {
      phone(tester);
      final strings = stringsFor(language);
      final alerts = FakeAlertsRepository(alerts: [
        SampleAlerts.boilWater(),
        SampleAlerts.liftingNotice(),
        SampleAlerts.boilWater(id: 'old', status: AlertStatus.lifted, age: const Duration(days: 20)),
        SampleAlerts.frenchOnly(),
      ]);
      final push = FakePushService(isSupported: true);
      await pumpApp(tester, {'language': code, 'sector': 'town'}, alerts, push);
      await _capture('${code}_6_notifications');

      await scrollAndTap(tester, find.text(strings.notificationsAllow));
      await _capture('${code}_7_today_boil_water');

      await tester.tap(find.widgetWithText(NavigationDestination, strings.alertsTitle));
      await tester.pumpAndSettle();
      await _capture('${code}_8_alerts');

      final frenchOnly = find.text(SampleAlerts.frenchOnly().titleFr);
      await tester.scrollUntilVisible(frenchOnly, 200, scrollable: find.byType(Scrollable).hitTestable().first);
      await scrollAndTap(tester, frenchOnly);
      await _capture('${code}_9_alert_detail_french_only');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(SourceHealthLine), -200, scrollable: find.byType(Scrollable).hitTestable().first);

      alerts.set(health: SourceHealth(
        lastSuccessAt: DateTime(2026, 10, 19, 14, 20),
        lastAttemptAt: DateTime.now(),
      ));
      await tester.pumpAndSettle();
      await _capture('${code}_10_alerts_source_stale');

      // Settings on a phone: the notification switches and reminder time.
      await tester.tap(find.byTooltip(strings.settingsTitle).hitTestable());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(strings.settingsCollectionChanges), 200,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await _capture('${code}_14_settings_notifications');
    });

    testWidgets('collection screens in $code', (tester) async {
      phone(tester);
      final collection = FakeCollectionRepository(pickups: SamplePickups.aroundToday());
      await pumpApp(tester, {'language': code, 'sector': 'town'}, null, null, collection);
      await _capture('${code}_11_today_collection');

      await scrollAndTap(tester, find.byType(CollectionCard));
      await _capture('${code}_12_schedule');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Nothing posted beyond tomorrow, and the calendar not checked for hours.
      collection.set(
        pickups: SamplePickups.aroundToday().take(1).toList(),
        health: CollectionHealth(
          lastSuccessAt: DateTime.now().subtract(const Duration(hours: 9)),
          knownThrough: DateTime.now().add(const Duration(days: 1)),
        ),
      );
      await tester.pumpAndSettle();
      await _capture('${code}_13_today_collection_stale');
    });

    testWidgets('event screens in $code', (tester) async {
      phone(tester);
      final strings = stringsFor(language);
      final events = FakeEventsRepository(events: SampleEvents.all());
      final collection = FakeCollectionRepository(pickups: SamplePickups.aroundToday());
      await pumpApp(tester, {'language': code, 'sector': 'town'}, null, null, collection, null, events);
      await tester.scrollUntilVisible(find.text(strings.eventsCardTitle), 200,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await _capture('${code}_15_today_events');

      await tester.tap(find.widgetWithText(NavigationDestination, strings.eventsTitle));
      await tester.pumpAndSettle();
      await _capture('${code}_16_events');

      final show = SampleEvents.show();
      await scrollAndTap(tester, find.text(language == AppLanguage.fr ? show.titleFr : show.titleEn));
      await _capture('${code}_17_event_detail');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      final untitled = find.text(strings.eventCategoryCouncil);
      await tester.scrollUntilVisible(untitled, 200, scrollable: find.byType(Scrollable).hitTestable().first);
      await scrollAndTap(tester, untitled);
      await _capture('${code}_18_event_detail_untitled');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      events.set(health: EventsHealth(lastSuccessAt: DateTime.now().subtract(const Duration(hours: 9))));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(EventsHealthLine), -200,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await _capture('${code}_19_events_stale');
    });

    testWidgets('weather screens in $code', (tester) async {
      phone(tester);
      final strings = stringsFor(language);
      final weather = FakeWeatherRepository(weather: SampleWeather.normal(
        alerts: [SampleWeather.frostAdvisory(), SampleWeather.specialStatement()],
      ));
      final collection = FakeCollectionRepository(pickups: SamplePickups.aroundToday());
      await pumpApp(tester, {'language': code, 'sector': 'town'}, null, null, collection, null, null, null, weather);
      await _capture('${code}_20_today_weather_alert');

      await tester.scrollUntilVisible(find.byType(WeatherCard), 200,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await _capture('${code}_21_today_weather_card');

      await scrollAndTap(tester, find.byType(WeatherAlertBanner));
      await _capture('${code}_22_weather');
      await tester.scrollUntilVisible(find.text(strings.weatherForecastHeading), 300,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await _capture('${code}_23_weather_forecast');
      await tester.scrollUntilVisible(find.text(strings.weatherOpenMeteoLink), 300,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await _capture('${code}_24_weather_sources');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // No alerts, but the alerts check is 2 hours old and the station quiet.
      weather.set(SampleWeather.normal(
        alertsAge: const Duration(hours: 2),
        conditions: SampleWeather.reading(age: const Duration(hours: 5)),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(WeatherCard), 200,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await _capture('${code}_25_today_weather_stale');
    });

    testWidgets('fire screens in $code', (tester) async {
      phone(tester);
      final strings = stringsFor(language);
      final fire = FakeFireRepository(status: SampleFire.banStarted());
      final collection = FakeCollectionRepository(pickups: SamplePickups.aroundToday());
      await pumpApp(tester, {'language': code, 'sector': 'town'}, null, null, collection, null, null, null, null, fire);
      await _capture('${code}_26_today_fire_ban');

      await scrollAndTap(tester, find.byType(FireBanBanner));
      await _capture('${code}_27_fire');
      await tester.scrollUntilVisible(find.text(strings.fireSource), 300,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await _capture('${code}_28_fire_sources');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Today's real state: the small card (shown only in fire season).
      if (isFireSeason(DateTime.now())) {
        fire.set(SampleFire.none());
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.byType(FireCard), 200,
            scrollable: find.byType(Scrollable).hitTestable().first);
        await _capture('${code}_29_today_fire_card');
      }

      // Announced for tomorrow, and the ministry's service down for 3 hours.
      fire.set(SampleFire.banAnnounced());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(FireBanBanner), -200,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await _capture('${code}_30_today_fire_announced');
      fire.set(SampleFire.none(checkedAge: const Duration(hours: 3)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(FireCard), 200,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await _capture('${code}_31_today_fire_stale');
    });

    testWidgets('fire-ban offer in $code', (tester) async {
      phone(tester);
      final push = FakePushService(isSupported: true);
      final collection = FakeCollectionRepository(pickups: SamplePickups.aroundToday());
      await pumpApp(tester, {'language': code, 'sector': 'town', 'water_alerts': true}, null, push, collection);
      await _capture('${code}_32_today_fire_offer');
    });

    testWidgets('roads screens in $code', (tester) async {
      phone(tester);
      final strings = stringsFor(language);
      final collection = FakeCollectionRepository(pickups: SamplePickups.aroundToday());
      // A bad day: both roads closed, ice and snow, roadwork, the Town's work.
      final roads = FakeRoadsRepository(
        items: [
          SampleRoads.closure101(), SampleRoads.closure63(), SampleRoads.plannedClosure(),
          SampleRoads.roadwork101(), SampleRoads.townFlushing(),
        ],
        conditions: SampleRoads.winterStorm(),
      );
      final push = FakePushService(isSupported: true);
      await pumpApp(tester, {'language': code, 'sector': 'town', 'water_alerts': true, 'fire_bans': true},
          null, push, collection, null, null, null, null, null, roads);
      await _capture('${code}_33_today_roads');
      await scrollAndTap(tester, find.byType(RoadsCard));
      await _capture('${code}_34_roads_bad_day');
      await tester.scrollUntilVisible(find.text(strings.roadsHighway63Heading), 300,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await _capture('${code}_35_roads_highway63');
      await tester.scrollUntilVisible(find.text(strings.roadsTownSource), 300,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await _capture('${code}_36_roads_town_sources');
      final closure = find.text(language == AppLanguage.fr
          ? 'Route fermée à Saint-Édouard-de-Fabre'
          : 'Road closed at Saint-Édouard-de-Fabre');
      await tester.scrollUntilVisible(closure, -300, scrollable: find.byType(Scrollable).hitTestable().first);
      await scrollAndTap(tester, closure);
      await _capture('${code}_37_road_item');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Checks failing: Today says so.
      roads.set(items: const [], conditions: SampleRoads.bareAndDry(), lastSuccess: SampleRoads.checked(age: const Duration(hours: 2)));
      await tester.pumpAndSettle();
      await _capture('${code}_38_today_roads_stale');

      await tester.tap(find.widgetWithText(NavigationDestination, strings.moreTitle));
      await tester.pumpAndSettle();
      await _capture('${code}_39_more');
    });

    testWidgets('roads, a quiet day with cameras, in $code', (tester) async {
      phone(tester);
      // Decode the stand-in image for real before any screen asks for it, so
      // the picture shows instead of "Loading" (decoding needs real time).
      await tester.runAsync(() async {
        final done = Completer<void>();
        final stream = testCameraImage.resolve(ImageConfiguration.empty);
        stream.addListener(ImageStreamListener(
          (_, _) { if (!done.isCompleted) done.complete(); },
          onError: (_, _) { if (!done.isCompleted) done.complete(); },
        ));
        await done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
      });
      SharedPreferences.setMockInitialValues({'language': code, 'sector': 'town'});
      final settings = await AppSettings.load();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: language.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: RoadsScreen(
          settings: settings,
          repository: FakeRoadsRepository(items: [SampleRoads.townFlushing()], cameras: SampleRoads.cameras()),
          push: FakePushService(isSupported: true),
          cameraImage: (_) => testCameraImage,
        ),
      ));
      await tester.pumpAndSettle();
      await _capture('${code}_40_roads_quiet');
      // Build the camera rows, then bring the Cameras heading to the top.
      await tester.dragUntilVisible(find.byType(CameraViewTile).first, find.byType(ListView), const Offset(0, -300));
      await tester.ensureVisible(find.text(stringsFor(language).roadsCamerasHeading));
      await tester.pumpAndSettle();
      await _capture('${code}_41_roads_cameras');
    });

    testWidgets('power outages in $code', (tester) async {
      phone(tester);
      final strings = stringsFor(language);
      final collection = FakeCollectionRepository(pickups: SamplePickups.aroundToday());
      // A storm: an outage in town, planned work under way, Lac Tee, planned work tomorrow.
      final power = FakePowerRepository(status: SamplePower.stormDay());
      final push = FakePushService(isSupported: true);
      await pumpApp(tester, {'language': code, 'sector': 'town', 'water_alerts': true, 'fire_bans': true},
          null, push, collection, null, null, null, null, null, null, power);
      await _capture('${code}_42_today_power');
      await scrollAndTap(tester, find.byType(PowerCard));
      await _capture('${code}_43_power_storm');
      await tester.scrollUntilVisible(find.text(strings.powerPlannedHeading), 300,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await _capture('${code}_44_power_planned');
      await tester.scrollUntilVisible(find.text(strings.powerSource), 300,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await _capture('${code}_45_power_about');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Check failing: Today says so; the screen keeps the last outage.
      power.set(PowerStatusSamples.staleWithOutage());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(PowerCard), 200,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await _capture('${code}_46_today_power_stale');
    });

    testWidgets('power outages, a quiet day, in $code', (tester) async {
      phone(tester);
      SharedPreferences.setMockInitialValues({'language': code, 'sector': 'town'});
      final settings = await AppSettings.load();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: language.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: PowerScreen(settings: settings, repository: FakePowerRepository(), push: FakePushService(isSupported: true)),
      ));
      await tester.pumpAndSettle();
      await _capture('${code}_47_power_quiet');
    });

    testWidgets('sector screen at 200% text in $code', (tester) async {
      phone(tester, textScale: 2);
      await pumpApp(tester);
      await scrollAndTap(tester, find.text(stringsFor(language).languageName));
      await _capture('${code}_5_sector_200pct');
    });
  }

  testWidgets('language screen at 200% text', (tester) async {
    phone(tester, textScale: 2);
    await pumpApp(tester);
    await _capture('1_language_200pct');
  });
}
