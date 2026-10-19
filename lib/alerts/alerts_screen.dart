import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../widgets/dates.dart';
import '../widgets/links.dart';
import 'alert_detail_screen.dart';
import 'alert_widgets.dart';
import 'alerts_repository.dart';
import 'town_alert.dart';

/// The Town's sign-up page for its official alerts (DESIGN §6.1: always visible).
Uri signUpUrl(AppLanguage language) => Uri.parse(
  language == AppLanguage.fr
      ? 'https://temiscaming.alertesmunicipales.com/inscrivez-vous'
      : 'https://temiscaming.alertesmunicipales.com/register',
);

/// Town alerts, newest first.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({
    super.key,
    required this.settings,
    required this.repository,
    required this.appBarActions,
  });

  final AppSettings settings;
  final AlertsRepository repository;
  final List<Widget> appBarActions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = settings.language ?? AppLanguage.fr;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.alertsTitle), actions: appBarActions),
      body: ListenableBuilder(
        listenable: repository,
        builder: (context, _) {
          final now = DateTime.now();
          final alerts = repository.alerts;
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: SourceHealthLine(repository: repository),
              ),
              if (repository.loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (alerts.isEmpty && !repository.failed)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l10n.alertsEmpty),
                ),
              for (final alert in alerts) ...[
                _AlertTile(alert: alert, language: language, now: now),
                const Divider(height: 1),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: Text(l10n.alertsSignUp),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () => openLink(signUpUrl(language)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Text(
                  l10n.alertsSourceNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert, required this.language, required this.now});

  final TownAlert alert;
  final AppLanguage language;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = statusLabel(context, alert, now);
    final shownIn = alert.displayLanguage(language);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: alert.isWater
          ? Icon(Icons.water_drop_outlined, semanticLabel: l10n.alertWaterLabel)
          : const Icon(Icons.campaign_outlined),
      title: Text(
        alert.title(language),
        // Lets screen readers pronounce a French-only title in French.
        locale: shownIn.locale,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(formatDate(context, alert.publishedAt)),
            if (status != null)
              StatusChip(label: status, urgent: alert.isWater && alert.isInEffect(now)),
          ],
        ),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AlertDetailScreen(alert: alert, language: language),
        ),
      ),
    );
  }
}
