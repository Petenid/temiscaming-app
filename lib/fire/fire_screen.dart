import 'package:flutter/material.dart';

import '../alerts/alert_widgets.dart' show urgentColor;
import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../weather/weather_widgets.dart' show WeatherStatusLine;
import '../widgets/dates.dart';
import '../widgets/links.dart';
import 'fire_data.dart';
import 'fire_repository.dart';
import 'fire_widgets.dart';

/// The Fire screen (fire-bans spec D9): each ban's status for Témiscaming,
/// what it means, and the official pages. Opened from Today's banner or
/// card, and from a fire-ban notification.
class FireScreen extends StatelessWidget {
  const FireScreen({super.key, required this.settings, required this.repository, this.now});

  final AppSettings settings;
  final FireRepository repository;

  /// For tests; defaults to the current time.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = settings.language ?? AppLanguage.fr;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.fireTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: repository,
          builder: (context, _) {
            final at = now ?? DateTime.now();
            final s = repository.status;
            if (repository.loading && s == null) return const Center(child: CircularProgressIndicator());
            final health = fireHealth(context, repository, at);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final layer in FireLayer.values) ...[
                  _LayerSection(layer: layer, status: s?.layer(layer), now: at),
                  const SizedBox(height: 24),
                ],
                if (health != null) WeatherStatusLine(text: health.text, problem: health.problem),
                const SizedBox(height: 24),
                ..._sources(context, s, language),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _sources(BuildContext context, FireStatus? s, AppLanguage language) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    Widget link(String label, String url) => Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        icon: const Icon(Icons.open_in_new),
        label: Text(label),
        onPressed: () => openLink(Uri.parse(url)),
      ),
    );
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(header: true, child: Text(l10n.fireSourcesHeading, style: textTheme.titleLarge)),
      ),
      Text(l10n.fireOfficialNote, style: textTheme.bodyLarge),
      const SizedBox(height: 8),
      Text(l10n.fireTownRulesNote, style: textTheme.bodyLarge),
      const SizedBox(height: 8),
      link(l10n.fireOfficialLink, s?.officialUrlFr ?? FireLinks.officialFr),
      link(l10n.fireMapLink, s?.mapUrl ?? FireLinks.map),
      link(l10n.fireDangerLink, language == AppLanguage.fr ? (s?.sopfeuUrlFr ?? FireLinks.sopfeuFr) : (s?.sopfeuUrlEn ?? FireLinks.sopfeuEn)),
      const SizedBox(height: 8),
      Text(l10n.fireSource, style: textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ];
  }
}

/// One ban: its name, its state here (never "none" after a failed check),
/// when it started or starts, and what it means.
class _LayerSection extends StatelessWidget {
  const _LayerSection({required this.layer, required this.status, required this.now});

  final FireLayer layer;
  final FireLayerStatus? status;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final s = status;
    final here = s?.isHere ?? false;
    final red = urgentColor(context);
    final Widget state;
    if (s == null) {
      state = WeatherStatusLine(text: l10n.fireNeverChecked, problem: true);
    } else if (s.isStale(now) && !here) {
      state = WeatherStatusLine(text: l10n.fireCheckFailedSince(formatWhen(context, s.checkedAt, now: now)), problem: true);
    } else {
      final color = here ? red : Theme.of(context).colorScheme.onSurface;
      state = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            here ? Icons.local_fire_department : s.state == FireLayerState.region ? Icons.info_outline : Icons.check_circle_outline,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              fireStateText(l10n, s, now),
              style: textTheme.titleMedium?.copyWith(color: color, fontWeight: here ? FontWeight.bold : null),
            ),
          ),
        ],
      );
    }
    final meaning = layer == FireLayer.ifco ? l10n.fireIfcoMeaning : l10n.fireIcafMeaning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Semantics(header: true, child: Text(fireLayerName(l10n, layer), style: textTheme.titleLarge)),
        ),
        state,
        if (s != null && here && s.startsAt != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 40),
            child: Text(
              s.isUpcoming(now) ? l10n.fireStarts(fireWhen(context, s.startsAt!)) : l10n.fireSince(fireWhen(context, s.startsAt!)),
              style: textTheme.bodyLarge,
            ),
          ),
        ],
        if (s != null && here && s.isStale(now)) ...[
          const SizedBox(height: 8),
          WeatherStatusLine(text: l10n.fireCheckFailedSince(formatWhen(context, s.checkedAt, now: now)), problem: true),
        ],
        if (s != null && !s.isStale(now) && s.state == FireLayerState.none && s.noneSince != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 40),
            child: Text(l10n.fireNoneInQuebecSince(formatDate(context, s.noneSince!)), style: textTheme.bodyLarge),
          ),
        ],
        const SizedBox(height: 12),
        Text(l10n.fireMeaningHeading, style: textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(meaning, style: textTheme.bodyLarge),
      ],
    );
  }
}
