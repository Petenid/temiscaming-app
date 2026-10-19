import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/dates.dart';
import 'alerts_repository.dart';
import 'town_alert.dart';

/// The app's reserved urgent colour (research §5b): only for urgent things.
Color urgentColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
    ? const Color(0xFFB3261E)
    : const Color(0xFFFF8A80);

/// "Last checked 16:40", or in red "Couldn't check the Town's alerts since
/// 14:20" (principle 3: silence must never look like safety).
class SourceHealthLine extends StatelessWidget {
  const SourceHealthLine({super.key, required this.repository, this.onlyWhenStale = false});

  final AlertsRepository repository;

  /// On Today, say nothing when all is well.
  final bool onlyWhenStale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final health = repository.health;
    final now = DateTime.now();
    if (repository.loading) return const SizedBox.shrink();

    final String text;
    final bool problem;
    if (repository.failed) {
      text = l10n.alertsLoadFailed;
      problem = true;
    } else if (health == null || health.lastSuccessAt == null) {
      text = l10n.alertsNeverChecked;
      problem = true;
    } else if (health.isStale(now)) {
      text = l10n.alertsCheckFailedSince(formatWhen(context, health.lastSuccessAt!));
      problem = true;
    } else {
      text = l10n.alertsLastChecked(formatWhen(context, health.lastSuccessAt!));
      problem = false;
    }
    if (onlyWhenStale && !problem) return const SizedBox.shrink();

    final color = problem
        ? urgentColor(context)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        // Icon + words, never colour alone (DESIGN §7).
        Icon(problem ? Icons.error_outline : Icons.check_circle_outline, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
        ),
      ],
    );
  }
}

/// "In effect" / "Lifted" / "Expired", or nothing (lifting notices, and
/// old advisories the Town never marked lifted).
String? statusLabel(BuildContext context, TownAlert alert, DateTime now) {
  final l10n = AppLocalizations.of(context);
  if (alert.isLiftingNotice) return null;
  return switch (alert.status) {
    AlertStatus.active => alert.isInEffect(now) ? l10n.alertStatusInEffect : null,
    AlertStatus.lifted => l10n.alertStatusLifted,
    AlertStatus.expired => l10n.alertStatusExpired,
  };
}

/// A small outlined tag; urgent ones are red with an icon.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.urgent});

  final String label;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final color = urgent ? urgentColor(context) : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
    );
  }
}

/// Red banner on Today while a boil-water advisory is in effect.
class BoilWaterBanner extends StatelessWidget {
  const BoilWaterBanner({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final red = urgentColor(context);
    final onRed = Theme.of(context).brightness == Brightness.light ? Colors.white : Colors.black;
    return Material(
      color: red,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.water_drop, color: onRed, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.bannerBoilTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: onRed,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.bannerBoilBody,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: onRed),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
