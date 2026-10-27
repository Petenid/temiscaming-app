// Roads in the app (roads spec D9–D13, §8 step 2): Today's road card, the
// Roads screen, the More tab, the opt-in switch and road notifications.
// The principle-3 cases: "nothing reported" only after a recent check, a
// stale check is said out loud, "No report" is never "clear", and a planned
// closure is never "in effect".
import 'package:community/l10n/app_localizations.dart';
import 'package:community/more/more_screen.dart';
import 'package:community/push/push_service.dart';
import 'package:community/roads/road_data.dart';
import 'package:community/roads/roads_repository.dart';
import 'package:community/roads/roads_screen.dart';
import 'package:community/roads/roads_widgets.dart';
import 'package:community/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';
import 'helpers.dart';
import 'roads_fakes.dart';

/// Already through first launch and the notifications question (and the fire-ban offer).
const _en = {'language': 'en', 'sector': 'town', 'water_alerts': true, 'fire_bans': true};
const _fr = {'language': 'fr', 'sector': 'town', 'water_alerts': true, 'fire_bans': true};

Future<AppSettings> _pumpApp(WidgetTester tester, Map<String, Object> prefs, FakeRoadsRepository roads, {FakePushService? push}) =>
    pumpApp(tester, prefs, null, push, null, null, null, null, null, null, roads);

/// The Roads screen on its own.
Future<AppSettings> _pumpScreen(
  WidgetTester tester,
  AppLanguage language,
  FakeRoadsRepository roads, {
  FakePushService? push,
}) async {
  SharedPreferences.setMockInitialValues({'language': language.name, 'sector': 'town'});
  final settings = await AppSettings.load();
  await tester.pumpWidget(MaterialApp(
    locale: language.locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: RoadsScreen(
      settings: settings,
      repository: roads,
      push: push ?? FakePushService(),
      cameraImage: (_) => testCameraImage,
    ),
  ));
  await tester.pumpAndSettle();
  return settings;
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) => tester.scrollUntilVisible(
  finder, 200, scrollable: find.byType(Scrollable).hitTestable().first,
);

void main() {
  group('data', () {
    test('reads an item as the backend writes it', () {
      final item = RoadItem.fromMap({
        'id': 'qc-warning-900001', 'source': 'mtmd-warnings', 'kind': 'closure', 'road': '101',
        'place': 'Saint-Édouard-de-Fabre', 'title_fr': 'Route fermée', 'title_en': 'Road closed',
        'body_fr': 'R-101 …', 'body_en': '', 'original_language': 'fr',
        'source_url_fr': RoadLinks.quebec511Fr, 'source_url_en': RoadLinks.quebec511En,
        'published_at': DateTime.utc(2026, 11, 3, 11, 40), 'starts_at': DateTime.utc(2026, 11, 3, 11, 40),
        'ends_at': null, 'status': 'in_effect', 'on_today': true,
      })!;
      expect(item.road, Road.route101);
      expect(item.kind, RoadItemKind.closure);
      expect(item.title(AppLanguage.en), 'Road closed');
      expect(item.displayLanguage(AppLanguage.en), AppLanguage.fr, reason: 'French-only text is never translated');
      expect(item.body(AppLanguage.en), 'R-101 …');
      expect(RoadItem.fromMap({'id': 'x', 'kind': 'mystery'}), isNull);
      expect(RoadItem.fromMap({'id': 'x', 'kind': 'closure', 'on_today': false})!.onToday, isTrue,
          reason: 'a closure always goes on Today');
    });

    test('conditions: snow, ice, poor visibility and drifting are flagged; "No report" and unclear values are handled', () {
      final c = RoadConditions.fromMap({
        'segments': [
          {'from_en': 'A', 'to_en': 'B', 'surface_ok': true, 'visibility_ok': true, 'drifting': false},
          {'from_en': 'B', 'to_en': 'C', 'surface_ok': false, 'visibility_ok': true},
          {'from_en': 'C', 'to_en': 'D', 'surface_ok': true, 'visibility_ok': true, 'drifting': true},
          {'from_en': 'D', 'to_en': 'E', 'surface_ok': true, 'visibility_ok': true, 'no_report': true},
          {'from_en': 'E', 'to_en': 'F'},
        ],
        'in_season': true,
        'checked_at': DateTime.now(),
      });
      expect(c.segments.map((s) => s.needsAttention).toList(), [false, true, true, false, true],
          reason: 'a segment without its flags counts as worth a look, never as fine');
    });

    test('cameras: only https images', () {
      final cams = RoadCamera.listFromMap({
        'cameras': [
          {'location': 'Highway 63 at Wyse Road', 'views': [
            {'image_url': 'https://511on.ca/map/Cctv/2720', 'direction_en': 'Looking North', 'direction_fr': 'Vers le nord'},
            {'image_url': 'http://insecure/1'},
          ]},
          {'location': 'Nothing usable', 'views': [{'image_url': 'ftp://x'}]},
        ],
      });
      expect(cams, hasLength(1));
      expect(cams.single.views.single.direction(AppLanguage.fr), 'Vers le nord');
    });

    test('health: never checked, recent, failing (1 h for roads, 3 h for the Town)', () {
      final repo = FakeRoadsRepository(lastSuccess: {
        ...SampleRoads.checked(),
        'mtmd-warnings': SampleRoads.ago(const Duration(minutes: 70)),
        'town-work-info': SampleRoads.ago(const Duration(hours: 2)),
      });
      final now = DateTime.now();
      expect(repo.health(Road.route101.sources, now), isA<CheckFailing>());
      expect(repo.health(Road.highway63.sources, now), isA<CheckedRecently>());
      expect(repo.health(townSources, now), isA<CheckedRecently>());
      final fresh = FakeRoadsRepository(lastSuccess: {'mtmd-warnings': DateTime.now()});
      expect(fresh.health(Road.route101.sources, now), isA<NeverChecked>());
    });

    test('a road notification opens the Roads screen', () {
      expect(targetOf({'screen': 'roads', 'road': '101'}), roadsTarget);
      expect(roadsTopicFor(AppLanguage.fr), 'roads-fr');
    });
  });

  group('Today', () {
    testWidgets('nothing wrong and checked: no road card', (tester) async {
      await _pumpApp(tester, _en, FakeRoadsRepository());
      expect(find.byType(RoadsCard), findsNothing);
    });

    testWidgets('a Route 101 closure: amber card, opens the Roads screen', (tester) async {
      final s = stringsFor(AppLanguage.en);
      await _pumpApp(tester, _en, FakeRoadsRepository(items: [SampleRoads.closure101()]));
      expect(find.byType(RoadsCard), findsOneWidget);
      expect(find.text(s.roadsTodayLine(s.roadsRoute101, s.roadsAtPlace('Road closed', 'Saint-Édouard-de-Fabre'))), findsOneWidget);
      await scrollAndTap(tester, find.byType(RoadsCard));
      expect(find.byType(RoadsScreen), findsOneWidget);
    });

    testWidgets('in French, with Highway 63 closed too', (tester) async {
      final s = stringsFor(AppLanguage.fr);
      await _pumpApp(tester, _fr, FakeRoadsRepository(items: [SampleRoads.closure101(), SampleRoads.closure63()]));
      expect(find.text('Route 101 : Route fermée à Saint-Édouard-de-Fabre'), findsOneWidget);
      expect(find.text(s.roadsTodayLine(s.roadsHighway63, 'Route fermée')), findsOneWidget);
    });

    testWidgets('icy road and snow on 63: one line each', (tester) async {
      final s = stringsFor(AppLanguage.en);
      await _pumpApp(tester, _en, FakeRoadsRepository(conditions: SampleRoads.winterStorm()));
      expect(find.text(s.roadsTodayLine('Route 101 (Témiscaming → Saint-Édouard-de-Fabre)', 'Ice Covered, visibility poor')), findsOneWidget);
      expect(find.text(s.roadsTodayLine('Highway 63 (North Bay → Thorne)', 'Snow packed')), findsOneWidget);
    });

    testWidgets('a planned closure says from when', (tester) async {
      final s = stringsFor(AppLanguage.en);
      await _pumpApp(tester, _en, FakeRoadsRepository(items: [SampleRoads.plannedClosure()]));
      final line = find.textContaining(s.roadsPlannedShort('Road closed (roadwork)', '').split(',').first);
      expect(line, findsOneWidget);
      expect(find.textContaining(', from '), findsOneWidget);
    });

    testWidgets('roadwork and the Town\'s work never go on Today', (tester) async {
      await _pumpApp(tester, _en, FakeRoadsRepository(items: [SampleRoads.roadwork101(), SampleRoads.townFlushing()]));
      expect(find.byType(RoadsCard), findsNothing);
    });

    testWidgets('a failing check is said on Today, all year', (tester) async {
      final s = stringsFor(AppLanguage.en);
      final roads = FakeRoadsRepository(lastSuccess: SampleRoads.checked(age: const Duration(hours: 2)));
      await _pumpApp(tester, _en, roads);
      expect(find.byType(RoadsCard), findsOneWidget);
      expect(find.textContaining(s.roadsTodayStale('').trim()), findsOneWidget);
      roads.set(lastSuccess: const {});
      await tester.pumpAndSettle();
      expect(find.text(s.roadsTodayNeverChecked), findsOneWidget);
    });
  });

  group('Roads screen', () {
    testWidgets('a quiet day: nothing reported on either road, bare and dry, Town work listed', (tester) async {
      final s = stringsFor(AppLanguage.en);
      await _pumpScreen(tester, AppLanguage.en, FakeRoadsRepository(items: [SampleRoads.townFlushing()]));
      expect(find.text(s.roadsRoute101Heading), findsOneWidget);
      expect(find.text(s.roadsNothingReported), findsWidgets);
      expect(find.text('Témiscaming → Saint-Édouard-de-Fabre'), findsOneWidget);
      await _scrollTo(tester, find.text('North Bay → Thorne'));
      expect(find.text(s.roadsNothingReported), findsWidgets);
      expect(find.text('Bare and dry road'), findsOneWidget);
      await _scrollTo(tester, find.text('WATER SYSTEM FLUSHING | MONTH OF OCTOBER'));
      expect(find.text(s.roadsNoTownWork), findsNothing);
      await _scrollTo(tester, find.text(s.roadsOntarioSource));
    });

    testWidgets('stale: no "nothing reported", the health line says so', (tester) async {
      final s = stringsFor(AppLanguage.en);
      await _pumpScreen(tester, AppLanguage.en, FakeRoadsRepository(lastSuccess: SampleRoads.checked(age: const Duration(hours: 2))));
      expect(find.text(s.roadsNothingReported), findsNothing);
      expect(find.textContaining(s.roadsCheckFailedSince('').trim()), findsWidgets);
      await _scrollTo(tester, find.text(s.roadsTownWorkHeading));
      expect(find.text(s.roadsNoTownWork), findsNothing, reason: 'the Town wasn\'t read recently either');
    });

    testWidgets('never checked: no conditions, no "nothing reported"', (tester) async {
      final s = stringsFor(AppLanguage.fr);
      await _pumpScreen(tester, AppLanguage.fr, FakeRoadsRepository(lastSuccess: const {}, conditions: const {}));
      expect(find.text(s.roadsNothingReported), findsNothing);
      expect(find.text(s.roadsNeverChecked), findsWidgets);
    });

    testWidgets('a French-only closure for an English reader: labelled, and its own screen shows the French text', (tester) async {
      final s = stringsFor(AppLanguage.en);
      await _pumpScreen(tester, AppLanguage.en, FakeRoadsRepository(items: [SampleRoads.closure101()]));
      expect(find.text(s.roadsClosuresHeading), findsOneWidget);
      expect(find.text(s.alertOnlyFrench), findsOneWidget);
      await scrollAndTap(tester, find.text(s.roadsAtPlace('Road closed', 'Saint-Édouard-de-Fabre')));
      expect(find.byType(RoadItemScreen), findsOneWidget);
      expect(find.text(s.alertOnlyFrench), findsOneWidget);
      expect(find.textContaining('Détour : Aucun détour possible'), findsOneWidget);
      expect(find.textContaining(s.roadsInEffectSince('').trim()), findsOneWidget);
    });

    testWidgets('a planned closure is "planned", never "in effect"', (tester) async {
      final s = stringsFor(AppLanguage.en);
      await _pumpScreen(tester, AppLanguage.en, FakeRoadsRepository(items: [SampleRoads.plannedClosure()]));
      expect(find.textContaining(s.roadsPlannedFrom('').trim()), findsOneWidget);
      expect(find.textContaining(s.roadsInEffectSince('').trim()), findsNothing);
    });

    testWidgets('roadwork under its own heading', (tester) async {
      final s = stringsFor(AppLanguage.fr);
      await _pumpScreen(tester, AppLanguage.fr, FakeRoadsRepository(items: [SampleRoads.roadwork101()]));
      expect(find.text(s.roadsRoadworkHeading), findsOneWidget);
      expect(find.text('Travaux routiers'), findsOneWidget);
    });

    testWidgets('outside the season, Route 101 says winter conditions aren\'t published', (tester) async {
      final s = stringsFor(AppLanguage.en);
      await _pumpScreen(tester, AppLanguage.en, FakeRoadsRepository(conditions: SampleRoads.bareAndDry(inSeason: false)));
      expect(find.text(s.roadsConditionsOffSeason), findsOneWidget);
    });

    testWidgets('Ontario "No report" is shown as such, never as clear', (tester) async {
      final s = stringsFor(AppLanguage.en);
      final conditions = SampleRoads.bareAndDry();
      conditions[Road.highway63] = RoadConditions(
        segments: [SampleRoads.segment(from: 'North Bay', to: 'Thorne', surfaceEn: 'No Report', noReport: true)],
        inSeason: null,
        checkedAt: DateTime.now(),
      );
      await _pumpScreen(tester, AppLanguage.en, FakeRoadsRepository(conditions: conditions));
      await _scrollTo(tester, find.text(s.roadsNoReport));
      expect(find.text('No Report'), findsNothing);
    });

    testWidgets('Highway 63 cameras: three views, credited', (tester) async {
      final s = stringsFor(AppLanguage.en);
      await _pumpScreen(tester, AppLanguage.en, FakeRoadsRepository(cameras: SampleRoads.cameras()));
      await _scrollTo(tester, find.text(s.roadsCameraCredit));
      expect(find.byType(CameraViewTile), findsNWidgets(3));
      expect(find.text('Highway 63 at Wyse Road · Looking South'), findsOneWidget);
      // Tap to refresh: still there, no error.
      await tester.tap(find.text('Highway 63 at Wyse Road · Looking South'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the notify switch: phones only, off by default, asks permission, subscribes', (tester) async {
      final s = stringsFor(AppLanguage.en);
      await _pumpScreen(tester, AppLanguage.en, FakeRoadsRepository());
      expect(find.text(s.roadsNotifyTitle), findsNothing, reason: 'desktop: no push');

      final push = FakePushService(isSupported: true);
      final settings = await _pumpScreen(tester, AppLanguage.en, FakeRoadsRepository(), push: push);
      expect(settings.roadClosuresEnabled, isFalse);
      await tester.tap(find.text(s.roadsNotifyTitle));
      await tester.pumpAndSettle();
      expect(push.permissionRequests, 1);
      expect(settings.roadClosuresEnabled, isTrue);

      push.grantPermission = false;
      await tester.tap(find.text(s.roadsNotifyTitle)); // off: never asks
      await tester.pumpAndSettle();
      expect(settings.roadClosuresEnabled, isFalse);
      await tester.tap(find.text(s.roadsNotifyTitle)); // on, but denied
      await tester.pumpAndSettle();
      expect(settings.roadClosuresEnabled, isFalse);
      expect(find.text(s.settingsPermissionDenied), findsOneWidget);
    });
  });

  group('More tab, settings and notifications', () {
    testWidgets('More lists Roads, Fire, Weather, the schedule and Settings; Roads opens', (tester) async {
      final s = stringsFor(AppLanguage.fr);
      await _pumpApp(tester, _fr, FakeRoadsRepository());
      await tester.tap(find.widgetWithText(NavigationDestination, s.moreTitle));
      await tester.pumpAndSettle();
      expect(find.byType(MoreScreen), findsOneWidget);
      for (final t in [s.roadsTitle, s.fireTitle, s.weatherTitle, s.collectionScheduleTitle, s.settingsTitle]) {
        expect(find.descendant(of: find.byType(MoreScreen), matching: find.text(t)), findsOneWidget, reason: t);
      }
      await tester.tap(find.descendant(of: find.byType(MoreScreen), matching: find.text(s.roadsTitle)));
      await tester.pumpAndSettle();
      expect(find.byType(RoadsScreen), findsOneWidget);
    });

    testWidgets('road closures stay off when the notifications question is answered yes', (tester) async {
      final push = FakePushService(isSupported: true);
      final settings = await pumpApp(tester, const {'language': 'en', 'sector': 'town'}, null, push);
      await scrollAndTap(tester, find.text(stringsFor(AppLanguage.en).notificationsAllow));
      expect(settings.waterAlertsEnabled, isTrue);
      expect(settings.roadClosuresEnabled, isFalse);
    });

    testWidgets('Settings has the road closures switch', (tester) async {
      final s = stringsFor(AppLanguage.en);
      final push = FakePushService(isSupported: true);
      final settings = await _pumpApp(tester, _en, FakeRoadsRepository(), push: push);
      await tester.tap(find.byTooltip(s.settingsTitle).first);
      await tester.pumpAndSettle();
      await scrollAndTap(tester, find.text(s.settingsRoadClosures));
      expect(settings.roadClosuresEnabled, isTrue);
    });

    testWidgets('a tapped road notification opens the Roads screen', (tester) async {
      final push = FakePushService(isSupported: true);
      await _pumpApp(tester, _en, FakeRoadsRepository(items: [SampleRoads.closure63()]), push: push);
      push.tapNotification(roadsTarget);
      await tester.pumpAndSettle();
      expect(find.byType(RoadsScreen), findsOneWidget);
    });
  });
}
