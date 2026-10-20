import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../settings/sector.dart';
import '../widgets/dates.dart';
import 'bin_icon.dart';
import 'collection_repository.dart';
import 'collection_widgets.dart';
import 'schedule.dart';

/// Today's bin card: "This week: blue bin, Tuesday", then the next pickup
/// (DESIGN §6.2). Tapping opens the full schedule.
class CollectionCard extends StatelessWidget {
  const CollectionCard({
    super.key,
    required this.settings,
    required this.repository,
    required this.onOpenSchedule,
    this.now,
  });

  final AppSettings settings;
  final CollectionRepository repository;
  final VoidCallback onOpenSchedule;

  /// For tests; defaults to the current time.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final sector = settings.sector ?? Sector.town;
        final today = dateOnly(now ?? DateTime.now());
        final ov = overview(
          repository.pickups,
          sector,
          today,
          knownThrough: repository.health?.knownThrough,
        );
        final waiting = repository.loading && repository.pickups.isEmpty;

        final lines = <Widget>[];
        if (ov.noPickupThisWeek) {
          lines.add(Text(l10n.collectionNoPickupThisWeek, style: textTheme.titleMedium));
        }
        final next = ov.next;
        if (next != null) {
          final bins = binsInSentence(l10n, next.bins);
          final headline = switch (whenLabel(next.date, today)) {
            WhenLabel.today => l10n.collectionToday(bins),
            WhenLabel.thisWeek => l10n.collectionThisWeek(bins, formatWeekday(context, next.date)),
            WhenLabel.nextWeek => l10n.collectionNextWeek(bins, formatWeekday(context, next.date)),
            WhenLabel.later => l10n.collectionOnDate(bins, formatShortDay(context, next.date)),
          };
          lines.add(Row(
            children: [
              for (final b in next.bins) ...[BinIcon(b, size: 36), const SizedBox(width: 4)],
              const SizedBox(width: 8),
              Expanded(child: Text(headline, style: textTheme.titleLarge)),
            ],
          ));
          final notes = {for (final p in next.pickups) ...pickupNotes(context, p)};
          if (notes.isNotEmpty) {
            lines.add(Text(notes.join(' · '), style: textTheme.bodyMedium));
          }
        }
        final then = ov.then;
        if (then != null) {
          lines.add(Text(
            l10n.collectionThen(binsInSentence(l10n, then.bins), formatShortDay(context, then.date)),
            style: textTheme.bodyLarge,
          ));
        }
        for (final s in ov.specialsThisWeek) {
          lines.add(Text(
            l10n.collectionAlsoThisWeek(specialName(l10n, s.special!), formatShortDay(context, s.date)),
            style: textTheme.bodyLarge,
          ));
        }
        if (!waiting && !repository.failed) {
          if (next == null && ov.notPostedAfter == null) {
            lines.add(Text(l10n.collectionNothingPosted, style: textTheme.bodyLarge));
          } else if (ov.notPostedAfter != null) {
            lines.add(Text(
              l10n.collectionNotPostedAfter(formatLongDay(context, ov.notPostedAfter!)),
              style: textTheme.bodyMedium,
            ));
          }
        }

        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpenSchedule,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(l10n.collectionCardTitle, style: textTheme.titleSmall),
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (waiting) const LinearProgressIndicator(),
                  for (final line in lines) ...[line, const SizedBox(height: 8)],
                  CollectionHealthLine(repository: repository, onlyWhenStale: true),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
