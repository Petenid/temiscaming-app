// Fire bans in the app (fire-bans spec D7–D9, §8 step 2): the red banner,
// the seasonal card, the Fire screen and the notification setting. The
// principle-3 cases: a stale or missing check must never read as "no ban".
import 'dart:io';

import 'package:community/fire/fire_data.dart';
import 'package:community/fire/fire_screen.dart';
import 'package:community/fire/fire_widgets.dart';
import 'package:community/l10n/app_localizations.dart';
import 'package:community/push/push_service.dart';
import 'package:community/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';
import 'fire_fakes.dart';
import 'helpers.dart';

const _en = {'language': 'en', 'sector': 'town'};
const _fr = {'language': 'fr', 'sector': 'town'};

Future<AppSettings> _pumpToday(
  WidgetTester tester,
  Map<String, Object> prefs,
  FakeFireRepository fire, {
  FakePushService? push,
}) => pumpApp(tester, prefs, null, push, null, null, null, null, null, fire);

/// The Fire screen on its own, so tests don't depend on the season (the
/// Today card only shows 1 April – 15 November).
Future<void> _pumpScreen(WidgetTester tester, AppLanguage language, FakeFireRepository fire) async {
  SharedPreferences.setMockInitialValues({'language': language.name, 'sector': 'town'});
  final settings = await AppSettings.load();
  await tester.pumpWidget(MaterialApp(
    locale: language.locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: FireScreen(settings: settings, repository: fire),
  ));
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) => tester.scrollUntilVisible(
  finder, 200, scrollable: find.byType(Scrollable).hitTestable().first,
);

void main() {
  group('data', () {
    test('reads the Firestore document as the backend writes it', () {
      final s = FireStatus.fromMap({
        'ifco': {
          'state': 'none', 'starts_at': null, 'none_since': DateTime.utc(2026, 7, 20, 16), 'nearest_km': null,
          'checked_at': DateTime.utc(2026, 10, 21, 23, 30),
          'pushed': {'kind': 'lifted', 'at': DateTime.utc(2026, 10, 21, 23, 30), 'baseline': true},
        },
        'icaf': {
          'state': 'around', 'starts_at': DateTime.utc(2026, 10, 22, 12), 'none_since': null, 'nearest_km': 4,
          'checked_at': DateTime.utc(2026, 10, 21, 23, 30),
        },
        'official_url_fr': 'https://www.quebec.ca/x',
        'map_url': 'not a link',
      });
      expect(s.ifco!.state, FireLayerState.none);
      expect(s.ifco!.noneSince, DateTime.utc(2026, 7, 20, 16));
      expect(s.ifco!.isHere, isFalse);
      expect(s.icaf!.isHere, isTrue);
      expect(s.icaf!.nearestKm, 4);
      expect(s.here.map((l) => l.layer).toList(), [FireLayer.icaf]);
      expect(s.officialUrlFr, 'https://www.quebec.ca/x');
      expect(s.mapUrl, FireLinks.map, reason: 'anything that isn\'t an https link falls back');
    });

    test('a layer the backend hasn\'t read yet is missing, not "none"', () {
      final s = FireStatus.fromMap({'ifco': {'state': 'none', 'checked_at': DateTime.now()}});
      expect(s.icaf, isNull);
    });

    test('an unknown state is never read as "no ban"', () {
      final s = FireStatus.fromMap({'ifco': {'state': 'partial', 'checked_at': DateTime.now()}});
      expect(s.ifco!.isHere, isTrue);
    });

    test('fire season is 1 April to 15 November', () {
      expect(isFireSeason(DateTime(2026, 3, 31, 23, 59)), isFalse);
      expect(isFireSeason(DateTime(2026, 4, 1)), isTrue);
      expect(isFireSeason(DateTime(2026, 11, 15, 23, 59)), isTrue);
      expect(isFireSeason(DateTime(2026, 11, 16)), isFalse);
      expect(isFireSeason(DateTime(2027, 1, 10)), isFalse);
    });

    test('the Today card: in season always; out of season only for a ban or a problem', () {
      final winter = DateTime(2027, 1, 10, 12);
      final summer = DateTime(2027, 7, 10, 12);
      FakeFireRepository repo(FireStatus? s) => FakeFireRepository(status: s, useDefault: false);
      FireLayerStatus fresh(FireLayer l, FireLayerState st, DateTime at) =>
          FireLayerStatus(layer: l, state: st, checkedAt: at.subtract(const Duration(minutes: 5)));
      FireStatus quiet(DateTime at) => FireStatus(
        ifco: fresh(FireLayer.ifco, FireLayerState.none, at), icaf: fresh(FireLayer.icaf, FireLayerState.none, at),
      );
      expect(FireCard.shows(repo(quiet(summer)), summer), isTrue);
      expect(FireCard.shows(repo(quiet(winter)), winter), isFalse);
      expect(FireCard.shows(repo(FireStatus(
        ifco: fresh(FireLayer.ifco, FireLayerState.region, winter), icaf: fresh(FireLayer.icaf, FireLayerState.none, winter),
      )), winter), isTrue);
      expect(FireCard.shows(repo(quiet(winter.subtract(const Duration(hours: 3)))), winter), isTrue, reason: 'stale');
      expect(FireCard.shows(repo(null), winter), isTrue, reason: 'never checked');
      expect(FireCard.shows(FakeFireRepository(failed: true, useDefault: false), winter), isTrue);
      expect(FireCard.shows(FakeFireRepository(loading: true, useDefault: false), summer), isFalse);
    });

    test('push topics and Android channels match the backend', () {
      expect(fireTopicFor(AppLanguage.fr), 'fire-fr');
      expect(fireTopicFor(AppLanguage.en), 'fire-en');
      final backend = File('functions/src/fire/sync.ts').readAsStringSync();
      expect(backend, contains('fr: "fire-fr", en: "fire-en"'));
      final kotlin = File('android/app/src/main/kotlin/ca/temiscaming/community/MainActivity.kt').readAsStringSync();
      for (final channel in ['fire_urgent', 'fire_updates']) {
        expect(backend, contains('"$channel"'));
        expect(kotlin, contains('"$channel"'));
      }
      expect(targetOf({'screen': 'fire', 'layer': 'ifco'}), fireTarget);
    });
  });

  for (final (prefs, language) in [(_en, AppLanguage.en), (_fr, AppLanguage.fr)]) {
    final strings = stringsFor(language);

    testWidgets('a ban in town: red banner on Today, details on the Fire screen (${language.name})', (tester) async {
      await _pumpToday(tester, prefs, FakeFireRepository(status: SampleFire.banStarted()));
      expect(find.byType(FireBanBanner), findsOneWidget);
      expect(find.descendant(of: find.byType(FireBanBanner), matching: find.text(strings.fireIfcoName)), findsOneWidget);
      expect(find.text(strings.fireBannerIfcoNow), findsOneWidget);

      await scrollAndTap(tester, find.byType(FireBanBanner));
      expect(find.byType(FireScreen), findsOneWidget);
      expect(find.text(strings.fireStateIfcoTown), findsOneWidget);
      expect(find.textContaining(strings.fireSince('').trim()), findsOneWidget);
      expect(find.text(strings.fireIfcoMeaning), findsOneWidget);
      // The forest access ban isn't in effect: said plainly, with the last-lifted date.
      expect(find.text(strings.fireStateIcafNone), findsOneWidget);
      await _scrollTo(tester, find.text(strings.fireSource));
      expect(find.text(strings.fireOfficialLink), findsOneWidget);
      expect(find.text(strings.fireTownRulesNote), findsOneWidget);
    });

    testWidgets('an announced ban shows on Today with its start, never as "in effect" (${language.name})', (tester) async {
      await _pumpToday(tester, prefs, FakeFireRepository(status: SampleFire.banAnnounced()));
      expect(find.textContaining(strings.fireBannerIfcoUpcoming('').trim()), findsOneWidget);
      expect(find.text(strings.fireBannerIfcoNow), findsNothing);
      expect(find.text(strings.fireStateIfcoTown), findsNothing);

      await _pumpScreen(tester, language, FakeFireRepository(status: SampleFire.banAnnounced()));
      expect(find.text(strings.fireStateIfcoAnnounced), findsOneWidget);
      expect(find.text(strings.fireStateIfcoTown), findsNothing);
      expect(find.textContaining(strings.fireStarts('').trim()), findsOneWidget);
    });

    testWidgets('both bans: one banner, both named (${language.name})', (tester) async {
      await _pumpToday(tester, prefs, FakeFireRepository(status: SampleFire.both()));
      expect(find.byType(FireBanBanner), findsOneWidget);
      expect(find.text(strings.fireBannerIfcoNow), findsOneWidget);
      expect(find.text(strings.fireBannerIcafNow), findsOneWidget);
    });

    testWidgets('no ban, fresh check: no banner; the screen says so, with the last-lifted date (${language.name})', (tester) async {
      await _pumpToday(tester, prefs, FakeFireRepository());
      expect(find.byType(FireBanBanner), findsNothing);

      await _pumpScreen(tester, language, FakeFireRepository());
      expect(find.text(strings.fireStateIfcoNone), findsOneWidget);
      expect(find.text(strings.fireStateIcafNone), findsOneWidget);
      expect(find.textContaining(strings.fireNoneInQuebecSince('').trim()), findsNWidgets(2));
      // Below the two bans: the list only builds what's near the screen.
      await _scrollTo(tester, find.textContaining(strings.fireCheckedAt('').trim()));
      expect(find.textContaining(strings.fireCheckedAt('').trim()), findsOneWidget);
    });

    testWidgets('a ban elsewhere in the region: no banner, shown with its distance (${language.name})', (tester) async {
      await _pumpToday(tester, prefs, FakeFireRepository(status: SampleFire.region()));
      expect(find.byType(FireBanBanner), findsNothing);
      await _pumpScreen(tester, language, FakeFireRepository(status: SampleFire.region()));
      expect(find.text(strings.fireStateRegion('131')), findsOneWidget);
    });

    testWidgets('a stale check never says "no ban" (${language.name})', (tester) async {
      await _pumpScreen(tester, language, FakeFireRepository(status: SampleFire.none(checkedAge: const Duration(hours: 3))));
      expect(find.text(strings.fireStateIfcoNone), findsNothing);
      expect(find.text(strings.fireStateIcafNone), findsNothing);
      expect(find.textContaining(strings.fireCheckFailedSince('').trim()), findsWidgets);
    });

    testWidgets('a stale check keeps showing the last known ban, with a warning (${language.name})', (tester) async {
      final fire = FakeFireRepository(status: SampleFire.banStarted(checkedAge: const Duration(hours: 3)));
      await _pumpToday(tester, prefs, fire);
      expect(find.byType(FireBanBanner), findsOneWidget);
      await _pumpScreen(tester, language, fire);
      expect(find.text(strings.fireStateIfcoTown), findsOneWidget);
      expect(find.textContaining(strings.fireCheckFailedSince('').trim()), findsWidgets);
    });

    testWidgets('never checked and load failure are problems, not silence (${language.name})', (tester) async {
      await _pumpScreen(tester, language, FakeFireRepository(useDefault: false));
      expect(find.text(strings.fireNeverChecked), findsWidgets);
      await _pumpScreen(tester, language, FakeFireRepository(useDefault: false, failed: true));
      await _scrollTo(tester, find.text(strings.fireLoadFailed));
      expect(find.text(strings.fireLoadFailed), findsOneWidget);
    });
  }

  group('notifications', () {
    testWidgets('first launch: answering yes turns fire bans on, and no offer appears', (tester) async {
      final push = FakePushService(isSupported: true);
      final settings = await _pumpToday(tester, const {}, FakeFireRepository(), push: push);
      final strings = stringsFor(AppLanguage.en);
      await scrollAndTap(tester, find.text(strings.languageName));
      await scrollAndTap(tester, find.text(strings.sectorTownName));
      await scrollAndTap(tester, find.text(strings.notificationsAllow));
      expect(settings.fireBansEnabled, isTrue);
      expect(find.byType(FireOptInCard), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('fire_bans'), isTrue);
    });

    testWidgets('installed before fire bans: offered once on Today; "Turn on" asks and saves', (tester) async {
      final push = FakePushService(isSupported: true);
      final settings = await _pumpToday(tester, {..._en, 'water_alerts': true}, FakeFireRepository(), push: push);
      expect(settings.fireBansEnabled, isFalse);
      expect(find.byType(FireOptInCard), findsOneWidget);
      await scrollAndTap(tester, find.text(stringsFor(AppLanguage.en).fireOptInYes));
      expect(push.permissionRequests, 1);
      expect(settings.fireBansEnabled, isTrue);
      expect(find.byType(FireOptInCard), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('fire_bans'), isTrue);
    });

    testWidgets('"No thanks" hides the offer for good without asking the system', (tester) async {
      final push = FakePushService(isSupported: true);
      final settings = await _pumpToday(tester, {..._fr, 'water_alerts': false}, FakeFireRepository(), push: push);
      await scrollAndTap(tester, find.text(stringsFor(AppLanguage.fr).fireOptInNo));
      expect(push.permissionRequests, 0);
      expect(settings.fireBansEnabled, isFalse);
      expect(settings.fireBansToOffer, isFalse);
      expect(find.byType(FireOptInCard), findsNothing);
    });

    testWidgets('desktop: no offer (no push there)', (tester) async {
      await _pumpToday(tester, {..._en, 'water_alerts': true}, FakeFireRepository());
      expect(find.byType(FireOptInCard), findsNothing);
    });

    testWidgets('the Settings switch turns fire bans on and off', (tester) async {
      final push = FakePushService(isSupported: true);
      final settings = await _pumpToday(
        tester, {..._en, 'water_alerts': true, 'fire_bans': false}, FakeFireRepository(), push: push,
      );
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      final toggle = find.text(stringsFor(AppLanguage.en).settingsFireBans);
      await scrollAndTap(tester, toggle);
      expect(settings.fireBansEnabled, isTrue);
      await scrollAndTap(tester, toggle);
      expect(settings.fireBansEnabled, isFalse);
    });

    testWidgets('tapping a fire-ban notification opens the Fire screen', (tester) async {
      final push = FakePushService(isSupported: true);
      await _pumpToday(tester, {..._en, 'water_alerts': true, 'fire_bans': true}, FakeFireRepository(status: SampleFire.banStarted()), push: push);
      push.tapNotification(fireTarget);
      await tester.pumpAndSettle();
      expect(find.byType(FireScreen), findsOneWidget);
    });

    test('PushSync follows the fire bans setting', () async {
      SharedPreferences.setMockInitialValues({'language': 'fr', 'sector': 'town', 'water_alerts': true, 'fire_bans': true});
      final settings = await AppSettings.load();
      final push = FakePushService(isSupported: true);
      PushSync(settings, push);
      await settings.setFireBans(false);
      expect(push.appliedFire, [true, false]);
    });
  });
}
