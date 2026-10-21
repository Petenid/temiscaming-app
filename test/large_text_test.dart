// Every screen must work at 200% system text size on a small phone
// (DESIGN.md §7). A layout overflow makes the test fail.
import 'package:community/alerts/alert_detail_screen.dart';
import 'package:community/alerts/alert_widgets.dart';
import 'package:community/alerts/town_alert.dart';
import 'package:community/collection/collection_card.dart';
import 'package:community/collection/collection_screen.dart';
import 'package:community/events/event_detail_screen.dart';
import 'package:community/events/events_card.dart';
import 'package:community/settings/app_settings.dart';
import 'package:community/weather/weather_card.dart';
import 'package:community/weather/weather_screen.dart';
import 'package:community/weather/weather_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'collection_fakes.dart';
import 'events_fakes.dart';
import 'fakes.dart';
import 'helpers.dart';
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
      await pumpApp(tester, const {}, alerts, push, collection, null, events, null, weather);
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

      expect(find.byType(WeatherAlertBanner), findsOneWidget);
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
}
