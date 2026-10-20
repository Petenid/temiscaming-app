import '../settings/sector.dart';

/// What goes to the curb (DESIGN §6.2): green = compost, blue = recycling,
/// black = garbage.
enum BinMaterial { compost, recycling, garbage }

/// Where a pickup came from (spec D4): the Town's calendar, or the MRC's
/// printed calendar for weeks the Town hasn't posted.
enum PickupOrigin { town, mrc }

/// One pickup for one sector, as stored in Firestore `collections/{id}` by
/// the backend (functions/src/collection/sync.ts). Plain data, so tests can
/// build them directly, and the same shape is saved on the phone.
class Pickup {
  const Pickup({
    required this.id,
    required this.date,
    required this.sector,
    this.material,
    this.special,
    this.origin = PickupOrigin.town,
    this.cancelled = false,
    this.previousDate,
    this.change,
    this.titleFr = '',
    this.titleEn = '',
    this.sourceUrlFr = '',
    this.sourceUrlEn = '',
  });

  /// "2026-10-20_town_garbage".
  final String id;

  /// The pickup day (a date, no time).
  final DateTime date;
  final Sector sector;

  /// The bin; `null` for a special collection.
  final BinMaterial? material;

  /// "christmas-trees" for special collections; `null` for bins.
  final String? special;
  final PickupOrigin origin;

  /// The Town removed this pickup from its calendar.
  final bool cancelled;

  /// Where a moved pickup used to be.
  final DateTime? previousDate;

  /// "moved", "cancelled" or "added": the latest change worth pointing out.
  final String? change;
  final String titleFr;
  final String titleEn;
  final String sourceUrlFr;
  final String sourceUrlEn;

  bool get isMoved => change == 'moved' && previousDate != null;

  /// Reads a Firestore document (or the copy saved on the phone).
  /// Returns `null` for a sector this version of the app doesn't know.
  static Pickup? fromMap(String id, Map<String, Object?> data) {
    final sector = Sector.fromId(data['sector'] as String?);
    final date = parseDay(data['date'] as String?);
    if (sector == null || date == null) return null;
    return Pickup(
      id: id,
      date: date,
      sector: sector,
      material: BinMaterial.values.asNameMap()[data['material'] as String?],
      special: data['special'] as String?,
      origin: data['origin'] == 'mrc' ? PickupOrigin.mrc : PickupOrigin.town,
      cancelled: data['status'] == 'cancelled',
      previousDate: parseDay(data['previous_date'] as String?),
      change: data['change'] as String?,
      titleFr: data['title_fr'] as String? ?? '',
      titleEn: data['title_en'] as String? ?? '',
      sourceUrlFr: data['source_url_fr'] as String? ?? '',
      sourceUrlEn: data['source_url_en'] as String? ?? '',
    );
  }

  /// The same keys as Firestore, for the copy saved on the phone.
  Map<String, Object?> toMap() => {
    'date': dayKey(date),
    'sector': sector.name,
    'material': material?.name,
    'special': special,
    'origin': origin.name,
    'status': cancelled ? 'cancelled' : 'scheduled',
    'previous_date': previousDate == null ? null : dayKey(previousDate!),
    'change': change,
    'title_fr': titleFr,
    'title_en': titleEn,
    'source_url_fr': sourceUrlFr,
    'source_url_en': sourceUrlEn,
  };
}

/// Health of the Town-calendar source (DESIGN §4), plus how far ahead
/// pickups are known.
class CollectionHealth {
  const CollectionHealth({required this.lastSuccessAt, this.lastAttemptAt, this.knownThrough});

  final DateTime? lastSuccessAt;
  final DateTime? lastAttemptAt;

  /// Last day with a known pickup (Town or MRC). After it: "not posted yet".
  final DateTime? knownThrough;

  /// The calendar is read every 2 hours (spec D2); more than two missed runs
  /// in a row shows in red.
  static const staleAfter = Duration(hours: 5);

  bool isStale(DateTime now) =>
      lastSuccessAt == null || now.difference(lastSuccessAt!) > staleAfter;

  /// From Firestore (DateTimes) or from the phone's copy (ISO strings).
  factory CollectionHealth.fromMap(Map<String, Object?> data) => CollectionHealth(
    lastSuccessAt: _time(data['last_success_at']),
    lastAttemptAt: _time(data['last_attempt_at']),
    knownThrough: parseDay(data['known_through'] as String?),
  );

  Map<String, Object?> toMap() => {
    'last_success_at': lastSuccessAt?.toIso8601String(),
    'last_attempt_at': lastAttemptAt?.toIso8601String(),
    'known_through': knownThrough == null ? null : dayKey(knownThrough!),
  };

  static DateTime? _time(Object? v) =>
      v is DateTime ? v : v is String ? DateTime.tryParse(v) : null;
}

/// "2026-10-20" → a date (local midnight); `null` if missing or malformed.
DateTime? parseDay(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return null;
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// A date → "2026-10-20".
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
