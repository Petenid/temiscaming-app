import '../settings/sector.dart';
import 'pickup.dart';

/// Pure date logic for the collection screens and reminders: no widgets, no
/// Firebase, so it's easy to test.

/// The date part only (local midnight).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday of the week containing [d].
DateTime mondayOf(DateTime d) {
  final day = dateOnly(d);
  return DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));
}

/// [d] plus [days] calendar days (safe across daylight-saving changes).
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Everything happening on one day for one sector.
class PickupDay {
  PickupDay(this.date, List<Pickup> pickups)
    : pickups = List.unmodifiable(pickups..sort(_order));

  final DateTime date;
  final List<Pickup> pickups;

  /// Bins to put out (not cancelled), in the order green, blue, black.
  List<BinMaterial> get bins => [
    for (final p in pickups)
      if (p.material != null && !p.cancelled) p.material!,
  ];

  bool get hasBins => bins.isNotEmpty;

  static int _order(Pickup a, Pickup b) {
    // Bins first (green, blue, black), then special collections.
    final ai = a.material?.index ?? 99;
    final bi = b.material?.index ?? 99;
    return ai != bi ? ai - bi : a.id.compareTo(b.id);
  }
}

/// The sector's pickups from [from] until (not including) [until], grouped
/// by day. Cancelled pickups are included (screens label them); use
/// [PickupDay.bins] for what actually goes out.
List<PickupDay> pickupDays(
  List<Pickup> all,
  Sector sector, {
  required DateTime from,
  DateTime? until,
}) {
  final start = dateOnly(from);
  final byDay = <DateTime, List<Pickup>>{};
  for (final p in all) {
    if (p.sector != sector || p.date.isBefore(start)) continue;
    if (until != null && !p.date.isBefore(dateOnly(until))) continue;
    byDay.putIfAbsent(p.date, () => []).add(p);
  }
  final days = byDay.entries.map((e) => PickupDay(e.key, e.value)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return days;
}

/// How Today describes the next pickup.
enum WhenLabel { today, thisWeek, nextWeek, later }

WhenLabel whenLabel(DateTime pickup, DateTime today) {
  if (sameDay(pickup, today)) return WhenLabel.today;
  final week = mondayOf(today);
  if (pickup.isBefore(addDays(week, 7))) return WhenLabel.thisWeek;
  if (pickup.isBefore(addDays(week, 14))) return WhenLabel.nextWeek;
  return WhenLabel.later;
}

/// What the Today card shows (spec §6, App).
class CollectionOverview {
  const CollectionOverview({
    required this.next,
    required this.then,
    required this.noPickupThisWeek,
    required this.specialsThisWeek,
    required this.notPostedAfter,
  });

  /// The next day with bins to put out (today counts), or `null`.
  final PickupDay? next;

  /// The one after it.
  final PickupDay? then;

  /// The Town cancelled this week's pickup and nothing replaces it.
  final bool noPickupThisWeek;

  /// Christmas trees etc. still to come this week.
  final List<Pickup> specialsThisWeek;

  /// Set when pickups are only known up to this day and it's less than two
  /// weeks away: the card says what's beyond isn't posted yet (spec D4).
  final DateTime? notPostedAfter;
}

/// How far ahead pickups must be known before the card stops warning.
const knownAheadWanted = 14;

CollectionOverview overview(
  List<Pickup> all,
  Sector sector,
  DateTime now, {
  DateTime? knownThrough,
}) {
  final today = dateOnly(now);
  final sunday = addDays(mondayOf(today), 6);
  final days = pickupDays(all, sector, from: today);
  final binDays = days.where((d) => d.hasBins).toList();
  final next = binDays.firstOrNull;
  final thisWeek = days.where((d) => !d.date.isAfter(sunday));
  final cancelledThisWeek = thisWeek.any((d) => d.pickups.any((p) => p.cancelled));
  final binsThisWeek = thisWeek.any((d) => d.hasBins);

  // Last known pickup: the backend's figure, or the last one we have.
  final lastKnown = knownThrough ?? (binDays.isEmpty ? null : binDays.last.date);
  final notPostedAfter =
      lastKnown != null && lastKnown.isBefore(addDays(today, knownAheadWanted)) ? lastKnown : null;

  return CollectionOverview(
    next: next,
    then: binDays.length > 1 ? binDays[1] : null,
    noPickupThisWeek: cancelledThisWeek && !binsThisWeek,
    specialsThisWeek: [
      for (final d in thisWeek)
        for (final p in d.pickups)
          if (p.special != null && !p.cancelled) p,
    ],
    notPostedAfter: notPostedAfter,
  );
}
