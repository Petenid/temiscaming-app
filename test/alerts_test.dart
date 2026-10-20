// Alerts tab, alert detail and the Today banner (spec §6, §8.3).
import 'package:community/alerts/alert_detail_screen.dart';
import 'package:community/alerts/town_alert.dart';
import 'package:community/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

const _onboarded = {'language': 'en', 'sector': 'town'};
const _onboardedFr = {'language': 'fr', 'sector': 'town'};

Future<void> _openAlertsTab(WidgetTester tester, AppLanguage language) async {
  await tester.tap(find.widgetWithText(NavigationDestination, stringsFor(language).alertsTitle));
  await tester.pumpAndSettle();
}

void main() {
  for (final language in AppLanguage.values) {
    final strings = stringsFor(language);
    final prefs = language == AppLanguage.en ? _onboarded : _onboardedFr;

    testWidgets('alerts list in ${language.name}: titles, labels, sign-up link', (tester) async {
      await pumpApp(tester, prefs, FakeAlertsRepository(alerts: [
        SampleAlerts.liftingNotice(),
        SampleAlerts.boilWater(status: AlertStatus.lifted, age: const Duration(days: 7)),
      ]));
      await _openAlertsTab(tester, language);

      final boil = SampleAlerts.boilWater();
      final lifting = SampleAlerts.liftingNotice();
      expect(find.text(language == AppLanguage.fr ? boil.titleFr : boil.titleEn), findsOneWidget);
      expect(find.text(language == AppLanguage.fr ? lifting.titleFr : lifting.titleEn), findsOneWidget);
      // Our own status label, never the site's "(Alert raised)".
      expect(find.text(strings.alertStatusLifted), findsOneWidget);
      expect(find.textContaining('Alert raised'), findsNothing);
      expect(find.text(strings.alertsSignUp), findsOneWidget);
      expect(find.textContaining(strings.alertsLastChecked('').trim()), findsOneWidget);
    });
  }

  testWidgets('newest alert first', (tester) async {
    await pumpApp(tester, _onboarded, FakeAlertsRepository(alerts: [
      SampleAlerts.liftingNotice(),
      SampleAlerts.boilWater(status: AlertStatus.lifted, age: const Duration(days: 7)),
    ]));
    await _openAlertsTab(tester, AppLanguage.en);
    final first = tester.getTopLeft(find.text(SampleAlerts.liftingNotice().titleEn));
    final second = tester.getTopLeft(find.text(SampleAlerts.boilWater().titleEn));
    expect(first.dy, lessThan(second.dy));
  });

  testWidgets('an unlifted advisory older than 30 days is not shown as in effect', (tester) async {
    await pumpApp(tester, _onboarded, FakeAlertsRepository(alerts: [
      SampleAlerts.boilWater(age: const Duration(days: 45)),
    ]));
    await _openAlertsTab(tester, AppLanguage.en);
    expect(find.text('In effect'), findsNothing);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Today'));
    await tester.pumpAndSettle();
    expect(find.text('Boil-water advisory in effect'), findsNothing);
  });

  group('in effect until the notice runs out (spec §5b)', () {
    testWidgets('a one-day notice past its date is listed without "In effect"', (tester) async {
      await pumpApp(tester, _onboarded, FakeAlertsRepository(alerts: [SampleAlerts.lowPressure()]));
      await _openAlertsTab(tester, AppLanguage.en);
      expect(find.text(SampleAlerts.lowPressure().titleEn), findsOneWidget);
      expect(find.text('In effect'), findsNothing);
    });

    testWidgets('the same notice before its date says "In effect" (${AppLanguage.fr.name})', (tester) async {
      await pumpApp(tester, _onboardedFr, FakeAlertsRepository(
        alerts: [SampleAlerts.lowPressure(endsIn: const Duration(hours: 5))],
      ));
      await _openAlertsTab(tester, AppLanguage.fr);
      expect(find.text('En vigueur'), findsOneWidget);
    });

    test('alerts saved before the backend stored an end fall back to 30 days', () {
      final now = DateTime.now();
      expect(SampleAlerts.boilWater(age: const Duration(days: 29)).isInEffect(now), isTrue);
      expect(SampleAlerts.boilWater(age: const Duration(days: 31)).isInEffect(now), isFalse);
    });

    test('reads in_effect_until and override from Firestore', () {
      final until = DateTime(2026, 9, 22);
      final alert = TownAlert.fromMap('8274', {
        'category': 'other', 'kind': 'advisory', 'status': 'active',
        'published_at': DateTime(2026, 9, 20, 15), 'in_effect_until': until, 'override': 'in-effect',
      });
      expect(alert.inEffectUntil, until);
      expect(alert.manualOverride, AlertOverride.inEffect);
      expect(TownAlert.fromMap('1', {'published_at': until, 'override': 'over'}).manualOverride, AlertOverride.over);
      expect(TownAlert.fromMap('1', {'published_at': until, 'override': 'typo'}).manualOverride, isNull);
      expect(TownAlert.fromMap('1', {'published_at': until}).inEffectUntil, isNull);
    });
  });

  group('manual overrides (spec §5c)', () {
    testWidgets('"over" removes "In effect" and the boil-water banner', (tester) async {
      await pumpApp(tester, _onboarded, FakeAlertsRepository(
        alerts: [SampleAlerts.boilWater(override: AlertOverride.over)],
      ));
      expect(find.text('Boil-water advisory in effect'), findsNothing);
      await _openAlertsTab(tester, AppLanguage.en);
      expect(find.text('In effect'), findsNothing);
    });

    testWidgets('"in-effect" keeps a notice in effect past its date, even if marked lifted', (tester) async {
      await pumpApp(tester, _onboarded, FakeAlertsRepository(alerts: [
        SampleAlerts.lowPressure(override: AlertOverride.inEffect),
        SampleAlerts.boilWater(status: AlertStatus.lifted, override: AlertOverride.inEffect),
      ]));
      expect(find.text('Boil-water advisory in effect'), findsOneWidget);
      await _openAlertsTab(tester, AppLanguage.en);
      expect(find.text('In effect'), findsNWidgets(2));
      expect(find.text('Lifted'), findsNothing);
    });
  });

  group('source health — silence must never look like safety', () {
    testWidgets('stale source shows a red warning on Alerts and Today', (tester) async {
      final repo = FakeAlertsRepository(
        health: SourceHealth(
          lastSuccessAt: DateTime.now().subtract(const Duration(hours: 3)),
          lastAttemptAt: DateTime.now(),
        ),
      );
      await pumpApp(tester, _onboarded, repo);
      expect(find.textContaining("Couldn't check the Town's alerts since"), findsOneWidget);
      await _openAlertsTab(tester, AppLanguage.en);
      expect(find.textContaining("Couldn't check the Town's alerts since"), findsOneWidget);
      // An empty list from a stale source is never presented as "no alerts".
    });

    testWidgets('a source never checked says so', (tester) async {
      await pumpApp(tester, _onboarded, FakeAlertsRepository(
        health: const SourceHealth(lastSuccessAt: null, lastAttemptAt: null),
      ));
      expect(find.text("The Town's alerts haven't been checked yet."), findsOneWidget);
    });

    testWidgets('alerts that cannot load at all say so instead of an empty list', (tester) async {
      await pumpApp(tester, _onboarded, FakeAlertsRepository(failed: true));
      await _openAlertsTab(tester, AppLanguage.en);
      expect(find.text("Couldn't load alerts. Check your internet connection."), findsOneWidget);
      expect(find.text("The Town hasn't posted any alerts."), findsNothing);
    });

    testWidgets('Today says nothing when all is well', (tester) async {
      await pumpApp(tester, _onboarded, FakeAlertsRepository());
      expect(find.textContaining('Last checked'), findsNothing);
      expect(find.textContaining("Couldn't"), findsNothing);
    });
  });

  group('Today banner', () {
    for (final language in AppLanguage.values) {
      testWidgets('boil-water advisory in effect shows the banner (${language.name})', (tester) async {
        final strings = stringsFor(language);
        await pumpApp(
          tester,
          language == AppLanguage.en ? _onboarded : _onboardedFr,
          FakeAlertsRepository(alerts: [SampleAlerts.boilWater()]),
        );
        expect(find.text(strings.bannerBoilTitle), findsOneWidget);
        await tester.tap(find.text(strings.bannerBoilTitle));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDetailScreen), findsOneWidget);
      });
    }

    testWidgets('no banner once lifted, and it disappears live', (tester) async {
      final repo = FakeAlertsRepository(alerts: [SampleAlerts.boilWater()]);
      await pumpApp(tester, _onboarded, repo);
      expect(find.text('Boil-water advisory in effect'), findsOneWidget);
      repo.set(alerts: [SampleAlerts.liftingNotice(), SampleAlerts.boilWater(status: AlertStatus.lifted)]);
      await tester.pumpAndSettle();
      expect(find.text('Boil-water advisory in effect'), findsNothing);
    });
  });

  group('alert detail', () {
    testWidgets('French-only alert for an English user: original text, labelled', (tester) async {
      await pumpApp(tester, _onboarded, FakeAlertsRepository(alerts: [SampleAlerts.frenchOnly()]));
      await _openAlertsTab(tester, AppLanguage.en);
      await tester.tap(find.text('FERMETURE DE RUE - AVENUE MURER'));
      await tester.pumpAndSettle();
      expect(find.text('Available in French only'), findsOneWidget);
      expect(find.text("L'avenue Murer sera fermée à la circulation."), findsOneWidget);
      expect(find.text("This is a summary. Read the full notice on the Town's site."), findsOneWidget);
      expect(find.text("View on the Town's site"), findsOneWidget);
    });

    testWidgets('bilingual alert shows only the user language, no label', (tester) async {
      await pumpApp(tester, _onboardedFr, FakeAlertsRepository(alerts: [SampleAlerts.liftingNotice()]));
      await _openAlertsTab(tester, AppLanguage.fr);
      await tester.tap(find.text("LEVÉE DE L'AVIS D'ÉBULLITION PRÉVENTIF."));
      await tester.pumpAndSettle();
      expect(find.text("L'avis d'ébullition préventif est maintenant levé."), findsOneWidget);
      expect(find.text('The precautionary boil water advisory has been lifted.'), findsNothing);
      expect(find.text('Disponible en anglais seulement'), findsNothing);
      expect(find.text('Disponible en français seulement'), findsNothing);
    });

    testWidgets('tapping a notification opens its alert', (tester) async {
      final push = FakePushService(isSupported: true);
      await pumpApp(
        tester,
        {..._onboarded, 'water_alerts': true},
        FakeAlertsRepository(alerts: [SampleAlerts.boilWater()]),
        push,
      );
      push.tapNotification('8344');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDetailScreen), findsOneWidget);
      expect(find.text(SampleAlerts.boilWater().bodyEn), findsOneWidget);
    });
  });
}
