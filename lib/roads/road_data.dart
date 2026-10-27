import '../settings/app_settings.dart';

/// The two roads we follow (roads spec D1), and the Town's own work.
enum Road {
  /// Route 101, Témiscaming to Ville-Marie (Quebec).
  route101('101'),

  /// Highway 63, Thorne to North Bay (Ontario).
  highway63('63');

  const Road(this.id);

  /// As the backend writes it: "101" / "63".
  final String id;

  static Road? fromId(Object? id) => Road.values.where((r) => r.id == id).firstOrNull;

  /// Firestore `road_conditions/{conditionsDoc}`.
  String get conditionsDoc => this == route101 ? 'route-101' : 'highway-63';

  /// The sources (`sources/{id}`) whose health decides whether this road
  /// was checked recently (spec D4): its items and its conditions.
  List<String> get sources => this == route101
      ? const ['mtmd-warnings', 'mtmd-roadworks', 'mtmd-conditions']
      : const ['on511-events', 'on511-construction', 'on511-conditions'];
}

/// Sources of the Town's Work Info.
const townSources = ['town-work-info'];

/// What kind of item (spec D2).
enum RoadItemKind { closure, incident, roadwork, town }

/// One item of Firestore `roads/{id}` (roads spec §5).
class RoadItem {
  const RoadItem({
    required this.id,
    required this.kind,
    required this.road,
    required this.place,
    required this.titleFr,
    required this.titleEn,
    required this.bodyFr,
    required this.bodyEn,
    required this.originalLanguage,
    required this.sourceUrlFr,
    required this.sourceUrlEn,
    required this.startsAt,
    required this.endsAt,
    required this.onToday,
  });

  final String id;
  final RoadItemKind kind;

  /// Null for the Town's work.
  final Road? road;
  final String place;
  final String titleFr;
  final String titleEn;
  final String bodyFr;
  final String bodyEn;

  /// "fr", "en" or "both".
  final String originalLanguage;
  final String sourceUrlFr;
  final String sourceUrlEn;
  final DateTime? startsAt;

  /// The planned end; items can outlast it (spec D5). Null if none given.
  final DateTime? endsAt;

  /// The backend's "goes on Today" flag (spec D11).
  final bool onToday;

  /// Never "in effect" before it starts (DESIGN §8).
  bool isPlanned(DateTime now) => startsAt != null && startsAt!.isAfter(now);

  /// The language the text is shown in: the user's, unless the source
  /// wrote it in the other one only (DESIGN §5, never machine-translated).
  /// Only the source's own words count: our labels ("Road closed") exist in
  /// both languages and say nothing about the source. The Town's titles are
  /// its own words, so they count for its items.
  AppLanguage displayLanguage(AppLanguage language) {
    final town = kind == RoadItemKind.town;
    final hasFr = bodyFr.isNotEmpty || (town && titleFr.isNotEmpty);
    final hasEn = bodyEn.isNotEmpty || (town && titleEn.isNotEmpty);
    if (language == AppLanguage.fr) return hasFr || !hasEn ? AppLanguage.fr : AppLanguage.en;
    return hasEn || !hasFr ? AppLanguage.en : AppLanguage.fr;
  }

  /// The first non-empty line of the source's text ("" if none): usually
  /// where it is, e.g. "À Duhamel-Ouest et Saint-Bruno-de-Guigues entre …".
  String firstLine(AppLanguage language) =>
      body(language).split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');

  /// Our own label (Quebec warnings, Ontario items) or the Town's title, in
  /// the user's language when it exists.
  String title(AppLanguage language) {
    final mine = language == AppLanguage.fr ? titleFr : titleEn;
    if (mine.isNotEmpty) return mine;
    return language == AppLanguage.fr ? titleEn : titleFr;
  }

  /// The source's text, in the language [displayLanguage] picked.
  String body(AppLanguage language) => displayLanguage(language) == AppLanguage.fr ? bodyFr : bodyEn;

  String sourceUrl(AppLanguage language) {
    final mine = language == AppLanguage.fr ? sourceUrlFr : sourceUrlEn;
    return mine.isNotEmpty ? mine : (sourceUrlFr.isNotEmpty ? sourceUrlFr : sourceUrlEn);
  }

  static RoadItem? fromMap(Map<String, Object?> m) {
    final id = m['id'];
    final kind = RoadItemKind.values.where((k) => k.name == m['kind']).firstOrNull;
    if (id is! String || kind == null) return null;
    String s(String k) => m[k] is String ? m[k]! as String : '';
    return RoadItem(
      id: id,
      kind: kind,
      road: Road.fromId(m['road']),
      place: s('place'),
      titleFr: s('title_fr'),
      titleEn: s('title_en'),
      bodyFr: s('body_fr'),
      bodyEn: s('body_en'),
      originalLanguage: s('original_language'),
      sourceUrlFr: s('source_url_fr'),
      sourceUrlEn: s('source_url_en'),
      startsAt: m['starts_at'] as DateTime?,
      endsAt: m['ends_at'] as DateTime?,
      // An unknown kind was dropped above; a closure is always worth Today.
      onToday: m['on_today'] == true || kind == RoadItemKind.closure,
    );
  }
}

/// One stretch's conditions (`road_conditions/{doc}.segments[]`).
class RoadSegment {
  const RoadSegment({
    required this.fromFr,
    required this.fromEn,
    required this.toFr,
    required this.toEn,
    required this.surfaceFr,
    required this.surfaceEn,
    required this.surfaceOk,
    required this.visibilityFr,
    required this.visibilityEn,
    required this.visibilityOk,
    required this.drifting,
    required this.noReport,
    required this.since,
  });

  final String fromFr, fromEn, toFr, toEn;
  final String surfaceFr, surfaceEn;
  final bool surfaceOk;
  final String visibilityFr, visibilityEn;
  final bool visibilityOk;
  final bool? drifting;

  /// Ontario's "No Report": neither flagged nor "clear".
  final bool noReport;
  final DateTime? since;

  /// Spec D11: snow, ice, poor visibility or drifting goes on Today.
  bool get needsAttention => !noReport && (!surfaceOk || !visibilityOk || drifting == true);

  String from(AppLanguage l) => l == AppLanguage.fr ? fromFr : fromEn;
  String to(AppLanguage l) => l == AppLanguage.fr ? toFr : toEn;
  String surface(AppLanguage l) => (l == AppLanguage.fr ? surfaceFr : surfaceEn).ifEmpty(surfaceFr);
  String visibility(AppLanguage l) => (l == AppLanguage.fr ? visibilityFr : visibilityEn).ifEmpty(visibilityEn);

  static RoadSegment fromMap(Map<String, Object?> m) {
    String s(String k) => m[k] is String ? m[k]! as String : '';
    return RoadSegment(
      fromFr: s('from_fr'),
      fromEn: s('from_en'),
      toFr: s('to_fr'),
      toEn: s('to_en'),
      surfaceFr: s('surface_fr'),
      surfaceEn: s('surface_en'),
      // Anything unclear counts as worth a look, never as fine.
      surfaceOk: m['surface_ok'] == true,
      visibilityFr: s('visibility_fr'),
      visibilityEn: s('visibility_en'),
      visibilityOk: m['visibility_ok'] == true,
      drifting: m['drifting'] as bool?,
      noReport: m['no_report'] == true,
      since: m['since'] as DateTime?,
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// `road_conditions/route-101` or `road_conditions/highway-63`.
class RoadConditions {
  const RoadConditions({required this.segments, required this.inSeason, required this.checkedAt});

  final List<RoadSegment> segments;

  /// Quebec only: false outside 15 Oct – 15 Apr, when winter conditions
  /// aren't published (null for Ontario).
  final bool? inSeason;
  final DateTime? checkedAt;

  static RoadConditions fromMap(Map<String, Object?> m) => RoadConditions(
    segments: [
      for (final s in (m['segments'] as List?) ?? const [])
        if (s is Map) RoadSegment.fromMap(s.cast<String, Object?>()),
    ],
    inSeason: m['in_season'] as bool?,
    checkedAt: m['checked_at'] as DateTime?,
  );
}

/// One camera view (`road_cameras/highway-63.cameras[].views[]`).
class CameraView {
  const CameraView({required this.imageUrl, required this.directionFr, required this.directionEn});

  final String imageUrl;
  final String directionFr;
  final String directionEn;

  String direction(AppLanguage l) => l == AppLanguage.fr ? directionFr : directionEn;
}

/// A Highway 63 camera (spec D10).
class RoadCamera {
  const RoadCamera({required this.location, required this.views});

  /// As Ontario names it, e.g. "Highway 63 at Wyse Road" (English only).
  final String location;
  final List<CameraView> views;

  static List<RoadCamera> listFromMap(Map<String, Object?> m) => [
    for (final c in (m['cameras'] as List?) ?? const [])
      if (c is Map)
        RoadCamera(
          location: c['location'] is String ? c['location'] as String : '',
          views: [
            for (final v in (c['views'] as List?) ?? const [])
              if (v is Map && v['image_url'] is String && (v['image_url'] as String).startsWith('https://'))
                CameraView(
                  imageUrl: v['image_url'] as String,
                  directionFr: v['direction_fr'] is String ? v['direction_fr'] as String : '',
                  directionEn: v['direction_en'] is String ? v['direction_en'] as String : '',
                ),
          ],
        ),
  ].where((c) => c.views.isNotEmpty).toList();
}

/// Official maps (spec D12).
class RoadLinks {
  static const quebec511Fr = 'https://www.quebec511.info/fr/';
  static const quebec511En = 'https://www.quebec511.info/en/';
  static const ontario511Fr = 'https://511on.ca/fr/';
  static const ontario511En = 'https://511on.ca/';
  static const townFr = 'https://www.temiscaming.net/fr/info-travaux';
  static const townEn = 'https://www.temiscaming.net/en/work-info';
}

/// How long a check stays fresh before the app says it couldn't check
/// (spec D4): roads are read every 15 minutes, the Town every hour.
Duration staleAfter(String source) =>
    source == 'town-work-info' ? const Duration(hours: 3) : const Duration(hours: 1);
