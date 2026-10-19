import 'package:community/app.dart';
import 'package:community/l10n/app_localizations.dart';
import 'package:community/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Starts the app as if on a device whose saved settings are [savedPrefs]
/// (empty = fresh install). Returns the settings object so tests can check it.
Future<AppSettings> pumpApp(
  WidgetTester tester, [
  Map<String, Object> savedPrefs = const {},
]) async {
  SharedPreferences.setMockInitialValues(savedPrefs);
  final settings = await AppSettings.load();
  await tester.pumpWidget(TemiscamingApp(settings: settings));
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
