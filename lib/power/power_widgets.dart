import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../weather/weather_widgets.dart';
import '../widgets/dates.dart';
import 'power_data.dart';
import 'power_repository.dart';

/// A time that never breaks across lines, written the Quebec way in French
/// ("8 h 30", "12 h", "19 h 37"; the date library gives "08 h 30", "12 h 00").
String _time(BuildContext context, DateTime at) {
  var t = formatTime(context, at);
  if (Localizations.localeOf(context).languageCode == 'fr') {
    t = t.replaceFirst(RegExp(r'^0(?=\d)'), '')
        .replaceFirstMapped(RegExp(r'(\d)[\s\u00A0\u202F]?h[\s\u00A0\u202F]?00$'), (m) => '${m[1]} h');
  }
  return t.replaceAll(' ', '\u00A0');
}

/// "2:15 p.m." today, otherwise "Thursday, October 29 at 8:30 a.m.".
String powerWhen(BuildContext context, DateTime at, DateTime now) {
  final local = at.toLocal(), today = now.toLocal();
  final sameDay = local.year == today.year && local.month == today.month && local.day == today.day;
  if (sameDay) return _time(context, local);
  return AppLocalizations.of(context).fireWhen(formatLongDay(context, local), _time(context, local));
}

/// A planned window: "Thursday, October 29, 8:30 a.m. to 12:00 p.m.", or
/// from one day to another.
String powerWindow(BuildContext context, DateTime from, DateTime to) {
  final l10n = AppLocalizations.of(context);
  final a = from.toLocal(), b = to.toLocal();
  if (a.year == b.year && a.month == b.month && a.day == b.day) {
    return l10n.powerWindowSameDay(formatLongDay(context, a), _time(context, a), _time(context, b));
  }
  String full(DateTime d) => l10n.fireWhen(formatLongDay(context, d), _time(context, d));
  return l10n.powerWindow(full(a), full(b));
}

String outageTitle(AppLocalizations l10n, OutageKind kind) => switch (kind) {
  OutageKind.outage => l10n.powerKindOutage,
  OutageKind.plannedInProgress => l10n.powerKindPlannedInProgress,
};

String crewLabel(AppLocalizations l10n, CrewStatus s) => switch (s) {
  CrewStatus.assigned => l10n.powerCrewAssigned,
  CrewStatus.onTheWay => l10n.powerCrewOnTheWay,
  CrewStatus.atWork => l10n.powerCrewAtWork,
};

String causeLabel(AppLocalizations l10n, OutageCause c) => switch (c) {
  OutageCause.equipment => l10n.powerCauseEquipment,
  OutageCause.weather => l10n.powerCauseWeather,
  OutageCause.accident => l10n.powerCauseAccident,
  OutageCause.vegetation => l10n.powerCauseVegetation,
  OutageCause.animal => l10n.powerCauseAnimal,
  OutageCause.plannedWork => l10n.powerCausePlannedWork,
};

/// Hydro-Québec's estimate, said as an estimate (spec D10); a planned
/// interruption in progress has an expected end instead. [short] is for
/// Today's card, where the screen one tap away names Hydro-Québec.
String endLine(BuildContext context, Outage o, DateTime now, {bool short = false}) {
  final l10n = AppLocalizations.of(context);
  final end = o.estimatedEndAt;
  if (end == null) return l10n.powerNoEstimate;
  final when = powerWhen(context, end, now);
  if (o.kind == OutageKind.plannedInProgress) return l10n.powerUntil(when);
  return short ? l10n.powerTodayEstimate(when) : l10n.powerEstimate(when);
}

/// The health of one list: current outages or planned interruptions.
({String text, bool problem})? powerHealthLine(
  BuildContext context,
  PowerRepository repository,
  DateTime now, {
  required bool planned,
  bool onlyWhenProblem = false,
}) {
  final l10n = AppLocalizations.of(context);
  if (repository.loading) return null;
  if (repository.failed) return (text: l10n.powerLoadFailed, problem: true);
  final s = repository.status;
  final checked = planned ? s?.plannedCheckedAt : s?.outagesCheckedAt;
  if (s == null || checked == null) return (text: l10n.powerNeverChecked, problem: true);
  final stale = planned ? s.plannedStale(now) : s.outagesStale(now);
  if (stale) return (text: l10n.powerCheckFailedSince(formatWhen(context, checked, now: now)), problem: true);
  if (onlyWhenProblem) return null;
  return (text: l10n.roadsCheckedAt(formatWhen(context, checked, now: now)), problem: false);
}

/// A current interruption: what, where, how many, since when, until when, crew, cause.
class OutageCard extends StatelessWidget {
  const OutageCard({super.key, required this.outage, required this.now});

  final Outage outage;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final o = outage;
    final details = <String>[
      l10n.powerCustomers(o.customers),
      l10n.powerSince(powerWhen(context, o.startedAt, now)),
      endLine(context, o, now),
      if (o.status != null) crewLabel(l10n, o.status!),
      if (o.cause != null && o.kind == OutageKind.outage) l10n.powerCause(causeLabel(l10n, o.cause!)),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(o.kind == OutageKind.outage ? Icons.power_off_outlined : Icons.engineering_outlined, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    outageTitle(l10n, o.kind),
                    style: textTheme.titleMedium?.copyWith(fontWeight: o.kind == OutageKind.outage ? FontWeight.bold : null),
                  ),
                  if (o.area == PowerArea.lacTee) Text(l10n.powerAreaLacTee, style: textTheme.labelLarge),
                  for (final d in details) ...[const SizedBox(height: 2), Text(d, style: textTheme.bodyLarge)],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An upcoming planned interruption: when, how many, moved from, backup date.
class PlannedCard extends StatelessWidget {
  const PlannedCard({super.key, required this.planned});

  final PlannedInterruption planned;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final p = planned;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.event_outlined, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(powerWindow(context, p.startsAt, p.endsAt), style: textTheme.titleMedium),
                  if (p.area == PowerArea.lacTee) Text(l10n.powerAreaLacTee, style: textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text(l10n.powerCustomers(p.customers), style: textTheme.bodyLarge),
                  if (p.originalStartsAt != null) ...[
                    const SizedBox(height: 2),
                    Text(l10n.powerMovedFrom(formatLongDay(context, p.originalStartsAt!.toLocal())), style: textTheme.bodyLarge),
                  ],
                  if (p.alternateStartsAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      l10n.powerAlternate(powerWindow(context, p.alternateStartsAt!, p.alternateEndsAt!)),
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Today's outage card (spec D9): only when the power is out (or planned
/// work is under way) here, a planned interruption is today or tomorrow, or
/// the check is failing. Amber, never red (red is for boil water and fire bans).
class PowerCard extends StatelessWidget {
  const PowerCard({super.key, required this.repository, required this.onOpen, this.now});

  final PowerRepository repository;
  final VoidCallback onOpen;
  final DateTime? now;

  static const _maxLines = 3;

  /// The lines to show, current interruptions first.
  static List<String> lines(BuildContext context, PowerRepository repository, DateTime now) {
    final l10n = AppLocalizations.of(context);
    final s = repository.status;
    if (s == null) return const [];
    String where(PowerArea area, String line) => area == PowerArea.lacTee ? l10n.powerAtLacTee(line) : line;
    return [
      for (final o in s.outages)
        where(o.area, '${o.kind == OutageKind.outage
            ? l10n.powerTodayOutage(o.customers, powerWhen(context, o.startedAt, now))
            : l10n.powerTodayWork(o.customers)} · ${endLine(context, o, now, short: true)}'),
      for (final p in s.soon(now)) where(p.area, l10n.powerTodayPlanned(powerWindow(context, p.startsAt, p.endsAt))),
    ];
  }

  /// Whether Today shows the card at all.
  static bool shows(BuildContext context, PowerRepository repository, DateTime now) =>
      lines(context, repository, now).isNotEmpty || staleLine(context, repository, now) != null;

  /// The current-outage check failing (or never done): said on Today, all year.
  static ({String text, bool problem})? staleLine(BuildContext context, PowerRepository repository, DateTime now) =>
      powerHealthLine(context, repository, now, planned: false, onlyWhenProblem: true);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final at = now ?? DateTime.now();
        final all = lines(context, repository, at);
        final stale = staleLine(context, repository, at);
        if (all.isEmpty && stale == null) return const SizedBox.shrink(); // Today checks [shows] first
        final amber = all.isNotEmpty;
        final colors = weatherAlertColors(context);
        final fg = amber ? colors.foreground : Theme.of(context).colorScheme.onSurface;
        final shown = all.take(_maxLines).toList();
        final content = Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(amber ? Icons.power_off_outlined : Icons.power_outlined, color: fg, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(l10n.powerTitle, style: textTheme.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.bold)),
                    ),
                    for (final line in shown) ...[
                      const SizedBox(height: 4),
                      Text(line, style: textTheme.bodyLarge?.copyWith(color: fg)),
                    ],
                    if (all.length > shown.length) ...[
                      const SizedBox(height: 4),
                      Text(l10n.powerMore(all.length - shown.length), style: textTheme.bodyMedium?.copyWith(color: fg)),
                    ],
                    if (stale != null) ...[
                      const SizedBox(height: 8),
                      // On amber the line keeps the amber text colour (contrast); the icon says it.
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
