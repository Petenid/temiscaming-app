// Events tab, event detail, "Add to my calendar" and Today's "Coming up"
// card (events spec §6, §8 step 3).
import 'package:community/events/calendar_adder.dart';
import 'package:community/events/event_detail_screen.dart';
import 'package:community/events/events_card.dart';
import 'package:community/events/events_screen.dart';
import 'package:community/events/town_event.dart';
import 'package:community/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'events_fakes.dart';
import 'helpers.dart';

const _en = {'language': 'en', 'sector': 'town'};
const _fr = {'language': 'fr', 'sector': 'town'};

Future<void> _openEventsTab(WidgetTester tester, AppLanguage language) async {
  await tester.tap(find.widgetWithText(NavigationDestination, stringsFor(language).eventsTitle));
  await tester.pumpAndSettle();
}

Future<void> _pumpEvents(
  WidgetTester tester,
  Map<String, Object> prefs, {
  FakeEventsRepository? events,
  FakeCalendarAdder? calendar,
}) => pumpApp(tester, prefs, null, null, null, null,
    events ?? FakeEventsRepository(events: SampleEvents.all()), calendar);

/// Scrolls the visible list until [finder] is on screen.
Future<void> _scrollTo(WidgetTester tester, Finder finder) => tester.scrollUntilVisible(
  finder, 200, scrollable: find.byType(Scrollable).hitTestable().first,
);

void main() {
  group('date logic', () {
    final today = DateTime(2026, 12, 22, 15, 30);
    TownEvent ev(String id, DateTime start, [DateTime? end]) => TownEvent(
      id: id, category: EventCategory.community, titleFr: id, titleEn: id,
      placeFr: '', placeEn: '', startsOn: start, endsOn: end ?? start,
      sourceUrlFr: '', sourceUrlEn: '',
    );

    test('a running multi-day event is listed under today; ended ones are dropped', () {
      final closed = ev('closed', DateTime(2026, 12, 21), DateTime(2026, 12, 25));
      final ended = ev('ended', DateTime(2026, 12, 21));
      final later = ev('later', DateTime(2026, 12, 28));
      final days = agenda([later, ended, closed], today);
      expect(days.map((d) => d.date), [DateTime(2026, 12, 22), DateTime(2026, 12, 28)]);
      expect(days.first.events.single.id, 'closed');
      expect(nextEvents([later, ended, closed], today).map((e) => e.id), ['closed', 'later']);
    });

    test('next events: at most three, soonest first', () {
      final list = [for (var i = 5; i >= 0; i--) ev('e$i', DateTime(2026, 12, 23 + i))];
      expect(nextEvents(list, today).map((e) => e.id), ['e0', 'e1', 'e2']);
    });

    test('today, tomorrow, later', () {
      expect(eventWhen(DateTime(2026, 12, 22), today), EventWhen.today);
      expect(eventWhen(DateTime(2026, 12, 23), today), EventWhen.tomorrow);
      expect(eventWhen(DateTime(2026, 12, 24), today), EventWhen.later);
    });

    test('all-day times: UTC midnights with an exclusive end on Android, local dates on iOS', () {
      final android = allDayTimes(DateTime(2026, 12, 21), DateTime(2026, 12, 25), android: true);
      expect(android.start, DateTime.utc(2026, 12, 21));
      expect(android.end, DateTime.utc(2026, 12, 26));
      expect(android.timeZone, 'UTC');
      final oneDay = allDayTimes(DateTime(2026, 12, 31), DateTime(2026, 12, 31), android: true);
      expect(oneDay.end, DateTime.utc(2027, 1, 1)); // across the new year
      final ios = allDayTimes(DateTime(2026, 12, 21), DateTime(2026, 12, 25), android: false);
      expect(ios.start, DateTime(2026, 12, 21));
      expect(ios.end, DateTime(2026, 12, 25));
      expect(ios.timeZone, isNull);
    });

    test('reads the backend document; refuses unreadable dates', () {
      final e = TownEvent.fromMap('143335', {
        'category': 'closure', 'title_fr': 'HÔTEL DE VILLE FERMÉ', 'title_en': 'TOWN HALL CLOSED',
        'place_fr': '', 'place_en': '', 'starts_on': '2026-12-21', 'ends_on': '2026-12-25',
        'source_url_fr': 'https://www.temiscaming.net/fr/evenements/2026/12/21/143335/',
        'source_url_en': 'https://www.temiscaming.net/en/events/2026/12/21/143335/',
      })!;
      expect(e.category, EventCategory.closure);
      expect(e.startsOn, DateTime(2026, 12, 21));
      expect(e.endsOn, DateTime(2026, 12, 25));
      expect(e.isMultiDay, isTrue);
      expect(TownEvent.fromMap('x', {'starts_on': 'soon'}), isNull);
      expect(TownEvent.fromMap('y', {'starts_on': '2026-12-21', 'category': 'new-kind'})!.category,
          EventCategory.community);
    });

    test('French-only title shows in French; untitled stays in the user\'s language', () {
      expect(SampleEvents.frenchOnly().displayLanguage(AppLanguage.en), AppLanguage.fr);
      expect(SampleEvents.frenchOnly().title(AppLanguage.en), 'SOUPER MISSION TOURNESOL');
      expect(SampleEvents.untitledCouncil().displayLanguage(AppLanguage.en), AppLanguage.en);
      expect(SampleEvents.untitledCouncil().isUntitled, isTrue);
    });
  });

  for (final language in AppLanguage.values) {
    final strings = stringsFor(language);
    final prefs = language == AppLanguage.en ? _en : _fr;
    String t(TownEvent e) => language == AppLanguage.fr ? e.titleFr : e.titleEn;

    testWidgets('events list in ${language.name}: titles, categories, horizon line', (tester) async {
      await _pumpEvents(tester, prefs);
      await _openEventsTab(tester, language);
      expect(find.byType(EventsScreen), findsOneWidget);
      expect(find.text(t(SampleEvents.townHallClosed())), findsOneWidget);
      expect(find.text(t(SampleEvents.councilTomorrow())), findsOneWidget);
      expect(find.text(t(SampleEvents.show())), findsOneWidget);
      // English council titles get context from our category name.
      expect(find.textContaining(strings.eventCategoryCouncil), findsWidgets);
      expect(find.textContaining(strings.eventCategoryClosure), findsOneWidget);
      // Ended events are never listed.
      expect(find.text(t(SampleEvents.past())), findsNothing);
      expect(find.textContaining(strings.collectionLastChecked('').trim()), findsOneWidget);

      await _scrollTo(tester, find.text(strings.eventsSourceNote));
      // "Events after Monday, December 21 aren't posted yet."
      expect(find.textContaining(strings.eventsNotPostedAfter('@').split('@').first.trim()), findsOneWidget);
      expect(find.text(strings.collectionTownCalendarLink), findsOneWidget);
    });

    testWidgets('event detail and "Add to my calendar" in ${language.name}', (tester) async {
      final calendar = FakeCalendarAdder();
      await _pumpEvents(tester, prefs, calendar: calendar);
      await _openEventsTab(tester, language);
      final show = SampleEvents.show();
      await _scrollTo(tester, find.text(t(show)));
      await scrollAndTap(tester, find.text(t(show)));
      expect(find.byType(EventDetailScreen), findsOneWidget);
      expect(find.text(show.place(language)), findsOneWidget);
      expect(find.text(strings.eventNoTimesNote), findsOneWidget);
      expect(find.text(strings.alertViewOnSite), findsOneWidget);

      await scrollAndTap(tester, find.text(strings.eventAddToCalendar));
      final request = calendar.requests.single;
      expect(request.title, t(show));
      expect(request.firstDay, show.startsOn);
      expect(request.lastDay, show.endsOn);
      expect(request.location, strings.eventLocation(show.place(language)));
      expect(request.notes, contains(show.sourceUrl(language)));
    });

    testWidgets('Today shows what\'s coming up and opens the Events tab (${language.name})', (tester) async {
      await _pumpEvents(tester, prefs);
      final cardTitle = find.descendant(
        of: find.byType(EventsCard), matching: find.text(strings.eventsCardTitle),
      );
      await _scrollTo(tester, cardTitle);
      // Town hall closed (running), council tomorrow, the show: three events.
      expect(find.descendant(of: find.byType(EventsCard), matching: find.text(t(SampleEvents.townHallClosed()))), findsOneWidget);
      expect(find.descendant(of: find.byType(EventsCard), matching: find.text(t(SampleEvents.councilTomorrow()))), findsOneWidget);
      expect(find.descendant(of: find.byType(EventsCard), matching: find.text(t(SampleEvents.show()))), findsOneWidget);
      expect(find.descendant(of: find.byType(EventsCard), matching: find.text(strings.eventTomorrow)), findsOneWidget);
      expect(find.descendant(of: find.byType(EventsCard), matching: find.textContaining('${strings.eventToday} – ')), findsOneWidget);

      await scrollAndTap(tester, cardTitle);
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 2);
      expect(find.byType(EventsScreen), findsOneWidget);
    });
  }

  testWidgets('an untitled event shows our category name, in italics (spec D3)', (tester) async {
    await _pumpEvents(tester, _en, events: FakeEventsRepository(events: [SampleEvents.untitledCouncil()]));
    await _openEventsTab(tester, AppLanguage.en);
    final title = tester.widget<Text>(find.text('Town council'));
    expect(title.style?.fontStyle, FontStyle.italic);
    await scrollAndTap(tester, find.text('Town council'));
    expect(find.byType(EventDetailScreen), findsOneWidget);
  });

  testWidgets('a French-only event says so in English', (tester) async {
    await _pumpEvents(tester, _en, events: FakeEventsRepository(events: [SampleEvents.frenchOnly()]));
    await _openEventsTab(tester, AppLanguage.en);
    await scrollAndTap(tester, find.text('SOUPER MISSION TOURNESOL'));
    expect(find.text('Available in French only'), findsOneWidget);
  });

  testWidgets('a multi-day event shows its dates as a range', (tester) async {
    await _pumpEvents(tester, _en, events: FakeEventsRepository(events: [SampleEvents.townHallClosed()]));
    await _openEventsTab(tester, AppLanguage.en);
    await scrollAndTap(tester, find.text('TOWN HALL CLOSED'));
    // "Monday, October 19 to Thursday, October 22"
    expect(find.textContaining(RegExp(r'^\w+, \w+ \d+ to \w+, \w+ \d+$')), findsOneWidget);
  });

  testWidgets('no calendar app on the phone: says so', (tester) async {
    final calendar = FakeCalendarAdder(outcome: CalendarOutcome.noCalendarApp);
    await _pumpEvents(tester, _en, calendar: calendar,
        events: FakeEventsRepository(events: [SampleEvents.show()]));
    await _openEventsTab(tester, AppLanguage.en);
    await scrollAndTap(tester, find.text(SampleEvents.show().titleEn));
    await scrollAndTap(tester, find.text('Add to my calendar'));
    expect(find.text('No calendar app found on this phone.'), findsOneWidget);
  });

  testWidgets('desktop: no "Add to my calendar" button', (tester) async {
    await _pumpEvents(tester, _en, calendar: FakeCalendarAdder(isSupported: false),
        events: FakeEventsRepository(events: [SampleEvents.show()]));
    await _openEventsTab(tester, AppLanguage.en);
    await scrollAndTap(tester, find.text(SampleEvents.show().titleEn));
    expect(find.text('Add to my calendar'), findsNothing);
    expect(find.text("View on the Town's site"), findsOneWidget);
  });

  group('silence must never look like a quiet month (principle 3)', () {
    testWidgets('stale calendar: red warning on the tab and on Today', (tester) async {
      await _pumpEvents(tester, _en, events: FakeEventsRepository(
        events: SampleEvents.all(),
        health: EventsHealth(lastSuccessAt: DateTime.now().subtract(const Duration(hours: 9))),
      ));
      await _scrollTo(tester, find.byType(EventsCard));
      expect(find.descendant(of: find.byType(EventsCard),
          matching: find.textContaining("Couldn't check the Town's calendar since")), findsOneWidget);
      await _openEventsTab(tester, AppLanguage.en);
      expect(find.textContaining("Couldn't check the Town's calendar since").hitTestable(), findsOneWidget);
    });

    testWidgets('events that can\'t load say so, not "nothing coming up"', (tester) async {
      await _pumpEvents(tester, _en, events: FakeEventsRepository(failed: true));
      await _openEventsTab(tester, AppLanguage.en);
      expect(find.text("Couldn't load the events."), findsOneWidget);
      expect(find.text(stringsFor(AppLanguage.en).eventsEmpty), findsNothing);
    });

    testWidgets('nothing upcoming, calendar fine: says the calendar has nothing', (tester) async {
      await _pumpEvents(tester, _en, events: FakeEventsRepository(events: [SampleEvents.past()]));
      await _openEventsTab(tester, AppLanguage.en);
      expect(find.text(stringsFor(AppLanguage.en).eventsEmpty), findsOneWidget);
    });
  });
}
