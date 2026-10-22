import 'package:flutter/material.dart';

import '../alerts/alert_widgets.dart' show urgentColor;
import '../l10n/app_localizations.dart';
import '../push/push_service.dart';
import '../settings/app_settings.dart';
import '../weather/weather_widgets.dart' show WeatherStatusLine;
import '../widgets/dates.dart';
import '../widgets/links.dart';
import 'fire_data.dart';
import 'fire_repository.dart';

/// "Thursday, October 22 at 8:00 a.m." / "jeudi 22 octobre à 8 h 00".
String fireWhen(BuildContext context, DateTime at) {
  final local = at.toLocal();
  return AppLocalizations.of(context).fireWhen(formatLongDay(context, local), formatTime(context, local));
}

String fireLayerName(AppLocalizations l10n, FireLayer layer) =>
    layer == FireLayer.ifco ? l10n.fireIfcoName : l10n.fireIcafName;

/// The layer's state in words. "None" is only said after a recent check:
/// callers show the health line instead when the check is stale. An
/// announced ban is never called "in effect" before it starts.
String fireStateText(AppLocalizations l10n, FireLayerStatus s, DateTime now) => switch (s.state) {
  FireLayerState.town => s.isUpcoming(now) ? l10n.fireStateIfcoAnnounced : l10n.fireStateIfcoTown,
  FireLayerState.around => s.isUpcoming(now) ? l10n.fireStateIcafAnnounced : l10n.fireStateIcafAround,
  FireLayerState.region => l10n.fireStateRegion('${s.nearestKm ?? '—'}'),
  FireLayerState.none => s.layer == FireLayer.ifco ? l10n.fireStateIfcoNone : l10n.fireStateIcafNone,
};

/// What to say about the fire-ban check, or null when all is well and
/// [onlyWhenProblem] is set. Both layers must have been read recently.
({String text, bool problem})? fireHealth(
  BuildContext context,
  FireRepository repository,
  DateTime now, {
  bool onlyWhenProblem = false,
}) {
  final l10n = AppLocalizations.of(context);
  if (repository.loading) return null;
  if (repository.failed) return (text: l10n.fireLoadFailed, problem: true);
  final s = repository.status;
  final layers = [s?.ifco, s?.icaf];
  if (layers.any((l) => l == null)) return (text: l10n.fireNeverChecked, problem: true);
  final oldest = layers.map((l) => l!.checkedAt).reduce((a, b) => a.isBefore(b) ? a : b);
  if (layers.any((l) => l!.isStale(now))) {
    return (text: l10n.fireCheckFailedSince(formatWhen(context, oldest, now: now)), problem: true);
  }
  if (onlyWhenProblem) return null;
  return (text: l10n.fireCheckedAt(formatWhen(context, oldest, now: now)), problem: false);
}

/// The text on red for the urgent colour, as on the boil-water banner.
Color onUrgent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light ? Colors.white : Colors.black;

/// Red banner on Today while a ban applies to Témiscaming, or has been
/// announced (red is reserved for boil water and fire bans, DESIGN §7).
class FireBanBanner extends StatelessWidget {
  const FireBanBanner({super.key, required this.layers, required this.onTap, this.now});

  /// The layers in effect (or announced) here, open-fire ban first.
  final List<FireLayerStatus> layers;
  final VoidCallback onTap;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final fg = onUrgent(context);
    final at = now ?? DateTime.now();
    String body(FireLayerStatus s) {
      final ifco = s.layer == FireLayer.ifco;
      if (s.isUpcoming(at)) {
        final when = fireWhen(context, s.startsAt!);
        return ifco ? l10n.fireBannerIfcoUpcoming(when) : l10n.fireBannerIcafUpcoming(when);
      }
      return ifco ? l10n.fireBannerIfcoNow : l10n.fireBannerIcafNow;
    }

    return Material(
      color: urgentColor(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.local_fire_department, color: fg, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, s) in layers.indexed) ...[
                      if (i > 0) const SizedBox(height: 12),
                      Text(
                        fireLayerName(l10n, s.layer),
                        style: textTheme.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(body(s), style: textTheme.bodyMedium?.copyWith(color: fg)),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today's fire card (spec D8): during fire season, or whenever there's a
/// ban or a problem. The status in a line, then SOPFEU's fire danger.
class FireCard extends StatelessWidget {
  const FireCard({super.key, required this.settings, required this.repository, required this.onOpen, this.now});

  final AppSettings settings;
  final FireRepository repository;
  final VoidCallback onOpen;
  final DateTime? now;

  /// Whether Today shows the card at all.
  static bool shows(FireRepository repository, DateTime now) {
    if (repository.loading) return false;
    if (isFireSeason(now)) return true;
    final s = repository.status;
    if (s?.anyBan ?? false) return true;
    // A problem shows all year: silence must never look like safety.
    return repository.failed || s?.ifco == null || s?.icaf == null ||
        s!.ifco!.isStale(now) || s.icaf!.isStale(now);
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
        final s = repository.status;
        final health = fireHealth(context, repository, at, onlyWhenProblem: true);
        final lines = <Widget>[];
        for (final layer in [s?.ifco, s?.icaf]) {
          if (layer == null) continue;
          final none = layer.state == FireLayerState.none;
          // Stale and no ban known: say nothing (the red health line says it).
          if (layer.isStale(at) && !layer.isHere) continue;
          // The forest access ban only gets a line when there's something to say.
          if (layer.layer == FireLayer.icaf && none) continue;
          // No ban: one line. A ban: its name, then its state for Témiscaming.
          lines.add(_StateLine(
            text: none ? fireStateText(l10n, layer, at) : fireLayerName(l10n, layer.layer),
            here: layer.isHere,
          ));
          if (!none) {
            lines.add(Padding(
              padding: const EdgeInsetsDirectional.only(start: 32),
              child: Text(fireStateText(l10n, layer, at), style: textTheme.bodyLarge),
            ));
          }
          if (layer.isHere && layer.startsAt != null) {
            lines.add(Padding(
              padding: const EdgeInsetsDirectional.only(start: 32),
              child: Text(
                layer.isUpcoming(at) ? l10n.fireStarts(fireWhen(context, layer.startsAt!)) : l10n.fireSince(fireWhen(context, layer.startsAt!)),
                style: textTheme.bodyMedium,
              ),
            ));
          }
          if (none && layer.noneSince != null) {
            lines.add(Padding(
              padding: const EdgeInsetsDirectional.only(start: 32),
              child: Text(l10n.fireNoneInQuebecSince(formatDate(context, layer.noneSince!)), style: textTheme.bodyMedium),
            ));
          }
        }
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(header: true, child: Text(l10n.fireTitle, style: textTheme.titleSmall)),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...lines,
                  if (health != null) ...[
                    if (lines.isNotEmpty) const SizedBox(height: 8),
                    WeatherStatusLine(text: health.text, problem: health.problem),
                  ],
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: Text(l10n.fireDangerLink),
                      onPressed: () => openLink(Uri.parse(
                        language == AppLanguage.fr ? (s?.sopfeuUrlFr ?? FireLinks.sopfeuFr) : (s?.sopfeuUrlEn ?? FireLinks.sopfeuEn),
                      )),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A ban's state with an icon: red fire when it applies here (icon + words,
/// never colour alone, DESIGN §7).
class _StateLine extends StatelessWidget {
  const _StateLine({required this.text, required this.here});

  final String text;
  final bool here;

  @override
  Widget build(BuildContext context) {
    final color = here ? urgentColor(context) : Theme.of(context).colorScheme.onSurface;
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: color,
      fontWeight: here ? FontWeight.bold : null,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(here ? Icons.local_fire_department : Icons.check_circle_outline, color: color, size: 24),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

/// Offered once on Today to people who answered the notifications question
/// before fire bans existed (spec D7). Either button hides it for good.
class FireOptInCard extends StatelessWidget {
  const FireOptInCard({super.key, required this.settings, required this.push});

  final AppSettings settings;
  final PushService push;

  Future<void> _turnOn(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final denied = AppLocalizations.of(context).settingsPermissionDenied;
    final granted = await push.requestPermission();
    await settings.setFireBans(granted);
    if (!granted) messenger.showSnackBar(SnackBar(content: Text(denied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.notifications_active_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(header: true, child: Text(l10n.fireOptInTitle, style: textTheme.titleMedium)),
                      const SizedBox(height: 4),
                      Text(l10n.fireOptInBody, style: textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(onPressed: () => settings.setFireBans(false), child: Text(l10n.fireOptInNo)),
                  FilledButton(onPressed: () => _turnOn(context), child: Text(l10n.fireOptInYes)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
