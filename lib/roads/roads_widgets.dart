import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../weather/weather_widgets.dart' show WeatherStatusLine, weatherAlertColors;
import '../widgets/dates.dart';
import 'road_data.dart';
import 'roads_repository.dart';

String roadName(AppLocalizations l10n, Road road) =>
    road == Road.route101 ? l10n.roadsRoute101 : l10n.roadsHighway63;

String roadHeading(AppLocalizations l10n, Road road) =>
    road == Road.route101 ? l10n.roadsRoute101Heading : l10n.roadsHighway63Heading;

/// "Tuesday, November 10 at 7:00 p.m." / "mardi 10 novembre à 19 h 00".
String roadWhen(BuildContext context, DateTime at) {
  final local = at.toLocal();
  return AppLocalizations.of(context).fireWhen(formatLongDay(context, local), formatTime(context, local));
}

/// "Road closed at Saint-Édouard-de-Fabre", or just the title.
String itemHeadline(AppLocalizations l10n, RoadItem item, AppLanguage language) {
  final title = item.title(language);
  return item.place.isNotEmpty && item.kind != RoadItemKind.town ? l10n.roadsAtPlace(title, item.place) : title;
}

/// "In effect since …" or "Planned from …" (never "in effect" before it starts).
String? itemStatus(BuildContext context, RoadItem item, DateTime now) {
  final l10n = AppLocalizations.of(context);
  final start = item.startsAt;
  if (item.kind == RoadItemKind.town) {
    if (start == null || item.endsAt == null) return null;
    // The Town's end is the midnight after its last day: show that day.
    final lastDay = item.endsAt!.toLocal().subtract(const Duration(minutes: 1));
    return l10n.roadsTownDates(formatDate(context, start), formatDate(context, lastDay));
  }
  if (start == null) return null;
  return item.isPlanned(now) ? l10n.roadsPlannedFrom(roadWhen(context, start)) : l10n.roadsInEffectSince(roadWhen(context, start));
}

/// The health of [sources] as a line, or null when all is well and
/// [onlyWhenProblem] is set.
({String text, bool problem})? roadsHealthLine(
  BuildContext context,
  RoadsRepository repository,
  List<String> sources,
  DateTime now, {
  bool onlyWhenProblem = false,
}) {
  final l10n = AppLocalizations.of(context);
  if (repository.loading) return null;
  if (repository.failed) return (text: l10n.roadsLoadFailed, problem: true);
  return switch (repository.health(sources, now)) {
    NeverChecked() => (text: l10n.roadsNeverChecked, problem: true),
    CheckFailing(:final oldest) => (text: l10n.roadsCheckFailedSince(formatWhen(context, oldest, now: now)), problem: true),
    CheckedRecently(:final oldest) =>
      onlyWhenProblem ? null : (text: l10n.roadsCheckedAt(formatWhen(context, oldest, now: now)), problem: false),
  };
}

/// Today's road card (spec D11): only when something's wrong on either road,
/// or a check is failing. Amber, never red (red is for boil water and fire bans).
class RoadsCard extends StatelessWidget {
  const RoadsCard({super.key, required this.settings, required this.repository, required this.onOpen, this.now});

  final AppSettings settings;
  final RoadsRepository repository;
  final VoidCallback onOpen;
  final DateTime? now;

  static const _maxLines = 3;

  /// The problems to list, most serious first.
  static List<String> problems(BuildContext context, RoadsRepository repository, AppLanguage language, DateTime now) {
    final l10n = AppLocalizations.of(context);
    final lines = <String>[];
    for (final road in Road.values) {
      for (final item in repository.itemsFor(road)) {
        if (!item.onToday) continue;
        var what = itemHeadline(l10n, item, language);
        if (item.isPlanned(now)) what = l10n.roadsPlannedShort(what, roadWhen(context, item.startsAt!));
        lines.add(l10n.roadsTodayLine(roadName(l10n, road), what));
      }
    }
    for (final road in Road.values) {
      for (final s in repository.conditions(road)?.segments ?? const <RoadSegment>[]) {
        if (!s.needsAttention) continue;
        final parts = <String>[
          if (!s.surfaceOk) s.surface(language),
          if (!s.visibilityOk) l10n.roadsVisibilityShort(s.visibility(language).toLowerCase()),
          if (s.drifting == true && s.surfaceOk && s.visibilityOk) l10n.roadsDrifting,
        ];
        final where = '${roadName(l10n, road)} (${l10n.roadsSegment(s.from(language), s.to(language))})';
        lines.add(l10n.roadsTodayLine(where, parts.join(', ')));
      }
    }
    return lines;
  }

  /// Whether Today shows the card at all.
  static bool shows(BuildContext context, RoadsRepository repository, AppLanguage language, DateTime now) =>
      problems(context, repository, language, now).isNotEmpty || staleLine(context, repository, now) != null;

  /// Any road check failing (or never done): said on Today, all year.
  static ({String text, bool problem})? staleLine(BuildContext context, RoadsRepository repository, DateTime now) {
    final l10n = AppLocalizations.of(context);
    if (repository.loading) return null;
    if (repository.failed) return (text: l10n.roadsLoadFailed, problem: true);
    final all = [for (final r in Road.values) ...r.sources];
    return switch (repository.health(all, now)) {
      NeverChecked() => (text: l10n.roadsTodayNeverChecked, problem: true),
      CheckFailing(:final oldest) => (text: l10n.roadsTodayStale(formatWhen(context, oldest, now: now)), problem: true),
      CheckedRecently() => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final language = settings.language ?? AppLanguage.fr;
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final at = now ?? DateTime.now();
        final lines = problems(context, repository, language, at);
        final stale = staleLine(context, repository, at);
        if (lines.isEmpty && stale == null) return const SizedBox.shrink(); // Today checks [shows] first
        final amber = lines.isNotEmpty;
        final colors = weatherAlertColors(context);
        final fg = amber ? colors.foreground : Theme.of(context).colorScheme.onSurface;
        final shown = lines.take(_maxLines).toList();
        final content = Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(amber ? Icons.warning_amber_rounded : Icons.directions_car_outlined, color: fg, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(l10n.roadsTitle, style: textTheme.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.bold)),
                    ),
                    for (final line in shown) ...[
                      const SizedBox(height: 4),
                      Text(line, style: textTheme.bodyLarge?.copyWith(color: fg)),
                    ],
                    if (lines.length > shown.length) ...[
                      const SizedBox(height: 4),
                      Text('+${lines.length - shown.length}', style: textTheme.bodyMedium?.copyWith(color: fg)),
                    ],
                    if (stale != null) ...[
                      const SizedBox(height: 8),
                      // On amber the line keeps the amber text colour (contrast), icon says it.
                      amber
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.error_outline, color: fg, size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: Text(stale.text, style: textTheme.bodyMedium?.copyWith(color: fg))),
                              ],
                            )
                          : WeatherStatusLine(text: stale.text, problem: true),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: fg),
            ],
          ),
        );
        return Material(
          color: amber ? colors.background : Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onOpen, child: content),
        );
      },
    );
  }
}

IconData roadItemIcon(RoadItemKind kind) => switch (kind) {
  RoadItemKind.closure => Icons.block,
  RoadItemKind.incident => Icons.warning_amber_rounded,
  RoadItemKind.roadwork => Icons.construction,
  RoadItemKind.town => Icons.engineering_outlined,
};

/// One item in a list: icon, headline, status. Tap → its own screen.
class RoadItemCard extends StatelessWidget {
  const RoadItemCard({super.key, required this.item, required this.language, required this.onTap, required this.now});

  final RoadItem item;
  final AppLanguage language;
  final VoidCallback onTap;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final status = itemStatus(context, item, now);
    final shownIn = item.displayLanguage(language);
    final strong = item.kind == RoadItemKind.closure;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(roadItemIcon(item.kind), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemHeadline(l10n, item, language),
                      style: textTheme.titleMedium?.copyWith(fontWeight: strong ? FontWeight.bold : null),
                    ),
                    if (status != null) ...[
                      const SizedBox(height: 2),
                      Text(status, style: textTheme.bodyMedium),
                    ],
                    if (shownIn != language) ...[
                      const SizedBox(height: 2),
                      Text(
                        shownIn == AppLanguage.fr ? l10n.alertOnlyFrench : l10n.alertOnlyEnglish,
                        style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// One stretch's conditions: "Témiscaming → Saint-Édouard-de-Fabre",
/// surface, visibility, drifting, since when. Flagged ones get a warning icon
/// (icon + words, never colour alone).
class SegmentConditions extends StatelessWidget {
  const SegmentConditions({super.key, required this.segment, required this.language});

  final RoadSegment segment;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final s = segment;
    final icon = s.noReport
        ? Icons.help_outline
        : s.needsAttention
        ? Icons.warning_amber_rounded
        : Icons.check_circle_outline;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.roadsSegment(s.from(language), s.to(language)), style: textTheme.titleSmall),
                const SizedBox(height: 2),
                if (s.noReport)
                  Text(l10n.roadsNoReport, style: textTheme.bodyLarge)
                else ...[
                  Text(s.surface(language), style: textTheme.bodyLarge?.copyWith(fontWeight: s.surfaceOk ? null : FontWeight.bold)),
                  if (s.visibility(language).isNotEmpty)
                    Text(
                      l10n.roadsVisibility(s.visibility(language)),
                      style: textTheme.bodyLarge?.copyWith(fontWeight: s.visibilityOk ? null : FontWeight.bold),
                    ),
                  if (s.drifting == true) Text(l10n.roadsDrifting, style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                ],
                if (s.since != null)
                  Text(l10n.roadsSince(formatWhen(context, s.since!)), style: textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Makes the image for a camera URL. The app loads it straight from Ontario
/// 511, only while the screen is open (spec D10); tests pass a stand-in.
typedef CameraImageFor = ImageProvider Function(String url);

ImageProvider networkCameraImage(String url) => NetworkImage(url);

/// One camera view: the image, when it was loaded, tap to refresh.
class CameraViewTile extends StatefulWidget {
  const CameraViewTile({super.key, required this.camera, required this.view, required this.language, required this.imageFor});

  final RoadCamera camera;
  final CameraView view;
  final AppLanguage language;
  final CameraImageFor imageFor;

  @override
  State<CameraViewTile> createState() => _CameraViewTileState();
}

class _CameraViewTileState extends State<CameraViewTile> {
  DateTime _requestedAt = DateTime.now();
  int _generation = 0;

  void _refresh() {
    // Forget the cached picture so the next build fetches a new one.
    widget.imageFor(widget.view.imageUrl).evict();
    setState(() {
      _requestedAt = DateTime.now();
      _generation++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final direction = widget.view.direction(widget.language);
    final label = direction.isEmpty ? widget.camera.location : '${widget.camera.location} · $direction';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _refresh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Image(
                key: ValueKey(_generation),
                image: widget.imageFor(widget.view.imageUrl),
                fit: BoxFit.cover,
                semanticLabel: label,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (frame == null && !wasSynchronouslyLoaded) {
                    return Center(child: Text(l10n.roadsCameraLoading, style: textTheme.bodyMedium));
                  }
                  return child;
                },
                errorBuilder: (context, error, stack) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l10n.roadsCameraUnavailable, style: textTheme.bodyLarge, textAlign: TextAlign.center),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(l10n.roadsCameraLoadedAt(formatTime(context, _requestedAt)), style: textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A health line in the app's usual style.
class RoadsHealthLine extends StatelessWidget {
  const RoadsHealthLine({super.key, required this.health});

  final ({String text, bool problem}) health;

  @override
  Widget build(BuildContext context) => WeatherStatusLine(text: health.text, problem: health.problem);
}
