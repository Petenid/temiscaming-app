import 'package:community/collection/schedule.dart';
import 'package:community/events/calendar_adder.dart';
import 'package:community/events/events_repository.dart';
import 'package:community/events/town_event.dart';

/// Events held in memory; tests set them and the screens update.
class FakeEventsRepository extends EventsRepository {
  FakeEventsRepository({
    List<TownEvent> events = const [],
    EventsHealth? health,
    bool loading = false,
    bool failed = false,
  }) : _events = events,
       _health = health ??
           EventsHealth(
             lastSuccessAt: DateTime.now(),
             listedThrough: addDays(dateOnly(DateTime.now()), 60),
           ),
       _loading = loading,
       _failed = failed;

  List<TownEvent> _events;
  EventsHealth? _health;
  bool _loading;
  bool _failed;

  @override
  List<TownEvent> get events => _events;
  @override
  EventsHealth? get health => _health;
  @override
  bool get loading => _loading;
  @override
  bool get failed => _failed;

  void set({List<TownEvent>? events, EventsHealth? health, bool? failed}) {
    _events = events ?? _events;
    _health = health ?? _health;
    _failed = failed ?? _failed;
    _loading = false;
    notifyListeners();
  }
}

/// Records what the app asked the phone's calendar to add.
class FakeCalendarAdder implements CalendarAdder {
  FakeCalendarAdder({this.isSupported = true, this.outcome = CalendarOutcome.opened});

  @override
  final bool isSupported;
  CalendarOutcome outcome;
  final requests = <CalendarRequest>[];

  @override
  Future<CalendarOutcome> add(CalendarRequest request) async {
    requests.add(request);
    return outcome;
  }
}

/// Sample events modelled on real entries of the Town's 2026 calendar, placed
/// around today so the screens always have something upcoming.
class SampleEvents {
  static DateTime day(int fromToday) => addDays(dateOnly(DateTime.now()), fromToday);

  static TownEvent _event({
    required String id,
    required EventCategory category,
    required String titleFr,
    required String titleEn,
    String placeFr = '',
    String placeEn = '',
    required int starts,
    int? ends,
  }) => TownEvent(
    id: id,
    category: category,
    titleFr: titleFr,
    titleEn: titleEn,
    placeFr: placeFr,
    placeEn: placeEn,
    startsOn: day(starts),
    endsOn: day(ends ?? starts),
    sourceUrlFr: titleFr.isEmpty && titleEn.isEmpty
        ? 'https://www.temiscaming.net/fr/evenements/2026/3/11/$id/'
        : 'https://www.temiscaming.net/fr/evenements/2026/12/21/$id/evenement',
    sourceUrlEn: titleEn.isEmpty && titleFr.isNotEmpty
        ? ''
        : 'https://www.temiscaming.net/en/events/2026/12/21/$id/event',
  );

  /// Town hall closed, started yesterday, ends in two days: listed under today.
  static TownEvent townHallClosed() => _event(
    id: '143335',
    category: EventCategory.closure,
    titleFr: 'HÔTEL DE VILLE FERMÉ',
    titleEn: 'TOWN HALL CLOSED',
    starts: -1,
    ends: 2,
  );

  static TownEvent councilTomorrow() => _event(
    id: '140962',
    category: EventCategory.council,
    titleFr: 'Séance ordinaire du conseil',
    titleEn: 'Regular session',
    placeFr: 'Le Centre - Salon Desjardins',
    placeEn: 'Le Centre - Salon Desjardins',
    starts: 1,
  );

  static TownEvent show() => _event(
    id: '145427',
    category: EventCategory.culture,
    titleFr: 'MIA KELLY À LA SALLE DOTTORI! - BILLETS GRATUITS!',
    titleEn: 'MIA KELLY AT DOTTORI HALL! - FREE TICKETS!',
    placeFr: 'Le Centre - Salle Dottori',
    placeEn: 'The Centre - Dottori Hall',
    starts: 5,
  );

  /// The Town once posted a council meeting with no title (spec D3).
  static TownEvent untitledCouncil() => _event(
    id: '143095',
    category: EventCategory.council,
    titleFr: '',
    titleEn: '',
    placeFr: 'Le Centre - Salon Desjardins',
    placeEn: 'Le Centre - Salon Desjardins',
    starts: 10,
  );

  /// On the French calendar only.
  static TownEvent frenchOnly() => _event(
    id: '144118',
    category: EventCategory.community,
    titleFr: 'SOUPER MISSION TOURNESOL',
    titleEn: '',
    placeFr: 'Le Centre - Salle Dottori',
    starts: 12,
  );

  /// Ended yesterday: never listed.
  static TownEvent past() => _event(
    id: '144379',
    category: EventCategory.community,
    titleFr: 'RASSEMBLEMENT CITOYEN',
    titleEn: 'COMMUNITY GATHERING',
    starts: -1,
  );

  static List<TownEvent> all() =>
      [show(), past(), frenchOnly(), councilTomorrow(), untitledCouncil(), townHallClosed()];
}
