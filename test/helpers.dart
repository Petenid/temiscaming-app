import 'package:community/app.dart';
import 'package:community/l10n/app_localizations.dart';
import 'package:community/services.dart';
import 'package:community/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'collection_fakes.dart';
import 'events_fakes.dart';
import 'fakes.dart';

/// Starts the app as if on a device whose saved settings are [savedPrefs]
/// (empty = fresh install). Returns the settings object so tests can check it.
///
/// By default the app gets fake alerts (none) and a push service that isn't
/// supported (like a desktop), so the notifications step is skipped.
Future<AppSettings> pumpApp(
  WidgetTester tester, [
  Map<String, Object> savedPrefs = const {},
  FakeAlertsRepository? alerts,
  FakePushService? push,
  FakeCollectionRepository? collection,
  FakeReminderService? reminders,
  FakeEventsRepository? events,
  FakeCalendarAdder? calendar,
]) async {
  SharedPreferences.setMockInitialValues(savedPrefs);
  final settings = await AppSettings.load();
  await tester.pumpWidget(
    TemiscamingApp(
      settings: settings,
      services: AppServices(
        alerts: alerts ?? FakeAlertsRepository(),
        collection: collection ?? FakeCollectionRepository(),
        push: push ?? FakePushService(),
        reminders: reminders ?? FakeReminderService(),
        events: events ?? FakeEventsRepository(),
        calendar: calendar ?? FakeCalendarAdder(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return settings;
}

/// The strings for [language], so tests never hard-code translations.
AppLocalizations stringsFor(AppLanguage language) =>
    lookupAppLocalizations(language.locale);

/// Scrolls [finder] into view (needed at large text sizes), then taps it.
Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
