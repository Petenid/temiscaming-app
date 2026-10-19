import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../widgets/dates.dart';
import '../widgets/links.dart';
import 'alert_widgets.dart';
import 'alerts_repository.dart';
import 'town_alert.dart';

/// One alert: the Town's full text, in its original language, with a link
/// to the Town's own page (principle 2: we relay, we don't replace).
class AlertDetailScreen extends StatelessWidget {
  const AlertDetailScreen({super.key, required this.alert, required this.language});

  final TownAlert alert;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();
    final shownIn = alert.displayLanguage(language);
    final status = statusLabel(context, alert, now);
    final sourceUrl = alert.sourceUrl(language);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.alertsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (shownIn != language) ...[
              _Notice(
                icon: Icons.translate,
                text: shownIn == AppLanguage.fr ? l10n.alertOnlyFrench : l10n.alertOnlyEnglish,
              ),
              const SizedBox(height: 16),
            ],
            Semantics(
              header: true,
              child: Text(alert.title(language), locale: shownIn.locale, style: textTheme.headlineSmall),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.alertPosted(formatWhen(context, alert.publishedAt)), style: textTheme.bodyMedium),
                if (status != null)
                  StatusChip(label: status, urgent: alert.isWater && alert.isInEffect(now)),
              ],
            ),
            const SizedBox(height: 16),
            SelectableText(alert.body(language), style: textTheme.bodyLarge),
            if (alert.bodyIsExcerpt) ...[
              const SizedBox(height: 16),
              _Notice(icon: Icons.info_outline, text: l10n.alertExcerptNote),
            ],
            const SizedBox(height: 24),
            if (sourceUrl.isNotEmpty)
              FilledButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: Text(l10n.alertViewOnSite),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => openLink(Uri.parse(sourceUrl)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Opens an alert by id, e.g. from a tapped notification.
class AlertByIdScreen extends StatelessWidget {
  const AlertByIdScreen({
    super.key,
    required this.id,
    required this.repository,
    required this.language,
  });

  final String id;
  final AlertsRepository repository;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TownAlert?>(
      future: repository.byId(id),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final alert = snap.data;
        if (alert == null) {
          return Scaffold(
            appBar: AppBar(title: Text(AppLocalizations.of(context).alertsTitle)),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(AppLocalizations.of(context).alertNotFound),
            ),
          );
        }
        return AlertDetailScreen(alert: alert, language: language);
      },
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
