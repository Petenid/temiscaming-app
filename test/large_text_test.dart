// Every screen must work at 200% system text size on a small phone
// (DESIGN.md §7). A layout overflow makes the test fail.
import 'package:community/alerts/alert_detail_screen.dart';
import 'package:community/alerts/alert_widgets.dart';
import 'package:community/alerts/town_alert.dart';
import 'package:community/collection/collection_card.dart';
import 'package:community/collection/collection_screen.dart';
import 'package:community/events/event_detail_screen.dart';
import 'package:community/events/events_card.dart';
import 'package:community/fire/fire_screen.dart';
import 'package:community/fire/fire_widgets.dart';
import 'package:community/l10n/app_localizations.dart';
import 'package:community/more/more_screen.dart';
import 'package:community/power/power_screen.dart';
import 'package:community/power/power_widgets.dart';
import 'package:community/roads/roads_screen.dart';
import 'package:community/roads/roads_widgets.dart';
import 'package:community/settings/app_settings.dart';
import 'package:community/weather/weather_card.dart';
import 'package:community/weather/weather_screen.dart';
import 'package:community/weather/weather_widgets.dart';
import 'package:flutter/material.dart';
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

/// Like the system back button (Android back gesture, Esc on desktop).
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  for (final language in AppLanguage.values) {
    testWidgets('all screens fit at 200% text (${language.name})', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final strings = stringsFor(language);
      final alerts = FakeAlertsRepository(
        alerts: [
          SampleAlerts.boilWater(),
          SampleAlerts.liftingNotice(),
          SampleAlerts.frenchOnly(),
        ],
        health: SourceHealth(
          lastSuccessAt: DateTime.now().subtract(const Duration(days: 2)),
          lastAttemptAt: DateTime.now(),
        ),
      );
      // A phone, so the notifications step appears too.
      final push = FakePushService(isSupported: true);

      final collection = FakeCollectionRepository(pickups: SamplePickups.aroundToday());
      final events = FakeEventsRepository(events: SampleEvents.all());
      // Every weather alert type, for the longest banner and screen.
      final weather = FakeWeatherRepository(weather: SampleWeather.normal(alerts: [
        SampleWeather.freezingRainWarning(), SampleWeather.frostAdvisory(), SampleWeather.specialStatement(),
      ]));
      // Both fire bans, for the tallest banner (it shows in any season).
      final fire = FakeFireRepository(status: SampleFire.both());
      await pumpApp(tester, const {}, alerts, push, collection, null, events, null, weather, fire);
      expect(tester.takeException(), isNull, reason: 'language screen');

      await scrollAndTap(tester, find.text(strings.languageName));
      expect(tester.takeException(), isNull, reason: 'sector screen');

      await scrollAndTap(tester, find.text(strings.sectorTownName));
      expect(tester.takeException(), isNull, reason: 'notifications screen');

      await scrollAndTap(tester, find.text(strings.notificationsAllow));
      expect(tester.takeException(), isNull, reason: 'Today screen with banner');

      expect(find.byType(BoilWaterBanner), findsOneWidget);
      await scrollAndTap(tester, find.byType(BoilWaterBanner));
      expect(find.byType(AlertDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'alert detail');
      await _back(tester);

      // At 200% the boil-water banner fills the screen, and the list only
      // builds rows near the screen: scroll to the fire banner first.
      // At 200% the banner is taller than the screen: tap its first title.
      final fireTitle = find.descendant(
        of: find.byType(FireBanBanner),
        matching: find.text(strings.fireIfcoName),
      );
      await tester.scrollUntilVisible(fireTitle, 200,
          scrollable: find.byType(Scrollable).hitTestable().first);
      expect(tester.takeException(), isNull, reason: 'Today fire banner');
      await scrollAndTap(tester, fireTitle);
      expect(find.byType(FireScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Fire screen');
      await tester.scrollUntilVisible(find.text(strings.fireSource), 300,
          scrollable: find.byType(Scrollable).hitTestable().first);
      expect(tester.takeException(), isNull, reason: 'Fire screen, sources');
      await _back(tester);

      // Then on to the weather banner.
      await tester.scrollUntilVisible(find.byType(WeatherAlertBanner), 200,
          scrollable: find.byType(Scrollable).hitTestable().first);
      expect(tester.takeException(), isNull, reason: 'Today weather alert banner');
      await scrollAndTap(tester, find.byType(WeatherAlertBanner));
      expect(find.byType(WeatherScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Weather screen');
      await tester.scrollUntilVisible(find.text(strings.weatherOpenMeteoLink), 300,
          scrollable: find.byType(Scrollable).hitTestable().first);
      expect(tester.takeException(), isNull, reason: 'Weather screen, sources');
      await _back(tester);

      await tester.scrollUntilVisible(find.byType(WeatherCard), 200,
          scrollable: find.byType(Scrollable).hitTestable().first);
      expect(tester.takeException(), isNull, reason: 'Today weather card');

      // At 200% the card is far down the list, which only builds rows near
      // the screen, and taller than the space above the bottom bar: scroll
      // until its title is on screen, then tap the title (a tap in the
      // card's middle would land on the navigation bar).
      final cardTitle = find.descendant(
        of: find.byType(CollectionCard),
        matching: find.text(strings.collectionCardTitle),
      );
      await tester.scrollUntilVisible(cardTitle, 200,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await scrollAndTap(tester, cardTitle);
      expect(find.byType(CollectionScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'pickup schedule');
      await _back(tester);

      // The fire card sits between the weather and events cards.
      await tester.scrollUntilVisible(find.byType(FireCard), 200,
          scrollable: find.byType(Scrollable).hitTestable().first);
      expect(tester.takeException(), isNull, reason: 'Today fire card');

      // The "Coming up" card, then on to the Events tab by tapping it.
      final eventsTitle = find.descendant(
        of: find.byType(EventsCard),
        matching: find.text(strings.eventsCardTitle),
      );
      await tester.scrollUntilVisible(eventsTitle, 200,
          scrollable: find.byType(Scrollable).hitTestable().first);
      expect(tester.takeException(), isNull, reason: 'Today events card');
      await scrollAndTap(tester, eventsTitle);
      expect(tester.takeException(), isNull, reason: 'Events screen');

      // A multi-day closure with the longest dates, and the untitled meeting.
      final closed = SampleEvents.townHallClosed();
      await scrollAndTap(tester, find.text(language == AppLanguage.fr ? closed.titleFr : closed.titleEn).hitTestable());
      expect(find.byType(EventDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'event detail (multi-day)');
      await _back(tester);
      final untitled = find.text(strings.eventCategoryCouncil);
      await tester.scrollUntilVisible(untitled, 200, scrollable: find.byType(Scrollable).hitTestable().first);
      await scrollAndTap(tester, untitled);
      expect(tester.takeException(), isNull, reason: 'event detail (untitled)');
      await _back(tester);

      await tester.tap(find.widgetWithText(NavigationDestination, strings.alertsTitle));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Alerts screen');

      // The list builds rows as they scroll into view, so scroll to it first.
      final frenchOnly = find.text(SampleAlerts.frenchOnly().titleFr);
      await tester.scrollUntilVisible(frenchOnly, 200, scrollable: find.byType(Scrollable).hitTestable().first);
      await scrollAndTap(tester, frenchOnly);
      expect(find.byType(AlertDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'French-only alert detail');
      await _back(tester);

      await tester.tap(find.byTooltip(strings.settingsTitle).hitTestable());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Settings screen');
    });
  }

  // Roads (Milestone 7): Today's road card with the most lines, the Roads
  // screen with every kind of item, an item, the More tab.
  for (final language in AppLanguage.values) {
    testWidgets('roads screens fit at 200% text (${language.name})', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final strings = stringsFor(language);
      final roads = FakeRoadsRepository(
        items: [
          SampleRoads.closure101(), SampleRoads.closure63(), SampleRoads.plannedClosure(),
          SampleRoads.roadwork101(), SampleRoads.townFlushing(),
        ],
        conditions: SampleRoads.winterStorm(),
        lastSuccess: {...SampleRoads.checked(), 'on511-events': SampleRoads.ago(const Duration(hours: 2))},
      );
      await pumpApp(
        tester,
        {'language': language.name, 'sector': 'town', 'water_alerts': true, 'fire_bans': true},
        null, FakePushService(isSupported: true), null, null, null, null, null, null, roads,
      );
      final cardTitle = find.descendant(of: find.byType(RoadsCard), matching: find.text(strings.roadsTitle));
      await tester.scrollUntilVisible(cardTitle, 200, scrollable: find.byType(Scrollable).hitTestable().first);
      expect(tester.takeException(), isNull, reason: 'Today road card');
      await scrollAndTap(tester, cardTitle);
      expect(find.byType(RoadsScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Roads screen');
      await tester.scrollUntilVisible(find.text(strings.roadsTownWorkInAlerts), 300,
          scrollable: find.byType(Scrollable).hitTestable().first);
      expect(tester.takeException(), isNull, reason: 'Roads screen, to the end');
      final closure = find.text(language == AppLanguage.fr
          ? 'Route fermée à Saint-Édouard-de-Fabre'
          : 'Road closed at Saint-Édouard-de-Fabre');
      await tester.scrollUntilVisible(closure, -300, scrollable: find.byType(Scrollable).hitTestable().first);
      await scrollAndTap(tester, closure);
      expect(find.byType(RoadItemScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'road item');
      await _back(tester);
      await _back(tester);
      await tester.tap(find.widgetWithText(NavigationDestination, strings.moreTitle));
      await tester.pumpAndSettle();
      expect(find.byType(MoreScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'More tab');
    });

    testWidgets('Highway 63 cameras fit at 200% text (${language.name})', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues({'language': language.name, 'sector': 'town'});
      final settings = await AppSettings.load();
      await tester.pumpWidget(MaterialApp(
        locale: language.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: RoadsScreen(
          settings: settings,
          repository: FakeRoadsRepository(cameras: SampleRoads.cameras()),
          push: FakePushService(),
          cameraImage: (_) => testCameraImage,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(stringsFor(language).roadsCameraCredit), 300,
          scrollable: find.byType(Scrollable).hitTestable().first);
      expect(tester.takeException(), isNull, reason: 'cameras');
    });
  }

  // Power outages (Milestone 8): Today's card with the most lines, the
  // Power outages screen from top to bottom.
  for (final language in AppLanguage.values) {
    testWidgets('power outage screens fit at 200% text (${language.name})', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final strings = stringsFor(language);
      await pumpApp(
        tester,
        {'language': language.name, 'sector': 'town', 'water_alerts': true, 'fire_bans': true},
        null, FakePushService(isSupported: true), null, null, null, null, null, null, null,
        FakePowerRepository(status: SamplePower.stormDay()),
      );
      final cardTitle = find.descendant(of: find.byType(PowerCard), matching: find.text(strings.powerTitle));
      await tester.scrollUntilVisible(cardTitle, 200, scrollable: find.byType(Scrollable).hitTestable().first);
      expect(tester.takeException(), isNull, reason: 'Today outage card');
      await scrollAndTap(tester, cardTitle);
      expect(find.byType(PowerScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Power outages screen');
      await tester.scrollUntilVisible(find.text(strings.powerSource), 300,
          scrollable: find.byType(Scrollable).hitTestable().first);
      expect(tester.takeException(), isNull, reason: 'Power outages screen, to the end');
    });
  }
}
