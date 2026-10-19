import 'package:community/home/today_screen.dart';
import 'package:community/settings/app_settings.dart';
import 'package:community/settings/sector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  testWidgets('fresh install shows the language screen in both languages', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('Choisissez votre langue'), findsOneWidget);
    expect(find.text('Choose your language'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Français'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'English'), findsOneWidget);
    expect(find.byType(TodayScreen), findsNothing);
  });

  testWidgets('the two language buttons are the same size', (tester) async {
    await pumpApp(tester);
    final french = find.widgetWithText(FilledButton, 'Français');
    final english = find.widgetWithText(FilledButton, 'English');
    expect(tester.getSize(french), tester.getSize(english));
  });

  for (final language in AppLanguage.values) {
    testWidgets('first launch in ${language.name}: language → sector → Today', (
      tester,
    ) async {
      final settings = await pumpApp(tester);
      final strings = stringsFor(language);

      await scrollAndTap(tester, find.text(strings.languageName));
      expect(find.text(strings.sectorPrompt), findsOneWidget);
      expect(find.text(strings.sectorTownName), findsOneWidget);
      expect(find.text(strings.sectorLumsdenName), findsOneWidget);

      await scrollAndTap(tester, find.text(strings.sectorTownName));
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, strings.todayTitle), findsOneWidget);

      expect(settings.language, language);
      expect(settings.sector, Sector.town);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('language'), language.name);
      expect(prefs.getString('sector'), 'town');
    });
  }

  testWidgets('back on the sector screen returns to the language screen', (
    tester,
  ) async {
    await pumpApp(tester);
    await scrollAndTap(tester, find.text('English'));
    expect(find.text(stringsFor(AppLanguage.en).sectorPrompt), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Choose your language'), findsOneWidget);
    expect(find.text('Choisissez votre langue'), findsOneWidget);
  });

  testWidgets('after first launch, the app opens straight to Today', (
    tester,
  ) async {
    await pumpApp(tester, {'language': 'en', 'sector': 'lumsden'});
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Today'), findsOneWidget);
    expect(find.text('Choose your language'), findsNothing);
  });

  testWidgets('changing language and sector in Settings applies at once', (
    tester,
  ) async {
    final settings = await pumpApp(tester, {
      'language': 'en',
      'sector': 'town',
    });
    final fr = stringsFor(AppLanguage.fr);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    await scrollAndTap(tester, find.text('Français'));
    expect(settings.language, AppLanguage.fr);
    expect(find.text(fr.settingsTitle), findsOneWidget);
    expect(find.text(fr.sectorLumsdenName), findsOneWidget);

    await scrollAndTap(tester, find.text(fr.sectorLumsdenName));
    expect(settings.sector, Sector.lumsden);

    // System back (Android back gesture / Esc key) returns to Today.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, fr.todayTitle), findsOneWidget);
  });
}
