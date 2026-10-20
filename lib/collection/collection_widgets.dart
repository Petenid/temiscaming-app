import 'package:flutter/material.dart';

import '../alerts/alert_widgets.dart' show urgentColor;
import '../l10n/app_localizations.dart';
import '../widgets/dates.dart';
import 'collection_repository.dart';
import 'pickup.dart';

/// Links for the schedule screen (DESIGN §2: always link to the source).
const townCalendarUrlFr = 'https://www.temiscaming.net/fr/calendrier';
const townCalendarUrlEn = 'https://www.temiscaming.net/en/calendar';

/// The MRC's printed calendar for the current year. Update each year
/// together with `functions/data/mrc-<year>.json` (README).
const mrcCalendarUrl = 'https://www.temiscaming.net/file-24778';

/// "Calendar checked 16:40", or in red "Couldn't check the Town's calendar
/// since 14:20" (principle 3). Same idea as the alerts' health line.
class CollectionHealthLine extends StatelessWidget {
  const CollectionHealthLine({super.key, required this.repository, this.onlyWhenStale = false});

  final CollectionRepository repository;
  final bool onlyWhenStale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (repository.loading) return const SizedBox.shrink();
    final health = repository.health;
    final String text;
    final bool problem;
    if (repository.failed) {
      text = l10n.collectionLoadFailed;
      problem = true;
    } else if (health == null || health.lastSuccessAt == null) {
      text = l10n.collectionNeverChecked;
      problem = true;
    } else if (health.isStale(DateTime.now())) {
      text = l10n.collectionCheckFailedSince(formatWhen(context, health.lastSuccessAt!));
      problem = true;
    } else {
      text = l10n.collectionLastChecked(formatWhen(context, health.lastSuccessAt!));
      problem = false;
    }
    if (onlyWhenStale && !problem) return const SizedBox.shrink();
    final color = problem ? urgentColor(context) : Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(problem ? Icons.error_outline : Icons.check_circle_outline, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
        ),
      ],
    );
  }
}

/// Small labels next to a pickup: moved, cancelled, from the MRC calendar.
List<String> pickupNotes(BuildContext context, Pickup p) {
  final l10n = AppLocalizations.of(context);
  return [
    if (p.cancelled) l10n.collectionCancelled,
    if (p.isMoved && !p.cancelled) l10n.collectionMoved(formatShortDay(context, p.previousDate!)),
    if (p.origin == PickupOrigin.mrc) l10n.collectionFromMrc,
  ];
}
