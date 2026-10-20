import 'package:flutter/material.dart';

import '../alerts/alert_widgets.dart' show StatusChip;
import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../settings/sector.dart';
import '../widgets/dates.dart';
import '../widgets/links.dart';
import 'bin_icon.dart';
import 'collection_repository.dart';
import 'collection_widgets.dart';
import 'schedule.dart';

/// The next 8 weeks of pickups for the user's sector, with the source's
/// health and links to the Town's and the MRC's calendars (spec §6).
class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key, required this.settings, required this.repository, this.now});

  final AppSettings settings;
  final CollectionRepository repository;
  final DateTime? now;

  static const weeksShown = 8;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final language = settings.language ?? AppLanguage.fr;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.collectionScheduleTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: repository,
          builder: (context, _) {
            final sector = settings.sector ?? Sector.town;
            final today = dateOnly(now ?? DateTime.now());
            final days = pickupDays(
              repository.pickups,
              sector,
              from: today,
              until: addDays(mondayOf(today), weeksShown * 7),
            );
            final ov = overview(repository.pickups, sector, today, knownThrough: repository.health?.knownThrough);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(sector.displayName(context), style: textTheme.titleMedium),
                const SizedBox(height: 8),
                CollectionHealthLine(repository: repository),
                if (ov.notPostedAfter != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.collectionNotPostedAfter(formatLongDay(context, ov.notPostedAfter!)),
                    style: textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 8),
                if (days.isEmpty && !repository.loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(l10n.collectionNothingPosted, style: textTheme.bodyLarge),
                  ),
                for (final day in days) _DayBlock(day: day),
                const Divider(height: 32),
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: Text(l10n.collectionTownCalendarLink),
                  onPressed: () => openLink(Uri.parse(
                    language == AppLanguage.fr ? townCalendarUrlFr : townCalendarUrlEn,
                  )),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: Text(l10n.collectionMrcCalendarLink),
                  onPressed: () => openLink(Uri.parse(mrcCalendarUrl)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DayBlock extends StatelessWidget {
  const _DayBlock({required this.day});

  final PickupDay day;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final heading = formatLongDay(context, day.date);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              heading[0].toUpperCase() + heading.substring(1),
              style: textTheme.titleSmall,
            ),
          ),
          for (final p in day.pickups)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.material != null) BinIcon(p.material!) else const SpecialCollectionIcon(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.material != null ? binFullName(l10n, p.material!) : specialName(l10n, p.special ?? ''),
                          style: textTheme.bodyLarge,
                        ),
                        if (pickupNotes(context, p).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final note in pickupNotes(context, p))
                                  StatusChip(label: note, urgent: p.cancelled && note == l10n.collectionCancelled),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
