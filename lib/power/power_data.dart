/// Power outages in Témiscaming (Milestone 8, specs/power-outages.md),
/// read from the one Firestore document `power/temiscaming` the backend writes.
library;

/// Where an interruption is (spec D1): the town (Lumsden and Letang
/// included), or Lac Tee, which Hydro-Québec files under Kipawa.
enum PowerArea { temiscaming, lacTee }

/// What a current interruption is (spec D2).
enum OutageKind {
  /// An outage (Hydro-Québec type "P").
  outage,

  /// Planned work under way (type "I"): the power is off on purpose.
  plannedInProgress,
}

/// Hydro-Québec's crew status (A / R / L); unknown codes are left blank.
enum CrewStatus { assigned, onTheWay, atWork }

/// Cause groups from Hydro-Québec's documentation (spec D8).
enum OutageCause { equipment, weather, accident, vegetation, animal, plannedWork }

T? _enumByWire<T extends Enum>(List<T> values, Object? wire) {
  if (wire is! String) return null;
  // The backend writes snake_case ("on_the_way"); the app's names are camelCase.
  final name = wire.replaceAllMapped(RegExp(r'_([a-z])'), (m) => m[1]!.toUpperCase());
  return values.where((v) => v.name == name).firstOrNull;
}

/// One current interruption here.
class Outage {
  const Outage({
    required this.kind,
    required this.customers,
    required this.startedAt,
    required this.area,
    this.estimatedEndAt,
    this.status,
    this.cause,
  });

  final OutageKind kind;
  final int customers;
  final DateTime startedAt;

  /// Hydro-Québec's estimate, never a promise; often missing at first.
  final DateTime? estimatedEndAt;
  final CrewStatus? status;
  final OutageCause? cause;
  final PowerArea area;

  static Outage? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, Object?>();
    final started = m['started_at'];
    final customers = m['customers'];
    if (started is! DateTime || customers is! num) return null;
    return Outage(
      // An unknown kind is shown as an outage: the power is still off.
      kind: _enumByWire(OutageKind.values, m['kind']) ?? OutageKind.outage,
      customers: customers.round(),
      startedAt: started,
      estimatedEndAt: m['estimated_end_at'] as DateTime?,
      status: _enumByWire(CrewStatus.values, m['status']),
      cause: _enumByWire(OutageCause.values, m['cause']),
      area: _enumByWire(PowerArea.values, m['area']) ?? PowerArea.temiscaming,
    );
  }
}

/// One upcoming planned interruption here.
class PlannedInterruption {
  const PlannedInterruption({
    required this.customers,
    required this.startsAt,
    required this.endsAt,
    required this.area,
    this.originalStartsAt,
    this.alternateStartsAt,
    this.alternateEndsAt,
  });

  final int customers;

  /// The window currently scheduled.
  final DateTime startsAt;
  final DateTime endsAt;

  /// Set when the work was moved from its first date.
  final DateTime? originalStartsAt;

  /// Hydro-Québec's backup date, in case the work can't go ahead.
  final DateTime? alternateStartsAt;
  final DateTime? alternateEndsAt;
  final PowerArea area;

  static PlannedInterruption? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, Object?>();
    final starts = m['starts_at'], ends = m['ends_at'];
    final customers = m['customers'];
    if (starts is! DateTime || ends is! DateTime || customers is! num) return null;
    final altStart = m['alternate_starts_at'], altEnd = m['alternate_ends_at'];
    final hasAlternate = altStart is DateTime && altEnd is DateTime;
    return PlannedInterruption(
      customers: customers.round(),
      startsAt: starts,
      endsAt: ends,
      originalStartsAt: m['original_starts_at'] as DateTime?,
      alternateStartsAt: hasAlternate ? altStart : null,
      alternateEndsAt: hasAlternate ? altEnd : null,
      area: _enumByWire(PowerArea.values, m['area']) ?? PowerArea.temiscaming,
    );
  }
}

/// Hydro-Québec's pages (spec D10). The backend stores the map links too,
/// so they can change without an app update; these are used when it hasn't.
class PowerLinks {
  static const mapFr = 'https://infopannes.solutions.hydroquebec.com/info-pannes?langue=fr';
  static const mapEn = 'https://infopannes.solutions.hydroquebec.com/info-pannes?langue=en';

  /// To report an outage, 24 hours a day (hydroquebec.com/pannes/en-cas-de-panne, 2026-10-27).
  static const reportPhone = '1 800 790-2424';
  static const reportPhoneUri = 'tel:+18007902424';
}

/// Firestore `power/temiscaming` (spec §5).
class PowerStatus {
  const PowerStatus({
    this.outages = const [],
    this.planned = const [],
    this.outagesCheckedAt,
    this.plannedCheckedAt,
    this.mapUrlFr = PowerLinks.mapFr,
    this.mapUrlEn = PowerLinks.mapEn,
  });

  /// Current interruptions here, biggest first (as the backend sorts them).
  final List<Outage> outages;

  /// Upcoming planned interruptions here, soonest first.
  final List<PlannedInterruption> planned;

  /// When each list was last read successfully: its health. Null until the
  /// backend has read it once.
  final DateTime? outagesCheckedAt;
  final DateTime? plannedCheckedAt;
  final String mapUrlFr;
  final String mapUrlEn;

  /// Current outages are checked every 15 minutes: red after 4 missed runs (spec D4).
  static const outagesStaleAfter = Duration(hours: 1);

  /// Planned interruptions are checked hourly: red after 3 missed runs.
  static const plannedStaleAfter = Duration(hours: 3);

  bool outagesStale(DateTime now) =>
      outagesCheckedAt == null || now.difference(outagesCheckedAt!) > outagesStaleAfter;
  bool plannedStale(DateTime now) =>
      plannedCheckedAt == null || now.difference(plannedCheckedAt!) > plannedStaleAfter;

  /// Planned interruptions still to come at [now] (the backend refreshes
  /// hourly; one that has started shows as "in progress" in [outages]).
  List<PlannedInterruption> upcoming(DateTime now) => [
    for (final p in planned)
      if (p.startsAt.isAfter(now)) p,
  ];

  /// Those starting today or tomorrow (Témiscaming time = the phone's): Today's card (spec D9).
  List<PlannedInterruption> soon(DateTime now) {
    final local = now.toLocal();
    final dayAfterTomorrow = DateTime(local.year, local.month, local.day + 2);
    return [
      for (final p in upcoming(now))
        if (p.startsAt.toLocal().isBefore(dayAfterTomorrow)) p,
    ];
  }

  factory PowerStatus.fromMap(Map<String, Object?> m) {
    String link(String k, String fallback) {
      final v = m[k];
      return v is String && v.startsWith('https://') ? v : fallback;
    }

    List<T> list<T>(Object? raw, T? Function(Object?) read) =>
        raw is List ? [for (final x in raw) read(x)].whereType<T>().toList() : <T>[];

    return PowerStatus(
      outages: list(m['outages'], Outage.fromMap),
      planned: list(m['planned'], PlannedInterruption.fromMap),
      outagesCheckedAt: m['outages_checked_at'] as DateTime?,
      plannedCheckedAt: m['planned_checked_at'] as DateTime?,
      mapUrlFr: link('map_url_fr', PowerLinks.mapFr),
      mapUrlEn: link('map_url_en', PowerLinks.mapEn),
    );
  }
}
