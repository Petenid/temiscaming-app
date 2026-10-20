// Every screen must work at 200% system text size on a small phone
// (DESIGN.md §7). A layout overflow makes the test fail.
import 'package:community/alerts/alert_detail_screen.dart';
import 'package:community/alerts/alert_widgets.dart';
import 'package:community/alerts/town_alert.dart';
import 'package:community/collection/collection_card.dart';
import 'package:community/collection/collection_screen.dart';
import 'package:community/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'collection_fakes.dart';
import 'fakes.dart';
import 'helpers.dart';

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
      await pumpApp(tester, const {}, alerts, push, collection);
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

      await scrollAndTap(tester, find.byType(CollectionCard));
      expect(find.byType(CollectionScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'pickup schedule');
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
