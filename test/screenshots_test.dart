// Renders each screen to a PNG with real fonts, for visual review.
// Not a pass/fail check: CI runs this with --update-goldens and uploads
// test/screenshots/ as a downloadable artifact.
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:community/alerts/alert_widgets.dart';
import 'package:community/alerts/town_alert.dart';
import 'package:community/collection/collection_card.dart';
import 'package:community/collection/pickup.dart';
import 'package:community/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'collection_fakes.dart';
import 'fakes.dart';
import 'helpers.dart';

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
