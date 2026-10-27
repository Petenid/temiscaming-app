// Power outages in the app (power-outages spec D7, D9, D10, §8 step 2):
// Today's card, the Power outages screen, the More tab, the opt-in switch
// and outage notifications. The principle-3 cases: "no outage" only after a
// recent check, a stale check is said out loud and keeps the last outage
// shown, and an estimate is always called an estimate.
import 'package:community/l10n/app_localizations.dart';
import 'package:community/more/more_screen.dart';
import 'package:community/power/power_data.dart';
import 'package:community/power/power_screen.dart';
import 'package:community/power/power_widgets.dart';
import 'package:community/push/push_service.dart';
import 'package:community/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';
import 'helpers.dart';
import 'power_fakes.dart';

/// Already through first launch and the notifications question (and the fire-ban offer).
const _en = {'language': 'en', 'sector': 'town', 'water_alerts': true, 'fire_bans': true};
const _fr = {'language': 'fr', 'sector': 'town', 'water_alerts': true, 'fire_bans': true};

Future<AppSettings> _pumpApp(WidgetTester tester, Map<String, Object> prefs, FakePowerRepository power, {FakePushService? push}) =>
    pumpApp(tester, prefs, null, push, null, null, null, null, null, null, null, power);

/// The Power outages screen on its own.
Future<AppSettings> _pumpScreen(
  WidgetTester tester,
  AppLanguage language,
  FakePowerRepository power, {
  FakePushService? push,
}) async {
  SharedPreferences.setMockInitialValues({'language': language.name, 'sector': 'town'});
  final settings = await AppSettings.load();
  await tester.pumpWidget(MaterialApp(
    locale: language.locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: PowerScreen(settings: settings, repository: power, push: push ?? FakePushService()),
  ));
  await tester.pumpAndSettle();
  return settings;
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) => tester.scrollUntilVisible(
  finder, 200, scrollable: find.byType(Scrollable).hitTestable().first,
);

void main() {
  group('data', () {
    test('reads the document as the backend writes it', () {
      final s = PowerStatus.fromMap({
        'outages': [
          {
            'kind': 'planned_in_progress', 'customers': 80, 'started_at': DateTime.utc(2026, 10, 27, 18, 5),
            'estimated_end_at': null, 'status': 'on_the_way', 'cause': 'planned_work', 'area': 'lac_tee',
          },
          {'kind': 'outage', 'customers': 12}, // no start: skipped
        ],
        'planned': [
          {
            'notice': '777', 'customers': 63, 'starts_at': DateTime.utc(2026, 10, 29, 12, 30),
            'ends_at': DateTime.utc(2026, 10, 29, 16), 'original_starts_at': DateTime.utc(2026, 10, 28, 12, 30),
            'change': 'postponed', 'alternate_starts_at': DateTime.utc(2026, 11, 5, 13, 30),
            'alternate_ends_at': DateTime.utc(2026, 11, 5, 17), 'area': 'temiscaming',
          },
        ],
        'outages_checked_at': DateTime.utc(2026, 10, 27, 18, 15),
        'planned_checked_at': DateTime.utc(2026, 10, 27, 18),
        'map_url_fr': 'https://example.org/fr',
        'map_url_en': 'not a link',
      });
      expect(s.outages, hasLength(1));
      final o = s.outages.single;
      expect([o.kind, o.customers, o.status, o.cause, o.area, o.estimatedEndAt],
          [OutageKind.plannedInProgress, 80, CrewStatus.onTheWay, OutageCause.plannedWork, PowerArea.lacTee, null]);
      final p = s.planned.single;
      expect([p.customers, p.startsAt, p.originalStartsAt, p.alternateStartsAt],
          [63, DateTime.utc(2026, 10, 29, 12, 30), DateTime.utc(2026, 10, 28, 12, 30), DateTime.utc(2026, 11, 5, 13, 30)]);
      expect(s.mapUrlFr, 'https://example.org/fr');
      expect(s.mapUrlEn, PowerLinks.mapEn, reason: 'only https links are used');
    });

    test('unknown codes: shown as an outage, no status or cause guessed', () {
      final o = Outage.fromMap({
        'kind': 'something_new', 'customers': 5, 'started_at': DateTime.utc(2026, 10, 27), 'status': 'N', 'cause': 'x',
      })!;
      expect([o.kind, o.status, o.cause, o.area], [OutageKind.outage, null, null, PowerArea.temiscaming]);
    });

    test('freshness: an hour for outages, three hours for planned; never read is stale', () {
      final now = DateTime.utc(2026, 10, 27, 18);
      final s = PowerStatus(
        outagesCheckedAt: now.subtract(const Duration(minutes: 61)),
        plannedCheckedAt: now.subtract(const Duration(minutes: 170)),
      );
      expect(s.outagesStale(now), isTrue);
      expect(s.plannedStale(now), isFalse);
      expect(const PowerStatus().outagesStale(now), isTrue);
    });

    test('soon = today or tomorrow, not later, not started', () {
      final s = PowerStatus(planned: [SamplePower.tomorrow(), SamplePower.nextWeek()]);
      expect(s.soon(DateTime.now()), [s.planned.first]);
      expect(s.upcoming(SamplePower.at(9, 0, 1)), [s.planned.last]);
    });
  });

  group('Today', () {
    testWidgets('no card on a quiet day', (tester) async {
      await _pumpApp(tester, _en, FakePowerRepository());
      expect(find.byType(PowerCard), findsNothing);
      expect(find.text('Power outages will appear here soon.'), findsNothing, reason: 'placeholder gone');
    });

    testWidgets('an outage: amber card, three lines and "+1 more", the estimate called an estimate', (tester) async {
      final s = stringsFor(AppLanguage.en);
      await _pumpApp(tester, _en, FakePowerRepository(status: SamplePower.stormDay()));
      final card = find.byType(PowerCard);
      await tester.scrollUntilVisible(card, 200, scrollable: find.byType(Scrollable).hitTestable().first);
      expect(find.descendant(of: card, matching: find.textContaining('Outage: 120 customers since')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining(s.powerNoEstimate)), findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining('Planned interruption in progress: 80 customers')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining("Lac Tee — Outage: 3 customers")), findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining("Hydro-Québec's estimate")), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text(s.powerMore(1))), findsOneWidget);
      await scrollAndTap(tester, card);
      expect(find.byType(PowerScreen), findsOneWidget);
    });

    testWidgets('a planned interruption tomorrow shows; next week doesn\'t', (tester) async {
      await _pumpApp(tester, _fr, FakePowerRepository(status: PowerStatus(
        planned: [SamplePower.tomorrow(), SamplePower.nextWeek()],
        outagesCheckedAt: SamplePower.ago(const Duration(minutes: 5)),
        plannedCheckedAt: SamplePower.ago(const Duration(minutes: 5)),
      )));
      final card = find.byType(PowerCard);
      await tester.scrollUntilVisible(card, 200, scrollable: find.byType(Scrollable).hitTestable().first);
      expect(find.descendant(of: card, matching: find.textContaining('Interruption planifiée : ')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining('Lac Tee')), findsNothing);
    });

    testWidgets('a failing check is said on Today, even with nothing to show', (tester) async {
      final s = stringsFor(AppLanguage.en);
      final power = FakePowerRepository(status: SamplePower.quiet(age: const Duration(hours: 2)));
      await _pumpApp(tester, _en, power);
      final card = find.byType(PowerCard);
      await tester.scrollUntilVisible(card, 200, scrollable: find.byType(Scrollable).hitTestable().first);
      expect(find.descendant(of: card, matching: find.textContaining(s.powerCheckFailedSince('').trim())), findsOneWidget);

      power.set(null); // the backend has never written the document
      await tester.pumpAndSettle();
      expect(find.descendant(of: card, matching: find.text(s.powerNeverChecked)), findsOneWidget);
    });
  });

  group('Power outages screen', () {
    testWidgets('quiet: "no outage" and "no planned interruption", after a recent check only', (tester) async {
      final s = stringsFor(AppLanguage.en);
      await _pumpScreen(tester, AppLanguage.en, FakePowerRepository());
      expect(find.text(s.powerNoOutage), findsOneWidget);
      await _scrollTo(tester, find.text(s.powerNoPlanned));

      await _pumpScreen(tester, AppLanguage.en, FakePowerRepository(never: true));
      expect(find.text(s.powerNoOutage), findsNothing);
      expect(find.text(s.powerNeverChecked), findsWidgets);
    });

    testWidgets('stale: says so, keeps the last outage, never "no outage"', (tester) async {
      final s = stringsFor(AppLanguage.en);
      final status = SamplePower.stormDay();
      await _pumpScreen(tester, AppLanguage.en, FakePowerRepository(status: PowerStatus(
        outages: [status.outages.first],
        outagesCheckedAt: SamplePower.ago(const Duration(hours: 2)), // stale after 1 h
        plannedCheckedAt: SamplePower.ago(const Duration(hours: 4)), // stale after 3 h
      )));
      expect(find.textContaining(s.powerCheckFailedSince('').trim()), findsNWidgets(2));
      expect(find.text(s.powerKindOutage), findsOneWidget);
      expect(find.text(s.powerNoOutage), findsNothing);
      expect(find.text(s.powerNoPlanned), findsNothing);
    });

    testWidgets('planned checked 2 hours ago is still fine (read hourly, stale after 3 h)', (tester) async {
      final s = stringsFor(AppLanguage.en);
      await _pumpScreen(tester, AppLanguage.en, FakePowerRepository(status: SamplePower.quiet(age: const Duration(hours: 2))));
      expect(find.text(s.powerNoOutage), findsNothing, reason: 'outages: stale after 1 h');
      await _scrollTo(tester, find.text(s.powerNoPlanned));
    });

    testWidgets('a storm day: every detail, in French', (tester) async {
      tester.view.physicalSize = const Size(800, 3200); // everything built at once
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = stringsFor(AppLanguage.fr);
      await _pumpScreen(tester, AppLanguage.fr, FakePowerRepository(status: SamplePower.stormDay()));
      expect(find.text(s.powerKindOutage), findsNWidgets(2));
      expect(find.text('120 clients touchés'), findsOneWidget);
      expect(find.text(s.powerCrewOnTheWay), findsOneWidget);
      expect(find.text(s.powerCause(s.powerCauseWeather)), findsOneWidget);
      expect(find.text(s.powerNoEstimate), findsOneWidget);
      expect(find.text(s.powerKindPlannedInProgress), findsOneWidget);
      expect(find.textContaining('Fin prévue : '), findsOneWidget);
      await _scrollTo(tester, find.text(s.powerAreaLacTee).last);
      expect(find.textContaining('Retour du courant estimé par Hydro-Québec : '), findsOneWidget);
      await _scrollTo(tester, find.textContaining('Si elle est reportée : '));
      expect(find.textContaining('Déplacée du '), findsOneWidget);
      await _scrollTo(tester, find.text(s.powerSource));
      expect(find.text(s.powerReport(PowerLinks.reportPhone)), findsOneWidget);
      expect(find.text(s.powerDanger), findsOneWidget);
      expect(find.text(s.powerMapLink), findsOneWidget);
    });

    testWidgets('the notify switch: phones only, off by default, asks permission', (tester) async {
      final s = stringsFor(AppLanguage.en);
      await _pumpScreen(tester, AppLanguage.en, FakePowerRepository());
      expect(find.text(s.powerNotifyTitle), findsNothing, reason: 'desktop: no push');

      final push = FakePushService(isSupported: true);
      final settings = await _pumpScreen(tester, AppLanguage.en, FakePowerRepository(), push: push);
      expect(settings.powerOutagesEnabled, isFalse);
      await tester.tap(find.text(s.powerNotifyTitle));
      await tester.pumpAndSettle();
      expect(push.permissionRequests, 1);
      expect(settings.powerOutagesEnabled, isTrue);

      push.grantPermission = false;
      await tester.tap(find.text(s.powerNotifyTitle)); // off: never asks
      await tester.pumpAndSettle();
      expect(settings.powerOutagesEnabled, isFalse);
      await tester.tap(find.text(s.powerNotifyTitle)); // on, but denied
      await tester.pumpAndSettle();
      expect(settings.powerOutagesEnabled, isFalse);
      expect(find.text(s.settingsPermissionDenied), findsOneWidget);
    });
  });

  group('More tab, settings and notifications', () {
    testWidgets('More lists Power outages, which opens the screen', (tester) async {
      final s = stringsFor(AppLanguage.fr);
      await _pumpApp(tester, _fr, FakePowerRepository());
      await tester.tap(find.widgetWithText(NavigationDestination, s.moreTitle));
      await tester.pumpAndSettle();
      final tile = find.descendant(of: find.byType(MoreScreen), matching: find.text(s.powerTitle));
      expect(tile, findsOneWidget);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.byType(PowerScreen), findsOneWidget);
    });

    testWidgets('power outages stay off when the notifications question is answered yes', (tester) async {
      final push = FakePushService(isSupported: true);
      final settings = await pumpApp(tester, const {'language': 'en', 'sector': 'town'}, null, push);
      await scrollAndTap(tester, find.text(stringsFor(AppLanguage.en).notificationsAllow));
      expect(settings.waterAlertsEnabled, isTrue);
      expect(settings.powerOutagesEnabled, isFalse);
    });

    testWidgets('Settings has the power outages switch', (tester) async {
      final s = stringsFor(AppLanguage.en);
      final push = FakePushService(isSupported: true);
      final settings = await _pumpApp(tester, _en, FakePowerRepository(), push: push);
      await tester.tap(find.byTooltip(s.settingsTitle).first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(s.settingsPowerOutages), 100,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await scrollAndTap(tester, find.text(s.settingsPowerOutages));
      expect(settings.powerOutagesEnabled, isTrue);
    });

    test('PushSync follows the power outages setting', () async {
      SharedPreferences.setMockInitialValues({'language': 'fr', 'sector': 'town', 'water_alerts': true});
      final settings = await AppSettings.load();
      final push = FakePushService(isSupported: true);
      PushSync(settings, push);
      await settings.setPowerOutages(true);
      await settings.setPowerOutages(false);
      expect(push.appliedPower, [false, true, false]);
    });

    test('a push with screen "power" leads to the Power outages screen', () {
      expect(targetOf({'screen': 'power'}), powerTarget);
      expect(powerTopicFor(AppLanguage.fr), 'power-fr');
    });

    testWidgets('a tapped outage notification opens the Power outages screen', (tester) async {
      final push = FakePushService(isSupported: true);
      await _pumpApp(tester, _en, FakePowerRepository(status: SamplePower.stormDay()), push: push);
      push.tapNotification(powerTarget);
      await tester.pumpAndSettle();
      expect(find.byType(PowerScreen), findsOneWidget);
    });
  });
}
