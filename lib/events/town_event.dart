import '../collection/pickup.dart' show parseDay;
import '../collection/schedule.dart' show addDays, dateOnly;
import '../settings/app_settings.dart';

/// What kind of event it is, read by the backend from the Town's icon
/// (events spec D4).
enum EventCategory { council, closure, serviceCanada, culture, community }

/// A Town event, as stored in Firestore `events/{id}` by the backend
/// (functions/src/events/sync.ts). Plain data: no Firebase types, so tests
/// can build them directly.
///
/// Events are all-day: the Town's calendar gives no times (spec §2).
class TownEvent {
  const TownEvent({
    required this.id,
    required this.category,
    required this.titleFr,
    required this.titleEn,
    required this.placeFr,
    required this.placeEn,
    required this.startsOn,
    required this.endsOn,
    required this.sourceUrlFr,
    required this.sourceUrlEn,
  });

  final String id;
  final EventCategory category;

  /// The Town's titles; either (rarely both) can be empty.
  final String titleFr;
  final String titleEn;
  final String placeFr;
  final String placeEn;

  /// First and last day, at local midnight. Equal for a one-day event.
  final DateTime startsOn;
  final DateTime endsOn;
  final String sourceUrlFr;
  final String sourceUrlEn;

  bool get isMultiDay => endsOn.isAfter(startsOn);

  /// The Town gave no title in either language (spec D3): screens show our
  /// category name instead, in italics.
  bool get isUntitled => titleFr.isEmpty && titleEn.isEmpty;

  /// The language to show the title in: the user's if the Town wrote one,
  /// otherwise the other (DESIGN §5 — never machine-translated).
  AppLanguage displayLanguage(AppLanguage preferred) {
    final mine = preferred == AppLanguage.fr ? titleFr : titleEn;
    if (mine.isNotEmpty || isUntitled) return preferred;
    return preferred == AppLanguage.fr ? AppLanguage.en : AppLanguage.fr;
  }

  /// The Town's title, or "" when untitled.
  String title(AppLanguage language) =>
      displayLanguage(language) == AppLanguage.fr ? titleFr : titleEn;

  /// The place in the user's language if given, otherwise the other one.
  String place(AppLanguage language) {
    final mine = language == AppLanguage.fr ? placeFr : placeEn;
    return mine.isNotEmpty ? mine : (language == AppLanguage.fr ? placeEn : placeFr);
  }

  String sourceUrl(AppLanguage language) {
    final mine = language == AppLanguage.fr ? sourceUrlFr : sourceUrlEn;
    return mine.isNotEmpty ? mine : (language == AppLanguage.fr ? sourceUrlEn : sourceUrlFr);
  }

  /// Still on or coming up on [today].
  bool isUpcoming(DateTime today) => !endsOn.isBefore(dateOnly(today));

  /// The day it's listed under: its first day, or today if already running.
  DateTime listedOn(DateTime today) {
    final day = dateOnly(today);
    return startsOn.isBefore(day) ? day : startsOn;
  }

  static const _categories = {
    'council': EventCategory.council,
    'closure': EventCategory.closure,
    'service-canada': EventCategory.serviceCanada,
    'culture': EventCategory.culture,
    'community': EventCategory.community,
  };

  /// Builds an event from a Firestore document. Returns null if its dates are
  /// unreadable, rather than guessing them.
  static TownEvent? fromMap(String id, Map<String, Object?> data) {
    String text(String key) => (data[key] as String?) ?? '';
    final starts = parseDay(data['starts_on'] as String?);
    final ends = parseDay(data['ends_on'] as String?) ?? starts;
    if (starts == null || ends == null) return null;
    return TownEvent(
      id: id,
      category: _categories[data['category']] ?? EventCategory.community,
      titleFr: text('title_fr'),
      titleEn: text('title_en'),
      placeFr: text('place_fr'),
      placeEn: text('place_en'),
      startsOn: starts,
      endsOn: ends.isBefore(starts) ? starts : ends,
      sourceUrlFr: text('source_url_fr'),
      sourceUrlEn: text('source_url_en'),
    );
  }
}

/// How recently the backend read the Town's calendar for events
/// (Firestore `sources/town-events`).
class EventsHealth {
  const EventsHealth({required this.lastSuccessAt, this.listedThrough});

  final DateTime? lastSuccessAt;

  /// Last day of the months the backend reads: the "not posted yet" line.
  final DateTime? listedThrough;

  /// Checked every 2 hours, like the bin schedule: red after two missed runs.
  static const staleAfter = Duration(hours: 5);

  bool isStale(DateTime now) =>
      lastSuccessAt == null || now.difference(lastSuccessAt!) > staleAfter;

  factory EventsHealth.fromMap(Map<String, Object?> data) => EventsHealth(
    lastSuccessAt: data['last_success_at'] as DateTime?,
    listedThrough: parseDay(data['listed_through'] as String?),
  );
}

/// The events listed under one day.
class EventDay {
  EventDay(this.date, this.events);

  final DateTime date;
  final List<TownEvent> events;
}

/// Upcoming events grouped by day, soonest first (spec §6). A multi-day
/// event appears once: under its first day, or under today if it's running.
List<EventDay> agenda(List<TownEvent> events, DateTime today) {
  final byDay = <DateTime, List<TownEvent>>{};
  for (final e in events.where((e) => e.isUpcoming(today))) {
    byDay.putIfAbsent(e.listedOn(today), () => []).add(e);
  }
  // Within a day: earliest start first (a running closure before today's
  // show), then by the Town's event number so the order never jumps around.
  int byStart(TownEvent a, TownEvent b) {
    final c = a.startsOn.compareTo(b.startsOn);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  final days = byDay.keys.toList()..sort();
  return [for (final d in days) EventDay(d, byDay[d]!..sort(byStart))];
}

/// The next [count] upcoming events, for the Today card (spec D10).
List<TownEvent> nextEvents(List<TownEvent> events, DateTime today, {int count = 3}) =>
    [for (final day in agenda(events, today)) ...day.events].take(count).toList();

/// Today, tomorrow, or another day: how the Today card names a date.
enum EventWhen { today, tomorrow, later }

EventWhen eventWhen(DateTime day, DateTime today) {
  final t = dateOnly(today);
  if (!day.isAfter(t)) return EventWhen.today;
  if (day == addDays(t, 1)) return EventWhen.tomorrow;
  return EventWhen.later;
}
