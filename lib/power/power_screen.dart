import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../push/push_service.dart';
import '../settings/app_settings.dart';
import '../weather/weather_widgets.dart';
import '../widgets/links.dart';
import 'power_data.dart';
import 'power_repository.dart';
import 'power_widgets.dart';

/// The Power outages screen (spec D10): what's out now in Témiscaming and
/// at Lac Tee, planned interruptions in the next 14 days, and Hydro-Québec's
/// own caveats, phone number and map. Opened from More, from Today's card
/// and from an outage notification.
class PowerScreen extends StatelessWidget {
  const PowerScreen({super.key, required this.settings, required this.repository, required this.push, this.now});

  final AppSettings settings;
  final PowerRepository repository;

  /// For the "Notify me" switch (spec D7; phones only).
  final PushService push;

  /// For tests; defaults to the current time.
  final DateTime? now;

  Future<void> _setNotified(BuildContext context, bool on) async {
    if (!on) return settings.setPowerOutages(false);
    final messenger = ScaffoldMessenger.of(context);
    final denied = AppLocalizations.of(context).settingsPermissionDenied;
    if (await push.requestPermission()) {
      await settings.setPowerOutages(true);
    } else {
      messenger.showSnackBar(SnackBar(content: Text(denied)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.powerTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([repository, settings]),
          builder: (context, _) {
            final at = now ?? DateTime.now();
            final language = settings.language ?? AppLanguage.fr;
            if (repository.loading && repository.status == null) return const Center(child: CircularProgressIndicator());
            final s = repository.status;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (push.isSupported) ...[
                  Card(
                    margin: EdgeInsets.zero,
                    child: SwitchListTile(
                      secondary: const Icon(Icons.notifications_active_outlined),
                      title: Text(l10n.powerNotifyTitle),
                      subtitle: Text(l10n.powerNotifySubtitle),
                      value: settings.powerOutagesEnabled,
                      onChanged: (on) => _setNotified(context, on),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                _Heading(l10n.powerNowHeading),
                ..._section(
                  context,
                  health: powerHealthLine(context, repository, at, planned: false),
                  // "Nothing here" only after a recent successful check (principle 3).
                  checked: s != null && !s.outagesStale(at) && !repository.failed,
                  empty: l10n.powerNoOutage,
                  cards: [for (final o in s?.outages ?? const <Outage>[]) OutageCard(outage: o, now: at)],
                ),
                const SizedBox(height: 32),
                _Heading(l10n.powerPlannedHeading),
                ..._section(
                  context,
                  health: powerHealthLine(context, repository, at, planned: true),
                  checked: s != null && !s.plannedStale(at) && !repository.failed,
                  empty: l10n.powerNoPlanned,
                  cards: [for (final p in s?.upcoming(at) ?? const <PlannedInterruption>[]) PlannedCard(planned: p)],
                ),
                const SizedBox(height: 32),
                ..._about(context, s, language),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _section(
    BuildContext context, {
    required ({String text, bool problem})? health,
    required bool checked,
    required String empty,
    required List<Widget> cards,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return [
      if (health != null) ...[WeatherStatusLine(text: health.text, problem: health.problem), const SizedBox(height: 8)],
      ...cards,
      if (cards.isEmpty && checked)
        Row(
          children: [
            const Icon(Icons.check_circle_outline, size: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(empty, style: textTheme.bodyLarge)),
          ],
        ),
    ];
  }

  List<Widget> _about(BuildContext context, PowerStatus? s, AppLanguage language) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final map = language == AppLanguage.fr ? (s?.mapUrlFr ?? PowerLinks.mapFr) : (s?.mapUrlEn ?? PowerLinks.mapEn);
    return [
      _Heading(l10n.powerAboutHeading),
      Text(l10n.powerNotice, style: textTheme.bodyLarge),
      const SizedBox(height: 12),
      Text(l10n.powerDanger, style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      _Link(Icons.phone_outlined, l10n.powerReport(PowerLinks.reportPhone), PowerLinks.reportPhoneUri),
      _Link(Icons.open_in_new, l10n.powerMapLink, map),
      const SizedBox(height: 8),
      Text(l10n.powerSource, style: muted),
    ];
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(header: true, child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
  );
}

class _Link extends StatelessWidget {
  const _Link(this.icon, this.label, this.url);

  final IconData icon;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton.icon(
      icon: Icon(icon),
      label: Text(label),
      onPressed: () => openLink(Uri.parse(url)),
    ),
  );
}
