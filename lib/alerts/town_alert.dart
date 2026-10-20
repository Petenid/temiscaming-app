import '../settings/app_settings.dart';

/// How long an advisory the Town never marked "lifted" still counts as
/// current (spec §5). The real data has 2025 boil-water advisories that were
/// never marked lifted; without this cap they'd show as "in effect" forever.
/// Only a fallback now: the backend stores each alert's own end
/// (`in_effect_until`, spec §5b) — 30 days for water advisories, less for
/// general notices.
const currentAdvisoryWindow = Duration(days: 30);

/// The Town's own status for an alert.
enum AlertStatus { active, lifted, expired }

/// A manual correction made in the Firebase console (spec §5c).
enum AlertOverride { over, inEffect }

/// A town alert, as stored in Firestore `alerts/{id}` by the backend
/// (functions/src/alerts/sync.ts). Plain data: no Firebase types, so tests
/// can build them directly.
class TownAlert {
  const TownAlert({
    required this.id,
    required this.category,
    required this.isLiftingNotice,
    required this.status,
    required this.titleFr,
    required this.titleEn,
    required this.bodyFr,
    required this.bodyEn,
    required this.bodyIsExcerpt,
    required this.sourceUrlFr,
    required this.sourceUrlEn,
    required this.publishedAt,
    this.inEffectUntil,
    this.manualOverride,
  });

  final String id;

  /// "boil-water", "water-interruption", "water-main-break", "cloudy-water",
  /// "water-restriction", "traffic" or "other".
  final String category;

  /// A notice announcing that an advisory is over.
  final bool isLiftingNotice;
  final AlertStatus status;
  final String titleFr;
  final String titleEn;
  final String bodyFr;
  final String bodyEn;

  /// The body is only the Town's short summary, not the full notice.
  final bool bodyIsExcerpt;
  final String sourceUrlFr;
  final String sourceUrlEn;
  final DateTime publishedAt;

  /// When it stops counting as in effect if the Town never marks it lifted
  /// (spec §5b). Null on alerts saved before the backend computed it.
  final DateTime? inEffectUntil;

  /// A manual correction; wins over everything else (spec §5c).
  final AlertOverride? manualOverride;

  static const _waterCategories = {
    'boil-water',
    'water-interruption',
    'water-main-break',
    'cloudy-water',
    'water-restriction',
  };

  bool get isWater => _waterCategories.contains(category);

  /// An advisory the Town hasn't lifted and that hasn't run out (its own
  /// end date, or 30 days), unless someone corrected it by hand.
  bool isInEffect(DateTime now) {
    if (isLiftingNotice) return false;
    return switch (manualOverride) {
      AlertOverride.over => false,
      AlertOverride.inEffect => true,
      null =>
        status == AlertStatus.active &&
            now.isBefore(inEffectUntil ?? publishedAt.add(currentAdvisoryWindow)),
    };
  }

  /// Drives the red banner on Today.
  bool isBoilWaterInEffect(DateTime now) =>
      category == 'boil-water' && isInEffect(now);

  /// True when the alert exists in [language] on the Town's site.
  bool hasLanguage(AppLanguage language) =>
      (language == AppLanguage.fr ? titleFr : titleEn).isNotEmpty;

  /// The language to show it in: the user's if available, otherwise the
  /// one the Town wrote it in (DESIGN §5 — never machine-translated).
  AppLanguage displayLanguage(AppLanguage preferred) =>
      hasLanguage(preferred)
      ? preferred
      : (preferred == AppLanguage.fr ? AppLanguage.en : AppLanguage.fr);

  String title(AppLanguage language) =>
      displayLanguage(language) == AppLanguage.fr ? titleFr : titleEn;

  String body(AppLanguage language) =>
      displayLanguage(language) == AppLanguage.fr ? bodyFr : bodyEn;

  String sourceUrl(AppLanguage language) =>
      displayLanguage(language) == AppLanguage.fr ? sourceUrlFr : sourceUrlEn;

  /// Builds an alert from a Firestore document whose timestamps have
  /// already been turned into [DateTime]s.
  factory TownAlert.fromMap(String id, Map<String, Object?> data) {
    String text(String key) => (data[key] as String?) ?? '';
    return TownAlert(
      id: id,
      category: text('category'),
      isLiftingNotice: data['kind'] == 'lifting-notice',
      status: AlertStatus.values.asNameMap()[data['status']] ??
          AlertStatus.active,
      titleFr: text('title_fr'),
      titleEn: text('title_en'),
      bodyFr: text('body_fr'),
      bodyEn: text('body_en'),
      bodyIsExcerpt: data['body_is_excerpt'] == true,
      sourceUrlFr: text('source_url_fr'),
      sourceUrlEn: text('source_url_en'),
      publishedAt: data['published_at'] as DateTime,
      inEffectUntil: data['in_effect_until'] as DateTime?,
      manualOverride: switch (data['override']) {
        'over' => AlertOverride.over,
        'in-effect' => AlertOverride.inEffect,
        _ => null,
      },
    );
  }
}

/// How recently the backend managed to read the Town's alert site
/// (Firestore `sources/alertes-municipales`, DESIGN §4 "source health").
class SourceHealth {
  const SourceHealth({required this.lastSuccessAt, required this.lastAttemptAt});

  final DateTime? lastSuccessAt;
  final DateTime? lastAttemptAt;

  /// The backend checks every 10 minutes; three missed checks means trouble.
  static const staleAfter = Duration(minutes: 30);

  bool isStale(DateTime now) =>
      lastSuccessAt == null || now.difference(lastSuccessAt!) > staleAfter;

  factory SourceHealth.fromMap(Map<String, Object?> data) => SourceHealth(
    lastSuccessAt: data['last_success_at'] as DateTime?,
    lastAttemptAt: data['last_attempt_at'] as DateTime?,
  );
}
