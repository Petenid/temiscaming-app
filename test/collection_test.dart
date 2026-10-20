// Collection day on the phone (spec §6, App; §8 step 4): the scheduling
// logic, the Today card in every state, the schedule screen, and the copy of
// the schedule saved on the phone.
import 'dart:convert';

import 'package:community/collection/bin_icon.dart';
import 'package:community/collection/collection_card.dart';
import 'package:community/collection/collection_repository.dart';
import 'package:community/collection/collection_screen.dart';
import 'package:community/collection/pickup.dart';
import 'package:community/collection/schedule.dart';
import 'package:community/l10n/app_localizations.dart';
import 'package:community/settings/app_settings.dart';
import 'package:community/settings/sector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'collection_fakes.dart';
import 'helpers.dart';

final oct19 = SamplePickups.monday19Oct;

/// Shows one widget in a minimal app in [language], with [sector] saved.
Future<AppSettings> pumpInApp(
  WidgetTester tester,
  AppLanguage language,
  Widget Function(AppSettings) build, {
  Sector sector = Sector.town,
}) async {
  SharedPreferences.setMockInitialValues({'language': language.name, 'sector': sector.name});
  final settings = await AppSettings.load();
  await tester.pumpWidget(MaterialApp(
    locale: language.locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: build(settings)),
  ));
  await tester.pumpAndSettle();
  return settings;
}

Future<void> pumpCard(
  WidgetTester tester,
  AppLanguage language,
  FakeCollectionRepository repo, {
  DateTime? now,
  Sector sector = Sector.town,
}) => pumpInApp(
  tester,
  language,
  (settings) => ListView(children: [
    CollectionCard(settings: settings, repository: repo, onOpenSchedule: () {}, now: now ?? oct19),
  ]),
  sector: sector,
);

String weekday(AppLanguage l, DateTime d) => DateFormat.EEEE('${l.name}_CA').format(d);
String shortDay(AppLanguage l, DateTime d) => DateFormat.MMMEd('${l.name}_CA').format(d);
String longDay(AppLanguage l, DateTime d) => DateFormat.MMMMEEEEd('${l.name}_CA').format(d);

void main() {
  group('scheduling logic', () {
    test('weeks start on Monday, across month ends', () {
      expect(mondayOf(DateTime(2026, 10, 19)), DateTime(2026, 10, 19));
      expect(mondayOf(DateTime(2026, 10, 25, 23)), DateTime(2026, 10, 19));
      expect(mondayOf(DateTime(2026, 11, 1)), DateTime(2026, 10, 26));
    });

    test('labels: today, this week, next week, later', () {
      final today = DateTime(2026, 10, 19);
      expect(whenLabel(DateTime(2026, 10, 19), today), WhenLabel.today);
      expect(whenLabel(DateTime(2026, 10, 20), today), WhenLabel.thisWeek);
      expect(whenLabel(DateTime(2026, 10, 27), today), WhenLabel.nextWeek);
      expect(whenLabel(DateTime(2026, 11, 3), today), WhenLabel.later);
    });

    test('overview picks the sector, skips past and cancelled pickups', () {
      final all = [
        ...SamplePickups.octoberNovember(),
        pickup('2026-10-13', Sector.town, BinMaterial.recycling),
        pickup('2026-10-20', Sector.town, BinMaterial.compost, cancelled: true),
      ];
      final ov = overview(all, Sector.town, oct19);
      expect(ov.next!.date, DateTime(2026, 10, 20));
      expect(ov.next!.bins, [BinMaterial.garbage]);
      expect(ov.then!.date, DateTime(2026, 10, 27));
      expect(ov.noPickupThisWeek, isFalse);
      expect(overview(all, Sector.lumsden, oct19).next!.date, DateTime(2026, 10, 21));
    });

    test('two bins on one day come in the order green, blue, black', () {
      final day = PickupDay(DateTime(2026, 12, 22), [
        pickup('2026-12-22', Sector.town, BinMaterial.recycling),
        pickup('2026-12-22', Sector.town, BinMaterial.compost),
      ]);
      expect(day.bins, [BinMaterial.compost, BinMaterial.recycling]);
    });

    test('"not posted yet" only when the last known pickup is less than two weeks away', () {
      final all = SamplePickups.octoberNovember();
      expect(overview(all, Sector.town, oct19, knownThrough: DateTime(2026, 12, 23)).notPostedAfter, isNull);
      expect(overview(all, Sector.town, oct19, knownThrough: DateTime(2026, 10, 28)).notPostedAfter,
          DateTime(2026, 10, 28));
      expect(overview(const [], Sector.town, oct19).notPostedAfter, isNull);
    });
  });

  for (final language in AppLanguage.values) {
    final strings = stringsFor(language);
    group('Today card (${language.name})', () {
      testWidgets('this week, then the next pickup', (tester) async {
        await pumpCard(tester, language, FakeCollectionRepository(pickups: SamplePickups.octoberNovember()));
        expect(find.text(strings.collectionThisWeek(strings.binGarbageShort, weekday(language, DateTime(2026, 10, 20)))),
            findsOneWidget);
        expect(find.text(strings.collectionThen(strings.binRecyclingShort, shortDay(language, DateTime(2026, 10, 27)))),
            findsOneWidget);
        expect(find.byType(BinIcon), findsOneWidget);
      });

      testWidgets('on pickup day it says today; the day after, next week', (tester) async {
        final repo = FakeCollectionRepository(pickups: SamplePickups.octoberNovember());
        await pumpCard(tester, language, repo, now: DateTime(2026, 10, 20, 7));
        expect(find.text(strings.collectionToday(strings.binGarbageShort)), findsOneWidget);
        await pumpCard(tester, language, repo, now: DateTime(2026, 10, 21, 7));
        expect(find.text(strings.collectionNextWeek(strings.binRecyclingShort, weekday(language, DateTime(2026, 10, 27)))),
            findsOneWidget);
      });

      testWidgets('Lumsden/Letang sees its own Wednesday pickup', (tester) async {
        await pumpCard(tester, language, FakeCollectionRepository(pickups: SamplePickups.octoberNovember()),
            sector: Sector.lumsden);
        expect(find.text(strings.collectionThisWeek(strings.binGarbageShort, weekday(language, DateTime(2026, 10, 21)))),
            findsOneWidget);
      });

      testWidgets('two bins, moved, and from the MRC calendar', (tester) async {
        await pumpCard(tester, language, FakeCollectionRepository(pickups: [
          pickup('2026-10-21', Sector.town, BinMaterial.recycling, movedFrom: '2026-10-20', origin: PickupOrigin.mrc),
          pickup('2026-10-21', Sector.town, BinMaterial.compost, movedFrom: '2026-10-20', origin: PickupOrigin.mrc),
        ]));
        final both = strings.listAnd(strings.binCompostShort, strings.binRecyclingShort);
        expect(find.text(strings.collectionThisWeek(both, weekday(language, DateTime(2026, 10, 21)))), findsOneWidget);
        expect(find.textContaining(strings.collectionMoved(shortDay(language, DateTime(2026, 10, 20)))), findsOneWidget);
        expect(find.textContaining(strings.collectionFromMrc), findsOneWidget);
        expect(find.byType(BinIcon), findsNWidgets(2));
      });

      testWidgets('a pickup cancelled by the Town says so, and points to next week', (tester) async {
        await pumpCard(tester, language, FakeCollectionRepository(pickups: [
          pickup('2026-10-20', Sector.town, BinMaterial.garbage, cancelled: true),
          pickup('2026-10-27', Sector.town, BinMaterial.recycling),
        ]));
        expect(find.text(strings.collectionNoPickupThisWeek), findsOneWidget);
        expect(find.text(strings.collectionNextWeek(strings.binRecyclingShort, weekday(language, DateTime(2026, 10, 27)))),
            findsOneWidget);
      });

      testWidgets('never shows "no pickup" when nothing is posted', (tester) async {
        await pumpCard(tester, language, FakeCollectionRepository());
        expect(find.text(strings.collectionNothingPosted), findsOneWidget);
        expect(find.text(strings.collectionNoPickupThisWeek), findsNothing);
      });

      testWidgets('says when pickups beyond a date are not posted yet', (tester) async {
        await pumpCard(tester, language, FakeCollectionRepository(
          pickups: SamplePickups.octoberNovember(),
          health: CollectionHealth(lastSuccessAt: DateTime.now(), knownThrough: DateTime(2026, 10, 28)),
        ));
        expect(find.text(strings.collectionNotPostedAfter(longDay(language, DateTime(2026, 10, 28)))), findsOneWidget);
      });

      testWidgets('a calendar not checked for hours shows in red words, data still shown', (tester) async {
        final lastOk = DateTime.now().subtract(const Duration(hours: 9));
        await pumpCard(tester, language, FakeCollectionRepository(
          pickups: SamplePickups.octoberNovember(),
          health: CollectionHealth(lastSuccessAt: lastOk),
        ));
        expect(find.textContaining(strings.collectionCheckFailedSince('').trim()), findsOneWidget);
        expect(find.text(strings.collectionThisWeek(strings.binGarbageShort, weekday(language, DateTime(2026, 10, 20)))),
            findsOneWidget);
      });

      testWidgets('Christmas-tree pickup this week is mentioned', (tester) async {
        await pumpCard(tester, language, FakeCollectionRepository(pickups: [
          ...SamplePickups.octoberNovember(),
          pickup('2026-10-22', Sector.town, null, special: 'christmas-trees'),
        ]));
        expect(find.text(strings.collectionAlsoThisWeek(strings.specialChristmasTrees, shortDay(language, DateTime(2026, 10, 22)))),
            findsOneWidget);
      });
    });

    testWidgets('schedule screen (${language.name}): full bin names, labels, links', (tester) async {
      // Tall enough that the list builds every row.
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpInApp(tester, language, (settings) => CollectionScreen(
        settings: settings,
        now: oct19,
        repository: FakeCollectionRepository(pickups: [
          ...SamplePickups.octoberNovember(),
          pickup('2026-11-10', Sector.town, BinMaterial.recycling, cancelled: true),
          pickup('2026-11-17', Sector.town, BinMaterial.garbage, origin: PickupOrigin.mrc),
          pickup('2027-01-05', Sector.town, BinMaterial.compost), // beyond 8 weeks
        ]),
      ));
      expect(find.text(strings.binGarbage), findsNWidgets(2)); // 20 Oct, and 17 Nov from the MRC
      expect(find.text(strings.binRecycling), findsNWidgets(2));
      expect(find.text(strings.binCompost), findsOneWidget); // 3 Nov only; 5 Jan is too far
      expect(find.text(strings.collectionCancelled), findsOneWidget);
      expect(find.text(strings.collectionFromMrc), findsOneWidget);
      expect(find.text(strings.sectorLumsdenName), findsNothing);
      expect(find.text(strings.collectionMrcCalendarLink), findsOneWidget);
      expect(find.text(strings.collectionTownCalendarLink), findsOneWidget);
    });
  }

  group('copy saved on the phone (spec D1)', () {
    test('a pickup survives being saved and read back', () {
      final p = pickup('2026-10-22', Sector.lumsden, BinMaterial.garbage, movedFrom: '2026-10-21', origin: PickupOrigin.mrc);
      final back = Pickup.fromMap(p.id, p.toMap())!;
      expect(back.date, p.date);
      expect(back.sector, Sector.lumsden);
      expect(back.material, BinMaterial.garbage);
      expect(back.origin, PickupOrigin.mrc);
      expect(back.isMoved, isTrue);
      expect(back.previousDate, DateTime(2026, 10, 21));
    });

    test('a sector this app version does not know is skipped, not misassigned', () {
      expect(Pickup.fromMap('x', {'date': '2026-10-20', 'sector': 'haut-de-la-ville', 'material': 'garbage'}), isNull);
    });

    test('without Firebase, the saved copy is shown (with its health)', () async {
      final p = pickup('2026-10-20', Sector.town, BinMaterial.garbage);
      final checked = DateTime(2026, 10, 19, 14, 20);
      SharedPreferences.setMockInitialValues({
        collectionCacheKey: jsonEncode({
          'pickups': {p.id: p.toMap()},
          'health': CollectionHealth(lastSuccessAt: checked, knownThrough: DateTime(2026, 12, 23)).toMap(),
        }),
      });
      final repo = OfflineCollectionRepository(await SharedPreferences.getInstance());
      expect(repo.failed, isFalse);
      expect(repo.pickups.single.id, p.id);
      expect(repo.health!.lastSuccessAt, checked);
      expect(repo.health!.knownThrough, DateTime(2026, 12, 23));
    });

    test('without Firebase or a saved copy, the screens say it failed', () async {
      SharedPreferences.setMockInitialValues({});
      expect(OfflineCollectionRepository(await SharedPreferences.getInstance()).failed, isTrue);
    });
  });
}
