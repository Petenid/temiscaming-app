// Bin reminders, pickup-change subscriptions and the new Settings controls
// (spec D6–D8; §8 step 4: reminders scheduled from the phone's own copy,
// with the backend unreachable).
import 'dart:convert';

import 'package:community/collection/collection_repository.dart';
import 'package:community/collection/collection_screen.dart';
import 'package:community/collection/pickup.dart';
import 'package:community/collection/reminders.dart';
import 'package:community/push/push_service.dart';
import 'package:community/settings/app_settings.dart';
import 'package:community/settings/sector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'collection_fakes.dart';
import 'fakes.dart';
import 'helpers.dart';

final oct19 = SamplePickups.monday19Oct; // 10 a.m.
final en = stringsFor(AppLanguage.en);
final fr = stringsFor(AppLanguage.fr);

List<Reminder> remindersFor(Sector sector, {DateTime? now, int minutes = 19 * 60, List<Pickup>? pickups}) =>
    buildReminders(
      pickups: pickups ?? SamplePickups.octoberNovember(),
      sector: sector,
      now: now ?? oct19,
      minutes: minutes,
      strings: en,
    );

void main() {
  group('which reminders', () {
    test('the evening before each pickup, at 7 p.m., in the user\'s language', () {
      final town = remindersFor(Sector.town);
      expect(town.map((r) => r.at), [
        DateTime(2026, 10, 19, 19),
        DateTime(2026, 10, 26, 19),
        DateTime(2026, 11, 2, 19),
      ]);
      expect(town.first.title, en.reminderTitle(en.binGarbageShort));
      expect(town.first.body, en.reminderBodyOne);
      expect(town.first.id, 20261020);
      final french = buildReminders(
        pickups: SamplePickups.octoberNovember(), sector: Sector.town, now: oct19, minutes: 19 * 60, strings: fr,
      );
      expect(french.first.title, fr.reminderTitle(fr.binGarbageShort));
    });

    test('Lumsden/Letang get theirs the evening before Wednesday', () {
      expect(remindersFor(Sector.lumsden).first.at, DateTime(2026, 10, 20, 19));
    });

    test('a reminder whose time has passed is left out', () {
      expect(remindersFor(Sector.town, now: DateTime(2026, 10, 19, 19, 30)).first.at, DateTime(2026, 10, 26, 19));
    });

    test('a chosen time is used', () {
      expect(remindersFor(Sector.town, minutes: 18 * 60 + 30).first.at, DateTime(2026, 10, 19, 18, 30));
    });

    test('none for cancelled pickups or special collections; two bins → "put them out"', () {
      final r = remindersFor(Sector.town, pickups: [
        pickup('2026-10-20', Sector.town, BinMaterial.garbage, cancelled: true),
        pickup('2026-10-22', Sector.town, null, special: 'christmas-trees'),
        pickup('2026-10-27', Sector.town, BinMaterial.recycling),
        pickup('2026-10-27', Sector.town, BinMaterial.compost),
      ]);
      expect(r, hasLength(1));
      expect(r.single.title, en.reminderTitle(en.listAnd(en.binCompostShort, en.binRecyclingShort)));
      expect(r.single.body, en.reminderBodyMany);
    });

    test('only the next 8 weeks (well under the phone\'s limit)', () {
      final weekly = [
        for (var i = 0; i < 20; i++) pickup(dayKey(DateTime(2026, 10, 20 + 7 * i)), Sector.town, BinMaterial.recycling),
      ];
      expect(remindersFor(Sector.town, pickups: weekly), hasLength(8));
    });
  });

  group('ReminderSync', () {
    Future<(AppSettings, FakeReminderService)> start(
      Map<String, Object> prefs,
      CollectionRepository collection,
    ) async {
      SharedPreferences.setMockInitialValues(prefs);
      final settings = await AppSettings.load();
      final service = FakeReminderService(isSupported: true);
      ReminderSync(settings, collection, service, now: () => oct19);
      await Future<void>.delayed(Duration.zero);
      return (settings, service);
    }

    const answered = {'language': 'en', 'sector': 'town', 'water_alerts': true};

    test('schedules from the copy saved on the phone, with no backend at all', () async {
      final saved = {for (final p in SamplePickups.octoberNovember()) p.id: p.toMap()};
      SharedPreferences.setMockInitialValues({
        ...answered,
        collectionCacheKey: jsonEncode({'pickups': saved, 'health': null}),
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = await AppSettings.load();
      final service = FakeReminderService(isSupported: true);
      ReminderSync(settings, OfflineCollectionRepository(prefs), service, now: () => oct19);
      await Future<void>.delayed(Duration.zero);
      expect(service.scheduled.map((r) => r.at).first, DateTime(2026, 10, 19, 19));
      expect(service.scheduled, hasLength(3));
    });

    test('follows the settings: off, new time, new sector, new language', () async {
      final (settings, service) = await start(answered, FakeCollectionRepository(pickups: SamplePickups.octoberNovember()));
      expect(service.scheduled.first.at, DateTime(2026, 10, 19, 19));

      await settings.setReminderMinutes(18 * 60);
      await Future<void>.delayed(Duration.zero);
      expect(service.scheduled.first.at, DateTime(2026, 10, 19, 18));

      await settings.setSector(Sector.lumsden);
      await Future<void>.delayed(Duration.zero);
      expect(service.scheduled.first.at, DateTime(2026, 10, 20, 18));

      await settings.setLanguage(AppLanguage.fr);
      await Future<void>.delayed(Duration.zero);
      expect(service.scheduled.first.title, fr.reminderTitle(fr.binGarbageShort));

      await settings.setBinReminder(false);
      await Future<void>.delayed(Duration.zero);
      expect(service.scheduled, isEmpty);
    });

    test('follows schedule updates, and does nothing when nothing changed', () async {
      final repo = FakeCollectionRepository(pickups: SamplePickups.octoberNovember());
      final (_, service) = await start(answered, repo);
      final before = service.replacements.length;
      repo.set(pickups: SamplePickups.octoberNovember()); // same pickups
      await Future<void>.delayed(Duration.zero);
      expect(service.replacements.length, before);
      repo.set(pickups: [pickup('2026-10-21', Sector.town, BinMaterial.garbage, movedFrom: '2026-10-20')]);
      await Future<void>.delayed(Duration.zero);
      expect(service.scheduled.single.at, DateTime(2026, 10, 20, 19));
    });

    test('nothing before the notifications question is answered, or if the answer was no', () async {
      final (_, notAsked) = await start({'language': 'en', 'sector': 'town'}, FakeCollectionRepository(pickups: SamplePickups.octoberNovember()));
      expect(notAsked.replacements, isEmpty);
      final (_, saidNo) = await start({'language': 'en', 'sector': 'town', 'water_alerts': false},
          FakeCollectionRepository(pickups: SamplePickups.octoberNovember()));
      expect(saidNo.scheduled, isEmpty);
    });
  });

  group('pickup-change subscriptions (D6)', () {
    test('topic names match the backend', () {
      expect(collectionTopicFor(Sector.town, AppLanguage.fr), 'collection-town-fr');
      expect(collectionTopicFor(Sector.lumsden, AppLanguage.en), 'collection-lumsden-en');
    });

    test('follow the sector and the "pickup changes" switch', () async {
      SharedPreferences.setMockInitialValues({'language': 'fr', 'sector': 'town', 'water_alerts': true});
      final settings = await AppSettings.load();
      final push = FakePushService(isSupported: true);
      PushSync(settings, push);
      await settings.setSector(Sector.lumsden);
      await settings.setCollectionChanges(false);
      expect(push.appliedCollection, [(Sector.town, true), (Sector.lumsden, true), (Sector.lumsden, false)]);
    });

    test('a tapped push for a pickup leads to the schedule', () {
      expect(targetOf({'type': 'collection', 'pickup_id': '2026-10-22_lumsden_garbage'}), collectionTarget);
      expect(targetOf({'alert_id': '8344'}), '8344');
      expect(targetOf({}), isNull);
    });
  });

  group('the app', () {
    testWidgets('the notifications answer turns all three kinds on', (tester) async {
      final push = FakePushService(isSupported: true);
      final settings = await pumpApp(tester, {'language': 'en', 'sector': 'town'}, null, push);
      await scrollAndTap(tester, find.text(en.notificationsAllow));
      expect(settings.waterAlertsEnabled, isTrue);
      expect(settings.binReminderEnabled, isTrue);
      expect(settings.collectionChangesEnabled, isTrue);
    });

    testWidgets('Settings: reminder switch, its time, and pickup changes', (tester) async {
      final push = FakePushService(isSupported: true);
      final settings = await pumpApp(
        tester, {'language': 'en', 'sector': 'town', 'water_alerts': true}, null, push,
      );
      await tester.tap(find.byTooltip(en.settingsTitle));
      await tester.pumpAndSettle();
      // The notification switches are near the bottom of the list.
      await tester.scrollUntilVisible(find.text(en.settingsCollectionChanges), 200,
          scrollable: find.byType(Scrollable).hitTestable().first);
      expect(find.text(DateFormat.jm('en_CA').format(DateTime(2000, 1, 1, 19))), findsOneWidget);
      await scrollAndTap(tester, find.text(en.settingsBinReminder));
      expect(settings.binReminderEnabled, isFalse);
      await scrollAndTap(tester, find.text(en.settingsCollectionChanges));
      expect(settings.collectionChangesEnabled, isFalse);
      await scrollAndTap(tester, find.text(en.settingsBinReminder));
      expect(settings.binReminderEnabled, isTrue);
      expect(push.permissionRequests, 1); // turning on asks; turning off doesn't
    });

    testWidgets('tapping a reminder, or a pickup-change push, opens the schedule', (tester) async {
      final push = FakePushService(isSupported: true);
      final reminders = FakeReminderService(isSupported: true);
      await pumpApp(tester, {'language': 'en', 'sector': 'town', 'water_alerts': true}, null, push, null, reminders);
      reminders.tap();
      await tester.pumpAndSettle();
      expect(find.byType(CollectionScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      push.tapNotification(collectionTarget);
      await tester.pumpAndSettle();
      expect(find.byType(CollectionScreen), findsOneWidget);
    });

    testWidgets('a reminder that launched the app opens the schedule', (tester) async {
      final reminders = FakeReminderService(isSupported: true)..launched = true;
      await pumpApp(tester, {'language': 'en', 'sector': 'town', 'water_alerts': true}, null,
          FakePushService(isSupported: true), null, reminders);
      expect(find.byType(CollectionScreen), findsOneWidget);
    });
  });
}
